<?php

namespace App\Services;

use App\Support\UnitFactors;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;

/**
 * Order creation exactly as described in ORDER_LIFECYCLE_FOR_NEW_FRONTEND.md
 * (the consumer app's calculateOrderDetails.php → placeNewOrder.php →
 * cancelOrder.php). Where that document lists a bug (§13), the FIXED
 * behaviour is implemented:
 *   - delivery_info comes from the chosen address (gotcha 1)
 *   - orders.items_count is per vendor, free items excluded (gotchas 2/3)
 *   - the client total is compared with the real master total (gotcha 4)
 *   - every write is in one DB transaction (gotcha 5)
 *   - a promo is logged / max_use decremented once per order (gotcha 6)
 *   - cancel removes an orphaned master_orders row (gotcha 8)
 *   - no offer_log write during preview (gotcha 11)
 *   - the vendor discount split is deterministic
 *
 * The cart is on hold (see sapeksh_prod_audit.md): the item list comes from the
 * CRM app ({product_id, vendor_product_id, pack_id, quantity}) and is turned
 * into the doc's per-vendor `cartList` here; everything after that follows the
 * document.
 */
class OrderPlacementService
{
    /** CRM-placed orders carry txn_id = 'crm' + 17 hex chars (20 chars, random). */
    public const TXN_PREFIX = 'crm';

    // ═════════════════════════════════════════════ preview (calculateOrderDetails)

    /**
     * @param array<array{product_id:int|string, vendor_product_id:int|string, pack_id:string, quantity:int}> $lines
     * @return array the doc's preview shape (+ 'vendors' with everything place() needs)
     */
    public function calculate(int $userId, int $addressId, array $lines, ?string $promoCode): array
    {
        $this->assertCustomer($userId);
        $address = $this->addressRow($userId, $addressId);
        if (empty($lines)) {
            $this->fail('items', 'Add at least one product to the order.');
        }

        $isNewCustomer = !DB::table('orders')->where('buyer_userid', $userId)->exists();
        $offers        = $this->activeOffers($userId);

        // ── cartList per vendor (doc §5 step 4/5)
        $byVendor = [];
        foreach ($this->resolveLines($lines) as $line) {
            $byVendor[$line['vendor_id']][] = $line;
        }
        ksort($byVendor);

        $vendors = [];
        foreach ($byVendor as $vendorId => $cartList) {
            $cfg      = $this->deliveryConfig((int) $vendorId);
            $subtotal = 0.0;
            $byCtype  = [];
            foreach ($cartList as $l) {
                $subtotal += $l['item_total'];
                $byCtype[$l['ctype']] = ($byCtype[$l['ctype']] ?? 0) + $l['item_total'];
            }

            $freeItems     = [];
            $offerDiscount = 0.0;
            $appliedOffers = []; // offer id per free-item row (doc §2.5)

            // prod_on_prod — buy X pack, get Y free (doc §5)
            foreach ($offers['prod_on_prod'] as $o) {
                $d = $o['data'];
                foreach ($cartList as $l) {
                    $conQty = max(1, (int) ($d['con_qty'] ?? 1));
                    if ((string) $l['pack_id'] !== (string) ($d['con_pid'] ?? '') || $l['quantity'] < $conQty) {
                        continue;
                    }
                    $qty = intdiv($l['quantity'], $conQty) * max(1, (int) ($d['eff_qty'] ?? 1));
                    if ($free = $this->freeItem((int) ($d['eff_prod_id'] ?? 0), (string) ($d['eff_pid'] ?? ''), $qty, (int) $vendorId, $o)) {
                        $freeItems[] = $free;
                        $appliedOffers[] = $o['id'];
                    }
                }
            }

            // new_customer_product — free item for a first order (doc §5)
            if ($isNewCustomer) {
                foreach ($offers['new_customer_product'] as $o) {
                    $d = $o['data'];
                    if ($subtotal < (float) ($d['min_order_value'] ?? 0)) continue;
                    if ($free = $this->freeItem((int) ($d['eff_prod_id'] ?? 0), (string) ($d['eff_pid'] ?? ''), max(1, (int) ($d['eff_qty'] ?? 1)), (int) $vendorId, $o)) {
                        $freeItems[] = $free;
                        $appliedOffers[] = $o['id'];
                    }
                }
            }

            // off_on_total — % off the category total; highest % per ctype (doc §5)
            $bestPct = [];
            foreach ($offers['off_on_total'] as $o) {
                $d     = $o['data'];
                $ctype = (string) ($d['ctype'] ?? 'all');
                $base  = $ctype === 'all' ? $subtotal : ($byCtype[$ctype] ?? 0);
                if ($base <= 0 || $base < (float) ($d['total'] ?? 0)) continue;
                $pct = (float) ($d['discount'] ?? 0);
                if ($pct > ($bestPct[$ctype]['pct'] ?? 0)) {
                    $bestPct[$ctype] = ['pct' => $pct, 'base' => $base, 'id' => $o['id']];
                }
            }
            // not written to offer_log — the doc logs free items and the
            // new-customer discount only (§2.5)
            foreach ($bestPct as $b) {
                $offerDiscount += round($b['base'] * $b['pct'] / 100, 2);
            }

            // prod_on_total — free item(s) once the category total crosses a threshold (doc §5)
            foreach ($offers['prod_on_total'] as $o) {
                $d     = $o['data'];
                $ctype = (string) ($d['ctype'] ?? 'all');
                $base  = $ctype === 'all' ? $subtotal : ($byCtype[$ctype] ?? 0);
                if ($base <= 0 || $base < (float) ($d['total'] ?? 0)) continue;
                $qty = $this->ladderValue($d['eff_qty'] ?? 1, $base);
                if ($qty <= 0) continue;
                $pids  = (array) ($d['eff_pid'] ?? []);
                $prods = (array) ($d['eff_prod_id'] ?? []);
                foreach (array_values($pids) as $i => $pid) {
                    $productId = (int) ($prods[$i] ?? 0) ?: (int) $o['product_id'];
                    if ($free = $this->freeItem($productId, (string) $pid, (int) $qty, (int) $vendorId, $o)) {
                        $freeItems[] = $free;
                        $appliedOffers[] = $o['id'];
                    }
                }
            }

            // delivery charge (doc §4): compared with the before-discount subtotal
            $deliveryCharge = 0.0;
            if ($cfg['min_total'] > 0 && $subtotal < $cfg['min_total']) {
                $deliveryCharge = $cfg['delivery_charge'];
            }
            $beforeDiscount = round($subtotal + $deliveryCharge, 2);

            $vendors[$vendorId] = [
                'vendor_id'           => (int) $vendorId,
                'cartList'            => $cartList,
                'freeItems'           => $freeItems,
                'subtotal'            => round($subtotal, 2),
                'deliveryCharge'      => round($deliveryCharge, 2),
                'beforeDiscount'      => $beforeDiscount,
                'offerDiscount'       => min(round($offerDiscount, 2), $beforeDiscount),
                'promoCodeDiscount'   => 0.0,
                'newCustomerDiscount' => 0.0,
                'afterDiscount'       => 0.0,
                'timeSlotText'        => $this->timeSlotText($cfg),
                'freeDeliMinTotal'    => $cfg['min_total'],
                'deliCharge'          => $cfg['delivery_charge'],
                // one offer_log row per free item + the new-customer discount (doc §2.5)
                'appliedOffers'       => $appliedOffers,
            ];
        }

        $itemsSubtotal = array_sum(array_column($vendors, 'subtotal'));

        // promo (doc §5 step 6, §9)
        $promo = $this->resolvePromo($promoCode, $userId, $itemsSubtotal);

        // new-customer discount (doc §5 step 7)
        $newCustomerDiscount = 0.0;
        if ($isNewCustomer) {
            foreach ($offers['new_customer_discount'] as $o) {
                $d = $o['data'];
                if ($itemsSubtotal < (float) ($d['min_order_value'] ?? 0)) continue;
                $value = (float) ($d['discount'] ?? 0);
                $type  = strtolower((string) ($d['discount_type'] ?? $d['type'] ?? 'fixed'));
                $amt   = str_starts_with($type, 'percent') ? $itemsSubtotal * $value / 100 : $value;
                if ($amt > $newCustomerDiscount) {
                    $newCustomerDiscount = round($amt, 2);
                    $newCustomerOfferId  = $o['id'];
                }
            }
        }

        // distribute promo + new-customer discount: vendor 108 first, then by vendor id (doc §5 step 8, deterministic)
        $order = array_keys($vendors);
        usort($order, fn ($a, $b) => [(int) $a !== 108, (int) $a] <=> [(int) $b !== 108, (int) $b]);
        foreach (['promoCodeDiscount' => $promo['discount'], 'newCustomerDiscount' => $newCustomerDiscount] as $key => $amount) {
            $left = $amount;
            foreach ($order as $vid) {
                if ($left <= 0) break;
                $room = $vendors[$vid]['beforeDiscount'] - $vendors[$vid]['offerDiscount'] - $vendors[$vid]['promoCodeDiscount'] - $vendors[$vid]['newCustomerDiscount'];
                $take = min($left, max(0, $room));
                $vendors[$vid][$key] = round($vendors[$vid][$key] + $take, 2);
                $left -= $take;
            }
        }
        if ($newCustomerDiscount > 0 && isset($newCustomerOfferId)) {
            foreach ($order as $vid) {
                if ($vendors[$vid]['newCustomerDiscount'] > 0) {
                    $vendors[$vid]['appliedOffers'][] = $newCustomerOfferId;
                    break;
                }
            }
        }

        foreach ($vendors as $vid => $v) {
            $vendors[$vid]['afterDiscount'] = round(max(0, $v['beforeDiscount'] - $v['offerDiscount'] - $v['promoCodeDiscount'] - $v['newCustomerDiscount']), 2);
        }

        return [
            'deliveryInfo'      => array_map(fn ($v) => ['timeSlotText' => $v['timeSlotText'], 'freeDeliMinTotal' => $v['freeDeliMinTotal'], 'deliCharge' => $v['deliCharge']], $vendors),
            'cartList'          => array_map(fn ($v) => $v['cartList'], $vendors),
            'freeItems'         => array_map(fn ($v) => $v['freeItems'], $vendors),
            'deliveryCharge'    => round(array_sum(array_column($vendors, 'deliveryCharge')), 2),
            'order_count'       => array_sum(array_map(fn ($v) => count($v['cartList']), $vendors)),
            'afterDiscount'     => round(array_sum(array_column($vendors, 'afterDiscount')), 2),
            'beforeDiscount'    => round(array_sum(array_column($vendors, 'beforeDiscount')), 2),
            'promoCodeDiscount' => ['discount' => $promo['discount'], 'description' => $promo['description']],
            'offerDiscount'     => round(array_sum(array_column($vendors, 'offerDiscount')) + array_sum(array_column($vendors, 'newCustomerDiscount')), 2),
            'vendors'           => $vendors,
            'promo_id'          => $promo['promo_id'],
            'address'           => $address,
        ];
    }

    // ═════════════════════════════════════════════════ place (placeNewOrder)

    /**
     * @return array{master_order_id:int, order_ids:int[], order_total:float}
     */
    public function place(int $userId, int $addressId, array $lines, ?string $promoCode, float $totalAmount): array
    {
        $calc = $this->calculate($userId, $addressId, $lines, $promoCode);

        // doc §1 step 3 — compare with the REAL master total (gotcha 4 fixed)
        if (abs($calc['afterDiscount'] - $totalAmount) > 0.01) {
            $this->fail('total_amount', 'The order total has changed (₹' . number_format($calc['afterDiscount'], 2) . '). Please review the order again.');
        }

        $this->minimumOrderGates($userId, $calc);

        return DB::transaction(function () use ($userId, $calc) {
            // stock re-validation under row locks (doc §1 step 7) — paid AND free lines
            $need = [];
            foreach ($calc['vendors'] as $v) {
                foreach (array_merge($v['cartList'], $v['freeItems']) as $l) {
                    $need[$l['vendor_product_id']][] = $l;
                }
            }
            $packsByVp = DB::table('vendor_products')->whereIn('id', array_keys($need))->lockForUpdate()->pluck('packs', 'id');
            $stockToRemove = [];
            foreach ($need as $vpId => $ls) {
                $packs = json_decode((string) ($packsByVp[$vpId] ?? ''), true) ?: [];
                foreach ($ls as $l) {
                    $pack = $packs[$l['pack_id']] ?? null;
                    if (!$pack || (int) ($pack['in_stk'] ?? 1) !== 1) {
                        $this->fail('items', "{$l['name']} is out of stock.");
                    }
                    $stockToRemove[$vpId] = ($stockToRemove[$vpId] ?? 0) + UnitFactors::stockFor($l['quantity'], $pack);
                }
                $available = $this->packStock($packs, $ls[0]['pack_id']);
                if ($available !== null && $stockToRemove[$vpId] > $available + 1e-9) {
                    $this->fail('items', "Not enough stock for {$ls[0]['name']}.");
                }
            }

            $now          = Carbon::now(config('app.timezone'));
            $deliveryInfo = json_encode($this->deliveryInfo($userId, $calc['address']));

            // master_orders (doc §2.1)
            $masterId = $this->insertGetId('master_orders', 'id', [
                'user_id'         => $userId,
                'created_at'      => $now->format('Y-m-d H:i:s'),
                'payment_method'  => 'cod',
                'payment_status'  => 'pending',
                'order_count'     => $calc['order_count'],
                'txn_id'          => $this->txnId(),
                'delivery_info'   => $deliveryInfo,
                'delivery_charge' => $calc['deliveryCharge'],
                'order_total'     => $calc['afterDiscount'],
                'before_discount' => $calc['beforeDiscount'],
                'discount'        => round(array_sum(array_map(fn ($v) => $v['promoCodeDiscount'] + $v['offerDiscount'] + $v['newCustomerDiscount'], $calc['vendors'])), 2),
                'status'          => '1',
            ]);

            $orderIds    = [];
            $promoLogged = false;
            foreach ($calc['vendors'] as $vendorId => $v) {
                // orders (doc §2.2) — one row per vendor
                $orderId = $this->insertGetId('orders', 'order_id', [
                    'master_order_id'  => $masterId,
                    'buyer_userid'     => $userId,
                    'before_discount'  => $v['beforeDiscount'],
                    'discount'         => round($v['promoCodeDiscount'] + $v['offerDiscount'] + $v['newCustomerDiscount'], 2),
                    'items_count'      => count($v['cartList']), // this vendor's paid lines (gotchas 2/3)
                    'delivery_info'    => $deliveryInfo,
                    'order_total'      => $v['afterDiscount'],
                    'delivery_charge'  => $v['deliveryCharge'],
                    'time_slot'        => $v['timeSlotText'],
                    'short_datetime'   => $now->format('d-M-y h:i A'),
                    'ctype_id'         => 'vegetables_fruits',
                    'feedback'         => '',
                    'admin_id'         => (int) $vendorId,
                    'area_name'        => 'AMT',
                    'payment_method'   => 'cod',
                    'payment_status'   => 'not_paid',
                    'txn_id'           => $this->txnId(),
                    'start_time'       => $now->timestamp,
                    'last_update_time' => $now->timestamp,
                    'order_state'      => 'pending',
                ]);
                $orderIds[] = $orderId;

                // promo_log + promo.max_use — once per ORDER (gotcha 6 fixed)
                if (!$promoLogged && $calc['promo_id'] && $v['promoCodeDiscount'] > 0) {
                    $this->insertGetId('promo_log', 'log_id', ['order_id' => $orderId, 'userid' => $userId, 'promo_id' => $calc['promo_id']]);
                    DB::table('promo')->where('promo_id', $calc['promo_id'])->update(['max_use' => DB::raw('GREATEST(CAST(max_use AS SIGNED) - 1, 0)')]);
                    $promoLogged = true;
                }

                // orders_item (doc §2.3) — paid lines then free lines
                foreach ($v['cartList'] as $l) {
                    $this->insertGetId('orders_item', 'item_id', [
                        'order_id'          => $orderId,
                        'product_id'        => $l['product_id'],
                        'pinfo'             => json_encode($l['pack']),
                        'quantity'          => $l['quantity'],
                        'qty_loaded'        => $l['quantity'],
                        'item_price'        => $l['item_price'],
                        'item_total'        => $l['item_total'],
                        'vendor_product_id' => $l['vendor_product_id'],
                        'commission'        => 0,
                    ]);
                }
                foreach ($v['freeItems'] as $f) {
                    $this->insertGetId('orders_item', 'item_id', [
                        'order_id'          => $orderId,
                        'product_id'        => $f['product_id'],
                        'pinfo'             => json_encode(array_merge($f['pack'], ['rp' => 0])),
                        'quantity'          => $f['quantity'],
                        'qty_loaded'        => $f['quantity'],
                        'item_price'        => 0,
                        'item_total'        => 0,
                        'vendor_product_id' => $f['vendor_product_id'],
                        'commission'        => 0,
                        'offers'            => 'free_item',
                    ]);
                }

                // offer_log (doc §2.5) — IST dates set explicitly
                foreach ($v['appliedOffers'] as $offerId) {
                    $this->insertGetId('offer_log', 'id', [
                        'user_id'    => $userId,
                        'order_id'   => $orderId,
                        'offer_id'   => $offerId,
                        'used_date'  => $now->toDateString(),
                        'created_at' => $now->format('Y-m-d H:i:s'),
                    ]);
                }
            }

            // vendor_products.packs stock (doc §2.6)
            $this->updateStock($stockToRemove, false);

            return ['master_order_id' => $masterId, 'order_ids' => $orderIds, 'order_total' => $calc['afterDiscount']];
        });
    }

    // ═════════════════════════════════════════════════ cancel (cancelOrder)

    /** Doc §6: pending only; restock; delete orders_item / orders / offer_log. CRM orders only. */
    public function cancel(int $orderId): void
    {
        DB::transaction(function () use ($orderId) {
            $order = DB::table('orders')->where('order_id', $orderId)->lockForUpdate()->first(['order_id', 'order_state', 'txn_id', 'master_order_id']);
            if (!$order) {
                $this->fail('order', 'Order not found.', 404);
            }
            if (!str_starts_with((string) $order->txn_id, self::TXN_PREFIX)) {
                $this->fail('order', 'Only orders placed from the CRM can be cancelled here.', 403);
            }
            if ($order->order_state !== 'pending') {
                $this->fail('order', 'Only pending orders can be cancelled.');
            }

            $add = [];
            foreach (DB::table('orders_item')->where('order_id', $orderId)->get(['vendor_product_id', 'pinfo', 'quantity']) as $r) {
                if (!$r->vendor_product_id) continue;
                $pack = json_decode((string) $r->pinfo, true) ?: [];
                $add[$r->vendor_product_id] = ($add[$r->vendor_product_id] ?? 0) + UnitFactors::stockFor((int) $r->quantity, $pack);
            }
            if ($add) {
                DB::table('vendor_products')->whereIn('id', array_keys($add))->lockForUpdate()->get(['id']);
                $this->updateStock($add, true);
            }

            DB::table('orders_item')->where('order_id', $orderId)->delete();
            DB::table('orders')->where('order_id', $orderId)->delete();
            DB::table('offer_log')->where('order_id', $orderId)->delete();

            // gotcha 8 fixed: don't leave an orphaned master behind
            if ($order->master_order_id && !DB::table('orders')->where('master_order_id', $order->master_order_id)->exists()) {
                DB::table('master_orders')->where('id', $order->master_order_id)->delete();
            }
        });
    }

    // ═════════════════════════════════════════════════ helpers

    /** App lines → doc cartList rows (live price, pack snapshot, sale checks). */
    private function resolveLines(array $lines): array
    {
        $vpIds = array_values(array_unique(array_map(fn ($l) => (int) ($l['vendor_product_id'] ?? 0), $lines)));
        $rows  = DB::table('vendor_products as vp')
            ->join('product as p', 'p.product_id', '=', 'vp.product_id')
            ->whereIn('vp.id', $vpIds)
            ->get(['vp.id as vendor_product_id', 'vp.admin_vendor_id', 'vp.product_id', 'vp.packs', 'vp.status',
                   'vp.in_stock as vendor_in_stock', 'p.in_stock as product_in_stock', 'p.is_published', 'p.is_deleted',
                   'p.name', 'p.cat_id', 'p.parent_cat_id'])
            ->keyBy('vendor_product_id');

        $out = [];
        foreach ($lines as $l) {
            $vpId = (int) ($l['vendor_product_id'] ?? 0);
            $qty  = (int) ($l['quantity'] ?? 0);
            $r    = $rows->get($vpId);
            if (!$r || (int) $r->product_id !== (int) ($l['product_id'] ?? 0)) {
                $this->fail('items', 'One of the products is not available from this vendor.');
            }
            if ($qty < 1) {
                $this->fail('items', "Quantity for {$r->name} must be at least 1.");
            }
            // isProductForSell + stock flags (doc §1 step 7)
            if ((string) $r->status !== '1' || (int) $r->is_published !== 1 || (int) $r->is_deleted !== 0
                || (string) $r->vendor_in_stock !== '1' || (int) $r->product_in_stock !== 1) {
                $this->fail('items', "{$r->name} is not available for sale.");
            }
            $packs = json_decode((string) $r->packs, true) ?: [];
            $pack  = $packs[(string) ($l['pack_id'] ?? '')] ?? null;
            if (!is_array($pack)) {
                $this->fail('items', "The selected pack of {$r->name} no longer exists.");
            }
            if ((int) ($pack['in_stk'] ?? 1) !== 1) {
                $this->fail('items', "{$r->name} ({$pack['tx']}) is out of stock.");
            }
            if (isset($pack['stk']) && UnitFactors::stockFor($qty, $pack) > (float) $pack['stk'] + 1e-9) {
                $this->fail('items', "Only limited stock left for {$r->name} ({$pack['tx']}).");
            }
            // bc = buy cap when numeric (some packs store a barcode here)
            if (isset($pack['bc']) && is_numeric($pack['bc']) && (int) $pack['bc'] > 0 && $qty > (int) $pack['bc']) {
                $this->fail('items', "You can order at most {$pack['bc']} of {$r->name} ({$pack['tx']}).");
            }
            $price = (float) ($pack['rp'] ?? 0); // live selling price, never the client's
            $out[] = [
                'vendor_id'         => (int) $r->admin_vendor_id,
                'vendor_product_id' => $vpId,
                'product_id'        => (int) $r->product_id,
                'pack_id'           => (string) $l['pack_id'],
                'name'              => $r->name,
                'pack'              => $pack,
                'quantity'          => $qty,
                'item_price'        => $price,
                'item_total'        => round($price * $qty, 2),
                'ctype'             => 'vegetables_fruits',
            ];
        }
        return $out;
    }

    /** A free (offer) item for the given vendor, or null if it can't be supplied. */
    private function freeItem(int $productId, string $packId, int $qty, int $vendorId, array $offer): ?array
    {
        if ($productId <= 0 || $packId === '' || $qty <= 0) return null;
        $vp = DB::table('vendor_products')->where('product_id', $productId)->where('admin_vendor_id', $vendorId)->where('status', '1')->first(['id', 'packs']);
        if (!$vp) return null;
        $pack = (json_decode((string) $vp->packs, true) ?: [])[$packId] ?? null;
        if (!is_array($pack) || (int) ($pack['in_stk'] ?? 1) !== 1) return null;
        $name = DB::table('product')->where('product_id', $productId)->value('name');
        return [
            'vendor_product_id' => (int) $vp->id,
            'product_id'        => $productId,
            'pack_id'           => $packId,
            'name'              => (string) $name,
            'pack'              => $pack,
            'quantity'          => $qty,
            'offer_id'          => $offer['id'],
            'offer_name'        => $offer['name'],
        ];
    }

    /** Active offers grouped by type; daily-limited ones already used today by this user are dropped. */
    private function activeOffers(int $userId): array
    {
        $out = ['prod_on_prod' => [], 'off_on_total' => [], 'prod_on_total' => [], 'new_customer_product' => [], 'new_customer_discount' => []];
        $today = Carbon::now(config('app.timezone'))->toDateString();
        foreach (DB::table('offers')->where('is_active', 1)->get() as $o) {
            $type = trim((string) $o->off_type);
            if (!isset($out[$type])) continue;
            $data = json_decode((string) $o->off_data, true) ?: [];
            if (isset($data['dailyLimit']) && (int) $data['dailyLimit'] > 0) {
                $usedToday = DB::table('offer_log')->where('user_id', $userId)->where('offer_id', $o->off_id)->where('used_date', $today)->count();
                if ($usedToday >= (int) $data['dailyLimit']) continue;
            }
            $out[$type][] = ['id' => (int) $o->off_id, 'name' => (string) $o->name, 'product_id' => (int) $o->product_id, 'data' => $data];
        }
        return $out;
    }

    /** {threshold: value} map → value for the highest threshold ≤ amount; a plain number is returned as is. */
    private function ladderValue($ladder, float $amount): float
    {
        if (!is_array($ladder)) return (float) $ladder;
        $best = 0.0;
        $bestAt = -1.0;
        foreach ($ladder as $threshold => $value) {
            if ((float) $threshold <= $amount && (float) $threshold > $bestAt) {
                $best = (float) $value;
                $bestAt = (float) $threshold;
            }
        }
        return $best;
    }

    /** Promo lookup + validation + amount (doc §5 step 6, §9). Invalid code → 422 with a message. */
    private function resolvePromo(?string $code, int $userId, float $subtotal): array
    {
        $none = ['promo_id' => null, 'discount' => 0.0, 'description' => ''];
        $code = strtoupper(trim((string) $code));
        if ($code === '') return $none;

        $p = DB::table('promo')->whereRaw('UPPER(title) = ?', [$code])->where('status', 1)->first();
        if (!$p) $this->fail('promo_code', 'Invalid promo code.');
        $data = json_decode((string) $p->promo_data, true) ?: [];
        if ((int) $p->max_use <= 0) $this->fail('promo_code', 'This promo code has been fully used.');
        if (isset($data['min_user_id']) && $userId < (int) $data['min_user_id']) $this->fail('promo_code', 'This promo code is not valid for this customer.');
        if (DB::table('promo_log')->where('userid', $userId)->where('promo_id', $p->promo_id)->exists()) $this->fail('promo_code', 'This customer has already used this promo code.');

        $min = (float) ($data['min_amount'] ?? 0);
        $discount = match ((string) ($data['promo_type'] ?? '')) {
            'amount'           => $subtotal >= $min ? (float) ($data['amount'] ?? 0) : 0,
            'amount_ladder'    => $this->ladderValue($data['ladderPromo'] ?? [], $subtotal),
            'percentage'       => $subtotal >= $min ? $subtotal * (float) ($data['percentage'] ?? 0) / 100 : 0,
            'percentage_up_to' => $subtotal >= $min ? min($subtotal * (float) ($data['percentage'] ?? 0) / 100, (float) ($data['max_amount'] ?? PHP_FLOAT_MAX)) : 0,
            default            => 0,
        };
        if ($discount <= 0) {
            $this->fail('promo_code', $min > 0 ? 'Add items worth ₹' . number_format($min, 0) . ' or more to use this promo code.' : 'This promo code does not apply to this order.');
        }
        return ['promo_id' => (int) $p->promo_id, 'discount' => round(min($discount, $subtotal), 2), 'description' => (string) ($p->description ?? '')];
    }

    /** Doc §1 steps 4–6. */
    private function minimumOrderGates(int $userId, array $calc): void
    {
        $total = $calc['afterDiscount'];
        $personal = DB::table('user')->where('userid', $userId)->value('shop_plot_no');
        if (is_numeric($personal) && (float) $personal > 0 && $total < (float) $personal) {
            $this->fail('items', 'Minimum order value for this customer is ₹' . number_format((float) $personal, 0) . '.');
        }
        $vendorIds = array_map('intval', array_keys($calc['vendors']));
        $globalMin = $vendorIds === [128] ? 100 : 1000;
        if ($total < $globalMin) {
            $this->fail('items', "Minimum order value is ₹{$globalMin}.");
        }
        if (isset($calc['vendors'][125]) && $calc['vendors'][125]['afterDiscount'] < 500) {
            $this->fail('items', 'Minimum order value for FMCG items (vendor 125) is ₹500.');
        }
    }

    /** timing_slot_groups ⨝ time_slots for a vendor (doc §3 inputs, §4). */
    private function deliveryConfig(int $vendorId): array
    {
        $r = DB::selectOne(
            'SELECT g.min_amount AS min_total, g.delivery_charge, t.start_date AS num_days_gap, t.`interval` AS delivery_interval,
                    t.order_time_end, t.delivery_time_start, t.delivery_time_end
             FROM timing_slot_groups g JOIN time_slots t ON g.id = t.time_slot_group_id
             WHERE g.is_active = 1 AND g.admin_id = ? LIMIT 1',
            [$vendorId]
        );
        return [
            'min_total'           => (float) ($r->min_total ?? 0),
            'delivery_charge'     => (float) ($r->delivery_charge ?? 0),
            'num_days_gap'        => (int) ($r->num_days_gap ?? 0),
            'delivery_interval'   => (int) ($r->delivery_interval ?? 1),
            'order_time_end'      => (int) ($r->order_time_end ?? 2359),
            'delivery_time_start' => (int) ($r->delivery_time_start ?? 800),
            'delivery_time_end'   => (int) ($r->delivery_time_end ?? 2200),
            'found'               => $r !== null,
        ];
    }

    /** Doc §3 — DeliveryDetails::generateTimeSlotText, exact algorithm. e.g. "10 Oct 8:00am  to  10 Oct 10:00pm". */
    public function timeSlotText(array $cfg, ?Carbon $now = null): string
    {
        if (!($cfg['found'] ?? true)) return '';
        $now      = $now ?? Carbon::now(config('app.timezone'));
        $interval = (int) $cfg['delivery_interval'];
        if ((int) $now->format('Hi') > (int) $cfg['order_time_end']) {
            $interval += 1;
        }
        $start = $now->copy()->addDays($interval)->format('j M');
        $end   = $now->copy()->addDays($interval + (int) $cfg['num_days_gap'])->format('j M');
        $ts = min((int) $cfg['delivery_time_start'], 2300);
        $te = min((int) $cfg['delivery_time_end'], 2400);
        return $start . ' ' . self::convertTime($ts) . '  to  ' . $end . ' ' . self::convertTime($te);
    }

    /** HHMM int → "8:00am" / "10:00pm" (doc §3 convertTime; format as stored in real orders). */
    public static function convertTime(int $hhmm): string
    {
        $s = str_pad((string) $hhmm, 4, '0', STR_PAD_LEFT);
        $h = (int) substr($s, 0, 2) % 24;
        $m = (int) substr($s, 2, 2);
        $ampm = $h >= 12 ? 'pm' : 'am';
        $h12 = $h % 12 === 0 ? 12 : $h % 12;
        return sprintf('%d:%02d%s', $h12, $m, $ampm);
    }

    /** delivery_info JSON from the chosen saved address (doc §2.1, gotcha 1 fixed). */
    private function deliveryInfo(int $userId, object $addr): array
    {
        $contact = DB::table('user')->where('userid', $userId)->value('contactno');
        $address = trim(trim((string) $addr->full_address) . ' ' . trim((string) $addr->address));
        return [
            'name'            => (string) ($addr->full_name ?: $addr->name ?: DB::table('user')->where('userid', $userId)->value('name')),
            'address'         => $address,
            'contactno'       => (string) ($addr->phone_no ?: $contact),
            'comment'         => '',
            'couponCode'      => '',
            'latitude'        => (float) $addr->lat,
            'longitude'       => (float) $addr->lng,
            'expressDelivery' => '0',
        ];
    }

    private function addressRow(int $userId, int $addressId): object
    {
        if ($addressId <= 0) {
            $this->fail('address_id', 'Select a saved delivery address for this customer.');
        }
        $a = DB::table('user_addresses')->where('id', $addressId)->where('user_id', $userId)->first();
        if (!$a) {
            $this->fail('address_id', 'This address does not belong to the customer.');
        }
        return $a;
    }

    private function assertCustomer(int $userId): void
    {
        if (!DB::table('user')->where('userid', $userId)->exists()) {
            $this->fail('buyer_userid', 'Orders can only be placed for a registered customer.');
        }
    }

    /** Available stock of one pack (packs share a pool per vendor product); null = not tracked. */
    private function packStock(array $packs, string $packId): ?float
    {
        return isset($packs[$packId]['stk']) ? (float) $packs[$packId]['stk'] : null;
    }

    /**
     * Doc §2.6 / database.php updateStock: apply the same delta to every pack of
     * the vendor product, then in_stk = stk > unit_factor × ps ? 1 : 0.
     */
    private function updateStock(array $deltaByVp, bool $add): void
    {
        foreach ($deltaByVp as $vpId => $delta) {
            $packs = json_decode((string) DB::table('vendor_products')->where('id', $vpId)->value('packs'), true) ?: [];
            foreach ($packs as $pid => $pack) {
                if (!is_array($pack) || !isset($pack['stk'])) continue;
                $stk = (float) $pack['stk'] + ($add ? $delta : -$delta);
                $packs[$pid]['stk'] = round($stk, 6);
                $packs[$pid]['in_stk'] = $stk > UnitFactors::factor($pack['pu'] ?? '') * UnitFactors::extractFirstNumber($pack['ps'] ?? '') ? 1 : 0;
            }
            DB::table('vendor_products')->where('id', $vpId)->update(['packs' => json_encode($packs)]);
        }
    }

    private function txnId(): string
    {
        return self::TXN_PREFIX . substr(hash('sha256', random_bytes(16) . microtime()), 0, 17);
    }

    /** Auto-increment insert (prod); MAX+1 fallback where the column has no AUTO_INCREMENT (dev TiDB). */
    private function insertGetId(string $table, string $pk, array $row): int
    {
        static $auto = [];
        $auto[$table] ??= (bool) DB::selectOne(
            "SELECT 1 x FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND COLUMN_NAME = ? AND EXTRA LIKE '%auto_increment%'",
            [$table, $pk]
        );
        if ($auto[$table]) {
            return (int) DB::table($table)->insertGetId($row, $pk);
        }
        $row[$pk] = (int) DB::table($table)->lockForUpdate()->max($pk) + 1;
        DB::table($table)->insert($row);
        return $row[$pk];
    }

    private function fail(string $field, string $message, int $status = 422): never
    {
        if ($status === 422) {
            throw ValidationException::withMessages([$field => $message]);
        }
        abort($status, $message);
    }
}

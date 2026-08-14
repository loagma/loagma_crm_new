<?php

namespace App\Http\Controllers;

use Illuminate\Http\JsonResponse;
use Illuminate\Support\Facades\DB;

/**
 * Minimal, safe slice of the real Sales Order model documented in
 * client/SALES_MODULE.md. `orders`/`orders_item` are shared, live production
 * tables (not owned by this app) with NO real AUTO_INCREMENT on TiDB, so IDs
 * are computed here the same way the documented system does it — but with an
 * explicit `lockForUpdate()` the doc flags as *missing* in the real
 * single-row `store()` path, to reduce (not fully eliminate) collision risk.
 *
 * Scope deliberately stops at `order_state = 'pending'` (draft) — no
 * invoicing, no stock-ledger movement, no PDF generation. Per the doc,
 * stock only moves once an order transitions to `invoiced`, so a plain
 * "Create Sales Order" action from the CRM staying in `pending` cannot
 * corrupt stock or numbering sequences owned by the real invoicing flow.
 */
class SalesOrderController extends Controller
{
    /**
     * GET /api/sales-orders/next-order-id
     *
     * Non-authoritative preview of the order_id this order WOULD get if
     * created right now (same "preview, not reserved" pattern as the real
     * system's `series()` endpoint for invoice numbers — see SALES_MODULE.md
     * §4). No lock is held, so the real `store()` call may still end up
     * assigning a different (higher) id if another order is created in
     * between; it's shown purely so the create form doesn't display a made-up
     * number.
     */
    public function nextOrderId(): JsonResponse
    {
        $next = (int) DB::table('orders')->max('order_id') + 1;

        return response()->json(['success' => true, 'data' => ['next_order_id' => $next]]);
    }

    public function store(): JsonResponse
    {
        $data = request()->all();

        $buyerUserId = $data['buyer_userid'] ?? null;
        $items       = $data['items'] ?? [];

        if (!$buyerUserId) {
            return response()->json(['success' => false, 'message' => 'buyer_userid is required'], 422);
        }

        $buyer = DB::table('user')->where('userid', $buyerUserId)->first(['userid']);
        if (!$buyer) {
            return response()->json([
                'success' => false,
                'message' => 'This account has no matching registered customer (user) row — a real sales order can only be created for a registered customer, not a lead.',
            ], 422);
        }

        if (!is_array($items) || count($items) === 0) {
            return response()->json(['success' => false, 'message' => 'At least one item is required'], 422);
        }

        // Validate every item references a real, non-deleted product — orders_item.product_id is NOT NULL.
        // Also the single source of truth for GST rate: tax_percent/sgst_percent/
        // cgst_percent are derived from product.gst_percent here, never trusted
        // from the client — a stale cache or buggy client shouldn't be able to
        // write an arbitrary tax rate onto a real order.
        $productIds = collect($items)->pluck('product_id')->filter()->unique()->values();
        $products = DB::table('product')
            ->whereIn('product_id', $productIds)
            ->where('is_deleted', 0)
            ->get(['product_id', 'name', 'gst_percent'])
            ->keyBy('product_id');

        foreach ($items as $item) {
            $pid = $item['product_id'] ?? null;
            if (!$pid || !$products->has((int) $pid)) {
                return response()->json(['success' => false, 'message' => "Invalid or unknown product_id: {$pid}"], 422);
            }
            if (((float) ($item['quantity'] ?? 0)) <= 0) {
                return response()->json(['success' => false, 'message' => 'Every item needs a quantity greater than 0'], 422);
            }
        }

        $idempotencyKey = $data['idempotency_key'] ?? null;
        if ($idempotencyKey) {
            $existing = DB::table('orders')->where('idempotency_key', $idempotencyKey)->first(['order_id']);
            if ($existing) {
                return response()->json(['success' => true, 'data' => ['order_id' => (string) $existing->order_id], 'idempotent_replay' => true]);
            }
        }

        $discount        = (float) ($data['discount'] ?? 0);
        $deliveryCharge  = (float) ($data['delivery_charge'] ?? 0);
        $narration       = $data['narration'] ?? null;
        $department      = $data['department'] ?? null;
        $areaName        = $data['area_name'] ?? null;
        $timeSlot        = $data['time_slot'] ?? 'Now';
        $documentDate    = $data['document_date'] ?? null; // Y-m-d
        $deliveryInfo    = $data['delivery_info'] ?? [];

        $beforeDiscount = 0.0;
        foreach ($items as $item) {
            $beforeDiscount += ((float) $item['quantity']) * ((float) ($item['item_price'] ?? 0));
        }
        $orderTotal = round($beforeDiscount - $discount + $deliveryCharge, 2);

        $orderId = null;

        DB::transaction(function () use (
            $items, $products, $buyerUserId, $discount, $deliveryCharge, $narration, $department,
            $areaName, $timeSlot, $documentDate, $deliveryInfo, $beforeDiscount, $orderTotal,
            $idempotencyKey, &$orderId
        ) {
            $nextOrderId = (int) (DB::table('orders')->lockForUpdate()->max('order_id')) + 1;
            $nextItemId  = (int) (DB::table('orders_item')->lockForUpdate()->max('item_id')) + 1;

            $now = now();

            DB::table('orders')->insert([
                'order_id'          => $nextOrderId,
                'master_order_id'   => $nextOrderId,
                'txn_id'            => 'CRM-' . $nextOrderId . '-' . $now->timestamp,
                'buyer_userid'      => $buyerUserId,
                'start_time'        => $now->timestamp,
                'last_update_time'  => $now->timestamp,
                'short_datetime'    => $now->format('d-M-y h:i A'),
                'order_state'       => 'pending',
                'payment_method'    => 'cod',
                'items_count'       => count($items),
                'delivery_charge'   => $deliveryCharge,
                'order_total'       => $orderTotal,
                'delivery_info'     => json_encode($deliveryInfo ?: (object) []),
                'area_name'         => $areaName,
                'feedback'          => '',
                'admin_id'          => 0,
                'payment_status'    => 'not_paid',
                'discount'          => $discount,
                'before_discount'   => $beforeDiscount,
                'time_slot'         => $timeSlot,
                'Bill_Narration'    => $narration,
                'Department'        => $department,
                'Bill_Dt'           => $documentDate,
                'idempotency_key'   => $idempotencyKey,
            ]);

            $itemId = $nextItemId;
            foreach ($items as $item) {
                $qty        = (float) $item['quantity'];
                $price      = (float) ($item['item_price'] ?? 0);
                // Tax rate is authoritative from the product row, not the client —
                // see the note at $products above.
                $taxPercent  = (float) ($products->get((int) $item['product_id'])->gst_percent ?? 0);
                $sgstPercent = round($taxPercent / 2, 2);
                $cgstPercent = round($taxPercent / 2, 2);
                DB::table('orders_item')->insert([
                    'order_id'   => $nextOrderId,
                    'item_id'    => $itemId,
                    'product_id' => (int) $item['product_id'],
                    'pinfo'      => json_encode([
                        'unit'                  => $item['unit'] ?? 'PCS',
                        'price_inclusive'       => true,
                        'unit_price_inclusive'  => $price,
                        'tax_percent'           => $taxPercent,
                        'sgst_percent'          => $sgstPercent,
                        'cgst_percent'          => $cgstPercent,
                        'discount_percent'      => 0,
                    ]),
                    'quantity'   => (int) round($qty),
                    'item_price' => $price,
                    'item_total' => round($qty * $price, 2),
                    'commission' => 0,
                ]);
                $itemId++;
            }

            DB::table('master_orders')->insert([
                'id'              => $nextOrderId,
                'user_id'         => $buyerUserId,
                'txn_id'          => 'CRM-' . $nextOrderId,
                'payment_status'  => 'not_paid',
                'order_count'     => count($items),
                'payment_method'  => 'cod',
                'delivery_info'   => json_encode($deliveryInfo ?: (object) []),
                'order_total'     => $orderTotal,
                'delivery_charge' => $deliveryCharge,
                'discount'        => $discount,
                'before_discount' => $beforeDiscount,
                'status'          => '1',
                'created_at'      => $now,
            ]);

            $orderId = $nextOrderId;
        });

        return response()->json([
            'success' => true,
            'data' => [
                'order_id'    => (string) $orderId,
                'order_total' => $orderTotal,
            ],
        ], 201);
    }

    /**
     * PUT /api/orders/{orderId}/items
     *
     * Persist an add/edit/remove of line items on an EXISTING order — the
     * missing counterpart to store() that the Order Detail screen needs so
     * edits survive a refresh instead of only living in local widget state.
     *
     * Deliberately scoped to `order_state = 'pending'` only, same reasoning
     * as store(): per SALES_MODULE.md §7, stock only moves once an order is
     * `invoiced`, and re-editing an invoiced order in the real system
     * reverses+reapplies the stock ledger — logic this app does not
     * implement. Editing a pending order touches no stock/ledger/invoice
     * fields at all, so it's safe to do here with a plain delete+reinsert of
     * `orders_item`, mirroring the real update()'s item-replacement approach
     * (SALES_MODULE.md §4).
     */
    public function updateItems(string $orderId): JsonResponse
    {
        $data  = request()->all();
        $items = $data['items'] ?? [];

        if (!is_array($items) || count($items) === 0) {
            return response()->json([
                'success' => false,
                'message' => "An order can't be saved with zero items — it still needs at least one. Delete the whole order instead if you want to clear it out.",
            ], 422);
        }

        // Tax rate is authoritative from the product row, not the client — see
        // the matching note in store().
        $productIds = collect($items)->pluck('product_id')->filter()->unique()->values();
        $products = DB::table('product')
            ->whereIn('product_id', $productIds)
            ->where('is_deleted', 0)
            ->get(['product_id', 'name', 'gst_percent'])
            ->keyBy('product_id');

        foreach ($items as $item) {
            $pid = $item['product_id'] ?? null;
            if (!$pid || !$products->has((int) $pid)) {
                return response()->json(['success' => false, 'message' => "Invalid or unknown product_id: {$pid}"], 422);
            }
            if (((float) ($item['quantity'] ?? 0)) <= 0) {
                return response()->json(['success' => false, 'message' => 'Every item needs a quantity greater than 0'], 422);
            }
        }

        $result = null;

        DB::transaction(function () use ($orderId, $items, $products, &$result) {
            $order = DB::table('orders')->where('order_id', $orderId)->lockForUpdate()->first(['order_id', 'order_state', 'discount', 'delivery_charge']);

            if (!$order) {
                $result = ['status' => 404, 'body' => ['success' => false, 'message' => 'Order not found']];
                return;
            }

            if ($order->order_state !== 'pending') {
                $result = ['status' => 422, 'body' => [
                    'success' => false,
                    'message' => 'Only draft (pending) orders can have items edited here — this order is already ' . $order->order_state . '.',
                ]];
                return;
            }

            DB::table('orders_item')->where('order_id', $orderId)->delete();

            $nextItemId = (int) (DB::table('orders_item')->lockForUpdate()->max('item_id')) + 1;
            $beforeDiscount = 0.0;
            $itemId = $nextItemId;

            foreach ($items as $item) {
                $qty   = (float) $item['quantity'];
                $price = (float) ($item['item_price'] ?? 0);
                $lineTotal = round($qty * $price, 2);
                $beforeDiscount += $lineTotal;

                $taxPercent  = (float) ($products->get((int) $item['product_id'])->gst_percent ?? 0);
                $sgstPercent = round($taxPercent / 2, 2);
                $cgstPercent = round($taxPercent / 2, 2);
                DB::table('orders_item')->insert([
                    'order_id'   => $orderId,
                    'item_id'    => $itemId,
                    'product_id' => (int) $item['product_id'],
                    'pinfo'      => json_encode([
                        'unit'                  => $item['unit'] ?? 'PCS',
                        'price_inclusive'       => true,
                        'unit_price_inclusive'  => $price,
                        'tax_percent'           => $taxPercent,
                        'sgst_percent'          => $sgstPercent,
                        'cgst_percent'          => $cgstPercent,
                        'discount_percent'      => 0,
                    ]),
                    'quantity'   => (int) round($qty),
                    'item_price' => $price,
                    'item_total' => $lineTotal,
                    'commission' => 0,
                ]);
                $itemId++;
            }

            $discount       = (float) $order->discount;
            $deliveryCharge = (float) $order->delivery_charge;
            $orderTotal     = round($beforeDiscount - $discount + $deliveryCharge, 2);
            if ($orderTotal < 0) {
                $orderTotal = 0.0;
            }

            DB::table('orders')->where('order_id', $orderId)->update([
                'items_count'      => count($items),
                'before_discount'  => $beforeDiscount,
                'order_total'      => $orderTotal,
                'last_update_time' => now()->timestamp,
            ]);

            DB::table('master_orders')->where('id', $orderId)->update([
                'order_count'     => count($items),
                'before_discount' => $beforeDiscount,
                'order_total'     => $orderTotal,
            ]);

            $result = ['status' => 200, 'body' => [
                'success' => true,
                'data' => [
                    'order_id'        => (string) $orderId,
                    'items_count'     => count($items),
                    'before_discount' => $beforeDiscount,
                    'order_total'     => $orderTotal,
                ],
            ]];
        });

        return response()->json($result['body'], $result['status']);
    }
}

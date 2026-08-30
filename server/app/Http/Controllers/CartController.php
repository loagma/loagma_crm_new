<?php

namespace App\Http\Controllers;

use App\Support\ProductTaxResolver;
use Illuminate\Http\JsonResponse;
use Illuminate\Support\Facades\DB;

/**
 * Server-side persistence for the Create Sales Order sheet's cart, backed by
 * the real (shared/legacy) `cart` table so a staff member's in-progress cart
 * for a customer survives an app close/crash instead of living only in
 * widget state.
 *
 * Deliberately scoped to real customer accounts only — `cart.userid` is a
 * `user.userid` FK and leads have no row there, so a lead's cart stays
 * client-side only (same as today) and never reaches this controller.
 *
 * `cart_id` has NO real AUTO_INCREMENT on TiDB (same situation documented on
 * SalesOrderController for `orders`/`orders_item`), so new ids are computed
 * with an explicit `lockForUpdate()` the same way.
 */
class CartController extends Controller
{
    // In-store, staff-placed orders — no delivery workflow/express charge
    // assumptions apply here, unlike the consumer app's other cart types.
    private const CTYPE_ID = 'in_store';

    /**
     * GET /api/cart?user_id=...
     *
     * Hydrated cart lines for one customer — product name/hsn/tax and the
     * matching pack's label come from the same sources ProductController's
     * search() uses, so a reloaded cart shows the same figures the catalog
     * did when the item was added.
     */
    public function index(): JsonResponse
    {
        $userId = (int) request()->query('user_id', 0);
        if ($userId <= 0) {
            return response()->json(['success' => false, 'message' => 'user_id is required'], 422);
        }

        $rows = DB::table('cart')->where('userid', $userId)->orderBy('cart_id')->get();
        if ($rows->isEmpty()) {
            return response()->json(['success' => true, 'data' => []]);
        }

        $productIds = $rows->pluck('product_id')->unique()->values();
        $products = DB::table('product')
            ->whereIn('product_id', $productIds)
            ->get(['product_id', 'name', 'hsn_code', 'stock_uom'])
            ->keyBy('product_id');
        $taxes = ProductTaxResolver::forProducts($productIds);

        $vendorProductIds = $rows->pluck('vendor_product_id')->filter()->unique()->values();
        $vendorProducts = $vendorProductIds->isEmpty()
            ? collect()
            : DB::table('vendor_products')
                ->whereIn('id', $vendorProductIds)
                ->get(['id', 'packs', 'default_pack_id'])
                ->keyBy('id');

        $data = $rows->map(function ($r) use ($products, $taxes, $vendorProducts) {
            $product = $products->get((int) $r->product_id);
            $tax = $taxes[(int) $r->product_id] ?? null;
            $vp = $r->vendor_product_id ? $vendorProducts->get((int) $r->vendor_product_id) : null;
            $pack = null;
            if ($vp) {
                $packs = ProductController::parsePacks($vp->packs, $vp->default_pack_id);
                foreach ($packs as $p) {
                    if ($p['id'] === $r->pack_id) { $pack = $p; break; }
                }
            }

            return [
                'cart_id'           => (string) $r->cart_id,
                'product_id'        => (string) $r->product_id,
                'name'              => $product->name ?? 'Unknown product',
                'hsn_code'          => $product->hsn_code ?? null,
                'stock_uom'         => $product->stock_uom ?? null,
                'gst_percent'       => $tax['tax_percent']  ?? 0,
                'sgst_percent'      => $tax['sgst_percent'] ?? 0,
                'cgst_percent'      => $tax['cgst_percent'] ?? 0,
                'vendor_product_id' => $r->vendor_product_id ?: null,
                'pack_id'           => $r->pack_id,
                'pack_label'        => $pack['label'] ?? null,
                'unit_price'        => $pack['price']  ?? ($r->quantity > 0 ? round($r->total / $r->quantity, 2) : 0),
                'quantity'          => (int) $r->quantity,
                'total'             => (float) $r->total,
            ];
        });

        return response()->json(['success' => true, 'data' => $data]);
    }

    /**
     * POST /api/cart
     * body: { user_id, product_id, vendor_product_id?, pack_id, quantity, unit_price }
     *
     * Upserts one cart line, matched on the table's real unique key
     * (userid, product_id, pack_id, addressId). quantity <= 0 deletes the
     * line instead of writing a zero-quantity row.
     */
    public function upsert(): JsonResponse
    {
        $data = request()->all();

        $userId   = (int) ($data['user_id'] ?? 0);
        $productId = (int) ($data['product_id'] ?? 0);
        $packId    = trim((string) ($data['pack_id'] ?? ''));
        $quantity  = (int) round((float) ($data['quantity'] ?? 0));
        $unitPrice = (float) ($data['unit_price'] ?? 0);
        $vendorProductId = (int) ($data['vendor_product_id'] ?? 0);

        if ($userId <= 0 || $productId <= 0 || $packId === '') {
            return response()->json(['success' => false, 'message' => 'user_id, product_id and pack_id are required'], 422);
        }

        $buyer = DB::table('user')->where('userid', $userId)->first(['userid']);
        if (!$buyer) {
            return response()->json([
                'success' => false,
                'message' => 'This account has no matching registered customer (user) row — only a real customer has a persisted cart.',
            ], 422);
        }

        $addressId = $this->resolveDefaultAddressId($userId);
        if ($addressId === null) {
            return response()->json([
                'success' => false,
                'message' => 'This customer has no saved address on file yet — add one before adding items to their cart.',
            ], 422);
        }

        $match = [
            'userid'    => $userId,
            'product_id' => $productId,
            'pack_id'   => $packId,
            'addressId' => $addressId,
        ];

        if ($quantity <= 0) {
            DB::table('cart')->where($match)->delete();
            return response()->json(['success' => true, 'data' => ['removed' => true]]);
        }

        $total = round($quantity * $unitPrice, 2);
        $existing = DB::table('cart')->where($match)->first(['cart_id']);

        if ($existing) {
            DB::table('cart')->where('cart_id', $existing->cart_id)->update([
                'vendor_product_id' => $vendorProductId,
                'quantity'          => $quantity,
                'total'             => $total,
            ]);
            $cartId = $existing->cart_id;
        } else {
            $cartId = null;
            DB::transaction(function () use ($match, $vendorProductId, $quantity, $total, &$cartId) {
                $nextId = (int) (DB::table('cart')->lockForUpdate()->max('cart_id')) + 1;
                DB::table('cart')->insert([
                    'cart_id'           => $nextId,
                    'userid'            => $match['userid'],
                    'addressId'         => $match['addressId'],
                    'product_id'        => $match['product_id'],
                    'vendor_product_id' => $vendorProductId,
                    'pack_id'           => $match['pack_id'],
                    'quantity'          => $quantity,
                    'total'             => $total,
                    'ctype_id'          => self::CTYPE_ID,
                    'created_at'        => now(),
                ]);
                $cartId = $nextId;
            });
        }

        return response()->json(['success' => true, 'data' => ['cart_id' => (string) $cartId, 'total' => $total]]);
    }

    /**
     * POST /api/cart/clear  body: { user_id }
     *
     * Called once a sales order is actually created from the cart's
     * contents, so the persisted cart doesn't keep re-showing items that
     * have already been ordered.
     */
    public function clear(): JsonResponse
    {
        $userId = (int) (request()->input('user_id') ?? 0);
        if ($userId <= 0) {
            return response()->json(['success' => false, 'message' => 'user_id is required'], 422);
        }

        DB::table('cart')->where('userid', $userId)->delete();

        return response()->json(['success' => true]);
    }

    /** The customer's default saved address id, falling back to their oldest saved address. */
    private function resolveDefaultAddressId(int $userId): ?int
    {
        $addr = DB::table('user_addresses')
            ->where('user_id', $userId)
            ->orderByDesc('is_default')
            ->orderBy('id')
            ->first(['id']);

        return $addr->id ?? null;
    }
}

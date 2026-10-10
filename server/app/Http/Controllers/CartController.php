<?php

namespace App\Http\Controllers;

use App\Services\OrderPlacementService;
use App\Support\UnitConversion;
use Illuminate\Http\JsonResponse;
use Illuminate\Support\Facades\DB;

/**
 * The customer's cart, as in ORDER_LIFECYCLE_FOR_NEW_FRONTEND.md §15: the
 * order screen fills `cart` (one row per pack, keyed by the customer's userid
 * + saved address), the bill and the order are built from those rows, and the
 * cart is cleared when the order is placed. These are the same rows the
 * consumer app uses, so a customer's cart is shared between the app and CRM.
 *
 *   GET    /api/cart?userid=&address_id=          the cart, with live price / stock
 *   PUT    /api/cart/item                         add / change / remove one pack (≈ addProductToCart)
 *   DELETE /api/cart?userid=&address_id=          empty it (≈ clearCart)
 */
class CartController extends Controller
{
    public function __construct(private OrderPlacementService $orders)
    {
    }

    private function key(): array
    {
        return validator(request()->all(), [
            'userid'     => 'required|integer|min:1',
            'address_id' => 'required|integer|min:1',
        ])->validate();
    }

    public function show(): JsonResponse
    {
        $k = $this->key();
        $rows = $this->orders->cartRows((int) $k['userid'], (int) $k['address_id']);

        $vps = DB::table('vendor_products as vp')->leftJoin('product as p', 'p.product_id', '=', 'vp.product_id')
            ->whereIn('vp.id', $rows->pluck('vendor_product_id')->unique()->values())
            ->get(['vp.id', 'vp.packs', 'vp.default_pack_id', 'p.name', 'p.stock_uom', 'p.hsn_code'])->keyBy('id');

        $items = $rows->map(function ($r) use ($vps) {
            $vp   = $vps->get((int) $r->vendor_product_id);
            $pack = $vp ? collect(ProductController::parsePacks($vp->packs, $vp->default_pack_id, $vp->stock_uom))
                ->firstWhere('id', (string) $r->pack_id) : null;
            return [
                'cart_id'           => (int) $r->cart_id,
                'product_id'        => (string) $r->product_id,
                'vendor_product_id' => (string) $r->vendor_product_id,
                'pack_id'           => (string) $r->pack_id,
                'name'              => $vp->name ?? '',
                'hsn_code'          => $vp && $vp->hsn_code !== null ? (string) $vp->hsn_code : null,
                'pack_label'        => $pack['label'] ?? $r->pack_id,
                'unit'              => $pack['unit_name'] ?? null,
                'quantity'          => (int) $r->quantity,
                'price'             => $pack['price'] ?? 0,     // live rp (the order uses this)
                'total'             => (float) $r->total,       // as saved when added
                'max_qty'           => $pack['stock'] ?? 0,     // units_master conversion + buy cap
                'base_per_pack'     => $pack['base_per_pack'] ?? null,
                'orderable'         => $pack['orderable'] ?? false,
                'blocked_reason'    => $pack ? $pack['blocked_reason'] : 'this pack no longer exists',
            ];
        })->values();

        return response()->json(['success' => true, 'data' => $items]);
    }

    public function setItem(): JsonResponse
    {
        $d = validator(request()->all(), [
            'userid'            => 'required|integer|min:1',
            'address_id'        => 'required|integer|min:1',
            'product_id'        => 'required|integer|min:1',
            'vendor_product_id' => 'required|integer|min:1',
            'pack_id'           => 'required|string|max:255',
            'quantity'          => 'required|integer|min:0|max:65535',
        ])->validate();

        $this->orders->setCartItem((int) $d['userid'], (int) $d['address_id'], (int) $d['product_id'],
            (int) $d['vendor_product_id'], $d['pack_id'], (int) $d['quantity']);

        return response()->json(['success' => true]);
    }

    public function clear(): JsonResponse
    {
        $k = $this->key();
        $this->orders->clearCart((int) $k['userid'], (int) $k['address_id']);

        return response()->json(['success' => true]);
    }
}

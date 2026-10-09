<?php

namespace App\Http\Controllers;

use App\Services\OrderPlacementService;
use Illuminate\Http\JsonResponse;
use Illuminate\Support\Facades\DB;
use Tymon\JWTAuth\Facades\JWTAuth;

/**
 * Sales orders from the CRM, written exactly as described in
 * ORDER_LIFECYCLE_FOR_NEW_FRONTEND.md — see OrderPlacementService.
 *
 *   POST /api/sales-orders/preview   ≈ calculateOrderDetails.php (writes nothing)
 *   POST /api/sales-orders           ≈ placeNewOrder.php
 *   POST /api/orders/{id}/cancel     ≈ cancelOrder.php (pending CRM orders only)
 *
 * The cart is on hold until the cart rules are confirmed, so the item list is
 * sent by the app: items[] = {product_id, vendor_product_id, pack_id, quantity}.
 */
class SalesOrderController extends Controller
{
    public function __construct(private OrderPlacementService $orders)
    {
    }

    private function input(bool $withTotal): array
    {
        return validator(request()->all(), array_filter([
            'buyer_userid'              => 'required|integer|min:1',
            'address_id'                => 'required|integer|min:1',
            'promo_code'                => 'nullable|string|max:100',
            'items'                     => 'required|array|min:1',
            'items.*.product_id'        => 'required|integer|min:1',
            'items.*.vendor_product_id' => 'required|integer|min:1',
            'items.*.pack_id'           => 'required|string|max:255',
            'items.*.quantity'          => 'required|integer|min:1|max:65535',
            'total_amount'              => $withTotal ? 'required|numeric|min:0' : null,
        ]), [
            'items.*.vendor_product_id.required' => 'Pick each product from the catalog (a vendor pack is required).',
            'address_id.required'                => 'Select a saved delivery address for this customer.',
        ])->validate();
    }

    /** POST /api/sales-orders/preview — the bill, exactly as the order would be written. */
    public function preview(): JsonResponse
    {
        $d = $this->input(false);
        $calc = $this->orders->calculate((int) $d['buyer_userid'], (int) $d['address_id'], $d['items'], $d['promo_code'] ?? null);

        return response()->json(['success' => true, 'data' => $this->publicShape($calc)]);
    }

    /** POST /api/sales-orders — place the order (re-calculated on the server; total must match the preview). */
    public function store(): JsonResponse
    {
        $d = $this->input(true);
        $result = $this->orders->place(
            (int) $d['buyer_userid'],
            (int) $d['address_id'],
            $d['items'],
            $d['promo_code'] ?? null,
            (float) $d['total_amount'],
        );

        // The order now owns these items — drop this staff member's CRM draft for the customer.
        DB::table('cart')
            ->where('ctype_id', 'crm_sales_draft')
            ->where('staff_id', (string) JWTAuth::parseToken()->authenticate()->mobile)
            ->where('account_ref', (string) $d['buyer_userid'])
            ->where('account_type', 'customer')
            ->delete();

        return response()->json([
            'success' => true,
            'data'    => [
                'order_id'        => (string) ($result['order_ids'][0] ?? ''),
                'order_ids'       => array_map('strval', $result['order_ids']),
                'master_order_id' => (string) $result['master_order_id'],
                'order_total'     => $result['order_total'],
            ],
        ], 201);
    }

    /** POST /api/orders/{orderId}/cancel — pending CRM orders only (doc §6). */
    public function cancel(string $orderId): JsonResponse
    {
        $this->orders->cancel((int) $orderId);

        return response()->json(['success' => true, 'message' => 'Order cancelled']);
    }

    /** Preview payload for the app (internal keys like address/promo id stripped). */
    private function publicShape(array $calc): array
    {
        $vendors = [];
        foreach ($calc['vendors'] as $v) {
            $vendors[] = [
                'vendor_id'             => $v['vendor_id'],
                'items'                 => array_map(fn ($l) => [
                    'product_id'        => (string) $l['product_id'],
                    'vendor_product_id' => (string) $l['vendor_product_id'],
                    'pack_id'           => $l['pack_id'],
                    'name'              => $l['name'],
                    'pack'              => $l['pack']['tx'] ?? $l['pack_id'],
                    'quantity'          => $l['quantity'],
                    'item_price'        => $l['item_price'],
                    'item_total'        => $l['item_total'],
                ], $v['cartList']),
                'free_items'            => array_map(fn ($f) => [
                    'product_id' => (string) $f['product_id'],
                    'name'       => $f['name'],
                    'pack'       => $f['pack']['tx'] ?? $f['pack_id'],
                    'quantity'   => $f['quantity'],
                    'offer'      => $f['offer_name'],
                ], $v['freeItems']),
                'subtotal'              => $v['subtotal'],
                'delivery_charge'       => $v['deliveryCharge'],
                'free_delivery_above'   => $v['freeDeliMinTotal'],
                'before_discount'       => $v['beforeDiscount'],
                'offer_discount'        => $v['offerDiscount'],
                'promo_discount'        => $v['promoCodeDiscount'],
                'new_customer_discount' => $v['newCustomerDiscount'],
                'total'                 => $v['afterDiscount'],
                'time_slot'             => $v['timeSlotText'],
            ];
        }

        return [
            'vendors'         => $vendors,
            'items_count'     => $calc['order_count'],
            'before_discount' => $calc['beforeDiscount'],
            'delivery_charge' => $calc['deliveryCharge'],
            'offer_discount'  => $calc['offerDiscount'],
            'promo_discount'  => $calc['promoCodeDiscount']['discount'],
            'promo_message'   => $calc['promoCodeDiscount']['description'],
            'total'           => $calc['afterDiscount'],
        ];
    }
}

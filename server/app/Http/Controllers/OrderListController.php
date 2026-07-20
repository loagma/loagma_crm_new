<?php

namespace App\Http\Controllers;

use Illuminate\Http\JsonResponse;
use Illuminate\Support\Facades\DB;

class OrderListController extends Controller
{
    /**
     * GET /api/orders
     *
     * Paginated order list joined against the buyer's own profile (`user`),
     * their default saved address (`user_addresses`), and the fulfilling
     * admin/partner (`admin`). Address/coordinates resolve in priority order:
     * orders.delivery_info (JSON snapshot at order time, since a delivery can
     * be addressed to a different person/location than the account holder) >
     * user_addresses default row (current address book entry) > flat
     * user.address/latitude/longitude columns (legacy fallback).
     */
    public function index(): JsonResponse
    {
        $q          = trim((string) request()->query('q', ''));
        $status     = request()->query('payment_status');
        $buyerId    = request()->query('buyer_userid');
        $perPage    = (int) request()->query('per_page', 20);
        $page       = max(1, (int) request()->query('page', 1));

        $query = DB::table('orders')
            ->leftJoin('user', 'orders.buyer_userid', '=', 'user.userid')
            ->leftJoin('admin', 'orders.admin_id', '=', 'admin.userid')
            // Buyer's default saved address (user_addresses) — more current than
            // the flat user.address/latitude/longitude columns.
            ->leftJoin('user_addresses', function ($join) {
                $join->on('user_addresses.user_id', '=', 'user.userid')
                     ->where('user_addresses.is_default', '=', '1');
            })
            ->select([
                'orders.order_id',
                'orders.buyer_userid',
                'orders.order_state',
                'orders.payment_status',
                'orders.payment_method',
                // orders.items_count is a denormalized counter that can go stale
                // relative to the real orders_item rows (seen on legacy orders,
                // e.g. #212226 claims 2 items but has 0 actual rows) — count the
                // real rows instead so the list matches what the detail screen shows.
                DB::raw('(SELECT COUNT(*) FROM orders_item WHERE orders_item.order_id = orders.order_id) as real_items_count'),
                'orders.order_total',
                'orders.area_name',
                'orders.short_datetime',
                'orders.time_slot',
                'orders.delivery_info',
                'orders.invoice_pdf_url',
                'admin.name as admin_name',
                'user.shop_name as buyer_shop_name',
                'user.name as buyer_name',
                'user.address as buyer_address',
                'user.shop_address as buyer_shop_address',
                'user.contactno as buyer_contactno',
                'user.latitude as buyer_latitude',
                'user.longitude as buyer_longitude',
                'user_addresses.full_address as buyer_saved_address',
                'user_addresses.lat as buyer_saved_lat',
                'user_addresses.lng as buyer_saved_lng',
            ]);

        if ($status) {
            $query->where('orders.payment_status', $status);
        }

        if ($buyerId) {
            $query->where('orders.buyer_userid', $buyerId);
        }

        if ($q !== '') {
            $query->where(function ($sub) use ($q) {
                $sub->where('orders.order_id', 'like', "%{$q}%")
                    ->orWhere('user.shop_name', 'like', "%{$q}%")
                    ->orWhere('user.name', 'like', "%{$q}%")
                    ->orWhere('user.contactno', 'like', "%{$q}%");
            });
        }

        $total = (clone $query)->count();

        $rows = $query
            ->orderByDesc('orders.order_id')
            ->forPage($page, $perPage)
            ->get();

        $data = $rows->map(function ($row) {
            $delivery = json_decode((string) $row->delivery_info, true) ?: [];
            $realItemsCount = (int) $row->real_items_count;

            return [
                'order_id'        => (string) $row->order_id,
                'buyer_userid'    => (string) $row->buyer_userid,
                'order_state'     => $row->order_state,
                'payment_status'  => $row->payment_status,
                'payment_method'  => $row->payment_method,
                'items_count'     => $realItemsCount,
                // orders.order_total has no meaning once the real orders_item
                // rows are gone (see #212226/#212429 — stale legacy total with
                // 0 matching item rows) — show it as having no derivable value
                // rather than a number that can't be traced to any line item.
                'order_total'     => $realItemsCount > 0 ? (float) $row->order_total : 0.0,
                'area_name'       => trim((string) $row->area_name),
                'admin_name'      => $row->admin_name,
                'order_datetime'  => $row->short_datetime,
                'delivery_window' => $row->time_slot,
                'invoice_pdf_url' => $row->invoice_pdf_url,
                'shop_name'       => $row->buyer_shop_name ?: ($delivery['name'] ?? ''),
                'contact_name'    => $delivery['name'] ?? $row->buyer_name,
                'address'         => $delivery['address'] ?? ($row->buyer_saved_address ?: ($row->buyer_shop_address ?: $row->buyer_address)),
                'contact_number'  => $delivery['contactno'] ?? $row->buyer_contactno,
                'latitude'        => $delivery['latitude'] ?? ($row->buyer_saved_lat ?? $row->buyer_latitude),
                'longitude'       => $delivery['longitude'] ?? ($row->buyer_saved_lng ?? $row->buyer_longitude),
            ];
        });

        return response()->json([
            'success' => true,
            'data'    => $data,
            'meta'    => [
                'current_page' => $page,
                'last_page'    => (int) ceil($total / max($perPage, 1)),
                'per_page'     => $perPage,
                'total'        => $total,
            ],
        ]);
    }

    /**
     * GET /api/orders/{orderId}
     *
     * Full detail for one order: owner/shop profile (from `user`, not the
     * delivery_info override — the owner card shows the account holder,
     * while the separate delivery address can differ), driver assignment
     * (deli_staff, matched by `orders.deli_id`), and line items joined
     * against `product` for their names.
     */
    public function show(string $orderId): JsonResponse
    {
        $order = DB::table('orders')
            ->leftJoin('user', 'orders.buyer_userid', '=', 'user.userid')
            ->leftJoin('admin', 'orders.admin_id', '=', 'admin.userid')
            ->leftJoin('user_addresses', function ($join) {
                $join->on('user_addresses.user_id', '=', 'user.userid')
                     ->where('user_addresses.is_default', '=', '1');
            })
            ->where('orders.order_id', $orderId)
            ->select([
                'orders.*',
                'admin.name as admin_name',
                'user.shop_name as owner_shop_name',
                'user.name as owner_name',
                'user.contactno as owner_contact',
                'user.address as owner_address',
                'user.shop_address as owner_shop_address',
                'user.latitude as owner_latitude',
                'user.longitude as owner_longitude',
                'user_addresses.full_address as owner_saved_address',
                'user_addresses.lat as owner_saved_lat',
                'user_addresses.lng as owner_saved_lng',
            ])
            ->first();

        if (!$order) {
            return response()->json(['success' => false, 'message' => 'Order not found'], 404);
        }

        $delivery = json_decode((string) $order->delivery_info, true) ?: [];

        $driver = null;
        if (!empty($order->deli_id)) {
            $d = DB::table('deli_staff')->where('deli_id', $order->deli_id)->first(['name', 'mobile']);
            if ($d) {
                $driver = ['name' => $d->name, 'mobile' => $d->mobile];
            }
        }

        $itemRows = DB::table('orders_item')
            ->leftJoin('product', 'orders_item.product_id', '=', 'product.product_id')
            ->where('orders_item.order_id', $orderId)
            ->select([
                'orders_item.product_id',
                'orders_item.pinfo',
                'orders_item.quantity',
                'orders_item.qty_delivered',
                'orders_item.item_price',
                'orders_item.item_total',
                'product.name as product_name',
            ])
            ->get();

        $items = $itemRows->map(function ($row) {
            $pinfo = json_decode((string) $row->pinfo, true) ?: [];
            return [
                'product_id'   => (string) $row->product_id,
                'name'         => $row->product_name ?: ($pinfo['tx'] ?? 'Item'),
                'pack_size'    => $pinfo['ps'] ?? null,
                'quantity'     => (int) $row->quantity,
                'qty_delivered' => $row->qty_delivered !== null ? (int) $row->qty_delivered : 0,
                'item_price'   => (float) $row->item_price,
                'item_total'   => (float) $row->item_total,
            ];
        })->values();

        return response()->json([
            'success' => true,
            'data' => [
                'order_id'         => (string) $order->order_id,
                'buyer_userid'     => (string) $order->buyer_userid,
                'order_state'      => $order->order_state,
                'payment_status'   => $order->payment_status,
                'payment_method'   => $order->payment_method,
                // Same reasoning as index(): a stored total that can't be traced
                // to any real orders_item row (legacy data gap) isn't shown as if
                // it were a verified figure.
                'order_total'      => $items->isNotEmpty() ? (float) $order->order_total : 0.0,
                'before_discount'  => $items->isNotEmpty() ? (float) $order->before_discount : 0.0,
                'discount'         => (float) $order->discount,
                'delivery_charge'  => (float) $order->delivery_charge,
                'items_count'      => $items->count(),
                'order_datetime'   => $order->short_datetime,
                'delivery_window'  => $order->time_slot,
                'area_name'        => trim((string) $order->area_name),
                'admin_name'       => $order->admin_name,
                'invoice_pdf_url'  => $order->invoice_pdf_url,
                // `user` has no matching row for most historical orders (buyer_userid
                // predates this table's data), so fall back to the delivery_info snapshot
                // stored on the order itself — same fallback the list endpoint uses.
                'shop_name'        => $order->owner_shop_name,
                'owner_name'       => $order->owner_name ?: ($delivery['name'] ?? null),
                'owner_contact'    => $order->owner_contact ?: ($delivery['contactno'] ?? null),
                'delivery_address' => $delivery['address'] ?? ($order->owner_saved_address ?: ($order->owner_shop_address ?: $order->owner_address)),
                'latitude'         => $delivery['latitude'] ?? ($order->owner_saved_lat ?? $order->owner_latitude),
                'longitude'        => $delivery['longitude'] ?? ($order->owner_saved_lng ?? $order->owner_longitude),
                'driver'           => $driver,
                'items'            => $items,
            ],
        ]);
    }

    /**
     * GET /api/orders/owner/{buyerUserId}/products
     *
     * Aggregated purchase history per product for one buyer, across all of
     * their orders — powers the "Product-wise History" tab on the order
     * detail screen.
     */
    public function ownerProductHistory(string $buyerUserId): JsonResponse
    {
        $rows = DB::table('orders_item')
            ->join('orders', 'orders_item.order_id', '=', 'orders.order_id')
            ->leftJoin('product', 'orders_item.product_id', '=', 'product.product_id')
            ->where('orders.buyer_userid', $buyerUserId)
            ->groupBy('orders_item.product_id', 'product.name')
            ->select([
                'orders_item.product_id',
                'product.name as product_name',
                DB::raw('SUM(orders_item.quantity) as total_qty'),
                DB::raw('SUM(orders_item.item_total) as total_amount'),
                DB::raw('COUNT(DISTINCT orders_item.order_id) as order_count'),
            ])
            ->orderByDesc('total_amount')
            ->get();

        $data = $rows->map(fn ($row) => [
            'product_id'    => (string) $row->product_id,
            'name'          => $row->product_name ?: 'Item',
            'total_qty'     => (int) $row->total_qty,
            'total_amount'  => (float) $row->total_amount,
            'order_count'   => (int) $row->order_count,
        ]);

        return response()->json(['success' => true, 'data' => $data]);
    }
}

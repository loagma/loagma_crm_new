<?php

namespace App\Http\Controllers;

use Illuminate\Http\JsonResponse;
use Illuminate\Support\Facades\DB;
use Tymon\JWTAuth\Facades\JWTAuth;

/**
 * Server-side persistence for the Create Sales Order sheet's cart.
 *
 * Stored on the shared `cart` table (see the
 * 2026_09_05_000001_move_sales_order_draft_to_cart migration for the layout and
 * why it is safe alongside the consumer app). One row per (staff member,
 * account), tagged `ctype_id = self::CTYPE`, holding the whole draft as JSON in
 * `draft_payload`. The salesman's in-person draft and the telecaller's phone
 * draft for the same shop stay independent because `staff_id` is part of the
 * key. Works identically for lead and customer accounts.
 *
 * The draft is written on every cart edit and deleted the moment an order is
 * actually created from it.
 */
class SalesOrderDraftController extends Controller
{
    /** `cart.ctype_id` sentinel for CRM draft rows — maps to no `cart_type`. */
    private const CTYPE = 'crm_sales_draft';

    /**
     * GET /api/order-draft?account_id=...&account_type=lead|customer
     *
     * The stored payload verbatim, except that every catalog-sourced line's
     * `max_qty` is re-resolved against live `vendor_products` stock.
     */
    public function show(): JsonResponse
    {
        $staffId = self::staffId();
        if ($staffId === null) {
            return response()->json(['success' => false, 'message' => 'Not authenticated'], 401);
        }

        $accountId   = trim((string) request()->query('account_id', ''));
        $accountType = trim((string) request()->query('account_type', ''));
        if ($accountId === '' || !in_array($accountType, ['lead', 'customer'], true)) {
            return response()->json(['success' => false, 'message' => 'account_id and account_type are required'], 422);
        }

        $row = $this->rowQuery($staffId, $accountId, $accountType)
            ->first(['draft_payload', 'created_at']);

        if (!$row) {
            return response()->json(['success' => true, 'data' => null]);
        }

        $payload = json_decode((string) $row->draft_payload, true);
        if (!is_array($payload)) {
            // A payload we can't parse is worse than no draft at all.
            $this->deleteFor($staffId, $accountId, $accountType);
            return response()->json(['success' => true, 'data' => null]);
        }

        $payload['items']      = $this->withLiveStock($payload['items'] ?? []);
        $payload['updated_at'] = $row->created_at;

        return response()->json(['success' => true, 'data' => $payload]);
    }

    /**
     * PUT /api/order-draft
     * body: { account_id, account_type, payload: {...} }
     *
     * Upserts the whole draft. Called (debounced) on every cart edit, so it
     * stays a single-row write and never partially applies.
     */
    public function store(): JsonResponse
    {
        $staffId = self::staffId();
        if ($staffId === null) {
            return response()->json(['success' => false, 'message' => 'Not authenticated'], 401);
        }

        $accountId   = trim((string) request()->input('account_id', ''));
        $accountType = trim((string) request()->input('account_type', ''));
        $payload     = request()->input('payload');

        if ($accountId === '' || !in_array($accountType, ['lead', 'customer'], true)) {
            return response()->json(['success' => false, 'message' => 'account_id and account_type are required'], 422);
        }
        if (!is_array($payload)) {
            return response()->json(['success' => false, 'message' => 'payload must be an object'], 422);
        }

        $encoded = json_encode($payload);
        if ($encoded === false) {
            return response()->json(['success' => false, 'message' => 'payload is not encodable'], 422);
        }

        DB::transaction(function () use ($staffId, $accountId, $accountType, $encoded) {
            $existing = $this->rowQuery($staffId, $accountId, $accountType)
                ->lockForUpdate()
                ->first(['cart_id']);

            if ($existing) {
                DB::table('cart')->where('cart_id', $existing->cart_id)->update([
                    'draft_payload' => $encoded,
                    'created_at'    => now(),
                ]);
                return;
            }

            // `cart.cart_id` has no AUTO_INCREMENT — allocate MAX+1 under lock.
            $nextId = (int) DB::table('cart')->lockForUpdate()->max('cart_id') + 1;

            DB::table('cart')->insert([
                'cart_id'           => $nextId,
                'userid'            => $accountType === 'customer' ? (int) $accountId : 0,
                'addressId'         => 0,
                'product_id'        => 0,
                'vendor_product_id' => 0,
                'pack_id'           => "crmdraft:{$staffId}|{$accountType}|{$accountId}",
                'quantity'          => 0,
                'total'             => 0,
                'ctype_id'          => self::CTYPE,
                'created_at'        => now(),
                'staff_id'          => $staffId,
                'account_ref'       => $accountId,
                'account_type'      => $accountType,
                'draft_payload'     => $encoded,
            ]);
        });

        return response()->json(['success' => true]);
    }

    /**
     * DELETE /api/order-draft?account_id=...&account_type=...
     * Called once an order is created from the draft (and when the cart is
     * emptied back to nothing).
     */
    public function destroy(): JsonResponse
    {
        $staffId = self::staffId();
        if ($staffId === null) {
            return response()->json(['success' => false, 'message' => 'Not authenticated'], 401);
        }

        $accountId   = trim((string) request()->query('account_id', ''));
        $accountType = trim((string) request()->query('account_type', ''));
        if ($accountId === '' || !in_array($accountType, ['lead', 'customer'], true)) {
            return response()->json(['success' => false, 'message' => 'account_id and account_type are required'], 422);
        }

        $this->deleteFor($staffId, $accountId, $accountType);

        return response()->json(['success' => true]);
    }

    /** The (staff, account) draft row on `cart`. */
    private function rowQuery(string $staffId, string $accountId, string $accountType)
    {
        return DB::table('cart')
            ->where('ctype_id', self::CTYPE)
            ->where('staff_id', $staffId)
            ->where('account_ref', $accountId)
            ->where('account_type', $accountType);
    }

    private function deleteFor(string $staffId, string $accountId, string $accountType): void
    {
        $this->rowQuery($staffId, $accountId, $accountType)->delete();
    }

    /**
     * Refresh each line's `max_qty` from the pack it was added from. Hand-typed
     * lines (no vendor pack) are passed through untouched.
     *
     * @param  mixed  $items
     * @return list<array<string, mixed>>
     */
    private function withLiveStock($items): array
    {
        if (!is_array($items) || $items === []) {
            return [];
        }

        $vendorProductIds = collect($items)
            ->pluck('vendor_product_id')
            ->filter(fn ($id) => $id !== null && $id !== '')
            ->unique()
            ->values();

        $vendorProducts = $vendorProductIds->isEmpty()
            ? collect()
            : DB::table('vendor_products')
                ->whereIn('id', $vendorProductIds)
                ->get(['id', 'packs', 'default_pack_id'])
                ->keyBy('id');

        return collect($items)->map(function ($item) use ($vendorProducts) {
            if (!is_array($item)) {
                return $item;
            }
            $vpId   = $item['vendor_product_id'] ?? null;
            $packId = $item['pack_id'] ?? null;
            if ($vpId === null || $vpId === '' || $packId === null || $packId === '') {
                return $item;
            }
            $vp = $vendorProducts->get((int) $vpId);
            if (!$vp) {
                return $item;
            }
            foreach (ProductController::parsePacks($vp->packs, $vp->default_pack_id) as $pack) {
                if ($pack['id'] === (string) $packId) {
                    $item['max_qty'] = $pack['stock'];
                    break;
                }
            }
            return $item;
        })->values()->all();
    }

    /**
     * The logged-in staff member's `deli_staff.mobile`.
     */
    private static function staffId(): ?string
    {
        try {
            $staff = JWTAuth::parseToken()->authenticate();
            $mobile = $staff?->mobile;
            return ($mobile === null || $mobile === '') ? null : (string) $mobile;
        } catch (\Throwable $e) {
            return null;
        }
    }
}

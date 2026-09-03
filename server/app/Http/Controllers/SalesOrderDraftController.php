<?php

namespace App\Http\Controllers;

use Illuminate\Http\JsonResponse;
use Illuminate\Support\Facades\DB;
use Tymon\JWTAuth\Facades\JWTAuth;

/**
 * Server-side persistence for the Create Sales Order sheet's cart, backed by
 * `sales_order_draft_crm` — a CRM-owned table, NOT the shared `cart` table
 * (see that migration for why `cart` can't hold this).
 *
 * Scoped to (staff member, account): the salesman's in-person draft for a
 * shop and the telecaller's phone draft for that same shop never see each
 * other. Works identically for lead and customer accounts, since nothing here
 * depends on the account having a `user` row.
 *
 * The draft is written on every cart edit and deleted the moment an order is
 * actually created from it, so re-opening the sheet after a checkout starts
 * clean while re-opening it after a plain close restores exactly what was
 * there.
 */
class SalesOrderDraftController extends Controller
{
    /**
     * GET /api/order-draft?account_id=...&account_type=lead|customer
     *
     * The stored payload verbatim, except that every catalog-sourced line's
     * `max_qty` is re-resolved against live `vendor_products` stock — a draft
     * can sit for days, and letting it submit against a stale stock figure is
     * the one thing worth not restoring faithfully.
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

        $row = DB::table('sales_order_draft_crm')
            ->where('staff_id', $staffId)
            ->where('account_id', $accountId)
            ->where('account_type', $accountType)
            ->first(['payload', 'updated_at']);

        if (!$row) {
            return response()->json(['success' => true, 'data' => null]);
        }

        $payload = json_decode($row->payload, true);
        if (!is_array($payload)) {
            // A payload we can't parse is worse than no draft at all — drop it
            // rather than handing the client something it will choke on.
            $this->deleteFor($staffId, $accountId, $accountType);
            return response()->json(['success' => true, 'data' => null]);
        }

        $payload['items']      = $this->withLiveStock($payload['items'] ?? []);
        $payload['updated_at'] = $row->updated_at;

        return response()->json(['success' => true, 'data' => $payload]);
    }

    /**
     * PUT /api/order-draft
     * body: { account_id, account_type, payload: {...} }
     *
     * Upserts the whole draft. The sheet calls this (debounced) on every cart
     * edit, so it must stay cheap and must never partially apply — hence one
     * JSON column rather than a diffed row-per-item table.
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

        $match = [
            'staff_id'     => $staffId,
            'account_id'   => $accountId,
            'account_type' => $accountType,
        ];

        // updateOrInsert matches the table's own unique key, so two rapid
        // autosaves can't race into a duplicate row.
        DB::table('sales_order_draft_crm')->updateOrInsert($match, [
            'payload'    => $encoded,
            'updated_at' => now(),
            'created_at' => now(),
        ]);

        return response()->json(['success' => true]);
    }

    /**
     * DELETE /api/order-draft?account_id=...&account_type=...
     *
     * Called once an order is actually created from the draft (and when the
     * cart is emptied back to nothing), so the next open starts clean.
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

    private function deleteFor(string $staffId, string $accountId, string $accountType): void
    {
        DB::table('sales_order_draft_crm')
            ->where('staff_id', $staffId)
            ->where('account_id', $accountId)
            ->where('account_type', $accountType)
            ->delete();
    }

    /**
     * Refresh each line's `max_qty` from the pack it was added from. Lines
     * with no vendor pack (hand-typed items) are passed through untouched —
     * they never had a stock figure to go stale.
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
     * The logged-in staff member's `deli_staff.mobile` — the same identity
     * BeatPlanController::salesmanId() and beat_plan_followup_crm.staff_id
     * use, so a draft belongs to the person, not the device or the role.
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

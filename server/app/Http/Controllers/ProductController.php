<?php

namespace App\Http\Controllers;

use App\Support\ProductTaxResolver;
use Illuminate\Http\JsonResponse;
use Illuminate\Support\Facades\DB;
use Tymon\JWTAuth\Facades\JWTAuth;

class ProductController extends Controller
{
    /**
     * GET /api/products/search?q=...
     *
     * Real catalog lookup against `product` (not a mock list) — used by the
     * Sales Order line-item picker so `orders_item.product_id` always points
     * at a genuine product (that column is NOT NULL, no free-text items).
     *
     * Basic details (name, hsn_code) come from `product`, which is shared
     * across every vendor. Pack/pricing is NOT — `vendor_products` carries a
     * separate `packs` blob per (product_id, admin_vendor_id), because the
     * same product is priced differently by each vendor. Which vendor's
     * prices to show is therefore per logged-in staff member, not fixed:
     * `deli_staff.admin_id` says which vendor a given telecaller/salesman
     * account belongs to (mirrors `BeatPlanController::salesmanId()`'s JWT
     * pattern) — a product with no `vendor_products` row for *that* vendor
     * has no real price here (falls back to manual entry client-side), even
     * if other vendors do carry it.
     */
    public function search(): JsonResponse
    {
        $q = trim((string) request()->query('q', ''));
        $adminId = self::currentVendorAdminId();

        $query = DB::table('product')
            ->where('is_deleted', 0)
            ->where('is_published', 1)
            ->select(['product_id', 'name', 'hsn_code', 'stock_uom', 'cat_id', 'parent_cat_id']);

        // Only show products this vendor actually carries — a `product` row
        // with no `vendor_products` listing for the logged-in staff's
        // admin_id isn't sellable by them, so it shouldn't appear in their
        // catalog at all (previously it could still surface with no pricing).
        if ($adminId !== null) {
            $query->whereExists(function ($w) use ($adminId) {
                $w->select(DB::raw(1))
                    ->from('vendor_products')
                    ->whereColumn('vendor_products.product_id', 'product.product_id')
                    ->where('vendor_products.admin_vendor_id', $adminId)
                    ->where('vendor_products.status', '1');
            });
        }

        if ($q !== '') {
            // `product.name`/`short_name`/`keywords` are collated utf8mb4_bin
            // (case-sensitive) on this DB, so a plain LIKE only matches exact
            // case — telecallers type lowercase/mixed case while most real
            // product names are upper/mixed case, so this silently returned 0
            // results for the vast majority of genuine searches until forcing
            // both sides through LOWER().
            //
            // Matches on any of: product_id (exact), name, short_name,
            // keywords — short_name is blank for most rows and keywords often
            // just duplicates name, but both DO carry real synonyms/codes for
            // some products that name alone misses.
            $like = '%' . mb_strtolower($q) . '%';
            $query->where(function ($w) use ($q, $like) {
                $w->whereRaw('LOWER(name) LIKE ?', [$like])
                    ->orWhereRaw('LOWER(short_name) LIKE ?', [$like])
                    ->orWhereRaw('LOWER(keywords) LIKE ?', [$like]);
                // product_id is a bigint — only compare it against a purely
                // numeric term, so a text search doesn't get coerced to 0 and
                // accidentally match an unrelated row.
                if (ctype_digit($q)) {
                    $w->orWhere('product_id', (int) $q);
                }
            });
        }

        $rows = $query->orderBy('name')->limit(20)->get();
        $productIds = $rows->pluck('product_id');

        // Rates come from `product_taxes`, the same resolver the order write path
        // uses — so the figure the telecaller sees while picking a product is the
        // figure that actually gets booked. `product.gst_percent` is stale/zero
        // for about half the catalog and is only a last-resort fallback inside
        // the resolver.
        $taxes = ProductTaxResolver::forProducts($productIds);

        $vendorProducts = $adminId === null
            ? collect()
            : DB::table('vendor_products')
                ->where('admin_vendor_id', $adminId)
                ->where('status', '1')
                ->whereIn('product_id', $productIds)
                ->get(['id', 'product_id', 'packs', 'default_pack_id'])
                ->keyBy('product_id');

        return response()->json([
            'success' => true,
            'data' => $rows->map(function ($r) use ($taxes, $vendorProducts, $adminId) {
                $tax = $taxes[(int) $r->product_id];
                $vp = $vendorProducts->get((int) $r->product_id);
                return [
                    'product_id'      => (string) $r->product_id,
                    'name'            => $r->name,
                    'hsn_code'        => $r->hsn_code,
                    'gst_percent'     => $tax['tax_percent'],
                    'sgst_percent'    => $tax['sgst_percent'],
                    'cgst_percent'    => $tax['cgst_percent'],
                    'stock_uom'       => $r->stock_uom,
                    // On `product`, confusingly, `parent_cat_id` is the
                    // top-level category and `cat_id` is the more specific
                    // subcategory (verified against `categories.parent_cat_id`
                    // — a category row with parent_cat_id=0 is top-level, and
                    // product.parent_cat_id always resolves to one of those).
                    'vendor_id'       => $adminId,
                    'cat_id'          => $r->parent_cat_id,
                    'subcat_id'       => $r->cat_id,
                    // The row id of this product's vendor-specific listing in
                    // `vendor_products` — i.e. this vendor's own id for the
                    // product. Null when the vendor has no listing for it at
                    // all (same case where packs is empty).
                    'vendor_product_id' => $vp->id ?? null,
                    'default_pack_id' => $vp->default_pack_id ?? null,
                    'packs'           => $vp ? self::parsePacks($vp->packs, $vp->default_pack_id) : [],
                ];
            }),
        ]);
    }

    /**
     * The logged-in deli_staff's own admin_id — i.e. which vendor's catalog
     * they sell for. Null (not an exception) if the request has no/invalid
     * token, since this route isn't behind `jwtauth` middleware — callers
     * degrade to "no pack pricing" rather than a hard failure.
     */
    private static function currentVendorAdminId(): ?int
    {
        try {
            $staff = JWTAuth::parseToken()->authenticate();
            return $staff?->admin_id !== null ? (int) $staff->admin_id : null;
        } catch (\Throwable $e) {
            return null;
        }
    }

    /**
     * `vendor_products.packs` is a JSON object keyed by pack id — e.g.
     * {"diGd":{"tx":"1 kg","op":90,"rp":60,"ps":"1","pu":"kg","pi":"diGd","stk":42}}
     * where `tx` is the display label, `op` the MRP, `rp` the actual selling
     * price (same shape `product.packs` used before pricing moved to being
     * vendor-scoped — see the class doc comment on search()), and `stk` the
     * available stock (per docs/SALES_MODULE.md §7, this is the authoritative
     * stock figure for PACK_WISE products — the legacy stock-ledger mutation
     * keeps every pack's `stk` in the same `vendor_products` row in sync with
     * each other, so any one pack's `stk` already reflects the shared pool).
     * Most (product_id, vendor) pairs have no row at all, so callers must
     * handle an empty result (no priced pack to pick) rather than assume
     * every product has one.
     *
     * @return list<array{id: string, label: string, mrp: float, price: float, is_default: bool, stock: int}>
     */
    private static function parsePacks(?string $raw, ?string $defaultPackId): array
    {
        if ($raw === null || $raw === '' || $raw === '[]') {
            return [];
        }
        $decoded = json_decode($raw, true);
        if (!is_array($decoded) || array_is_list($decoded)) {
            return []; // malformed or the empty-array shape ("[]") already handled above
        }

        $packs = [];
        foreach ($decoded as $id => $p) {
            if (!is_array($p)) continue;
            $packs[] = [
                'id'         => (string) $id,
                'label'      => (string) ($p['tx'] ?? $id),
                'mrp'        => (float) ($p['op'] ?? 0),
                'price'      => (float) ($p['rp'] ?? ($p['op'] ?? 0)),
                'is_default' => (string) $id === (string) $defaultPackId,
                'stock'      => (int) ($p['stk'] ?? 0),
            ];
        }
        return $packs;
    }
}

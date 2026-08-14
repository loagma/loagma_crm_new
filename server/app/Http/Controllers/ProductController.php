<?php

namespace App\Http\Controllers;

use App\Support\ProductTaxResolver;
use Illuminate\Http\JsonResponse;
use Illuminate\Support\Facades\DB;

class ProductController extends Controller
{
    /**
     * GET /api/products/search?q=...
     *
     * Real catalog lookup against `product` (not a mock list) — used by the
     * Sales Order line-item picker so `orders_item.product_id` always points
     * at a genuine product (that column is NOT NULL, no free-text items).
     */
    public function search(): JsonResponse
    {
        $q = trim((string) request()->query('q', ''));

        $query = DB::table('product')
            ->where('is_deleted', 0)
            ->select(['product_id', 'name', 'hsn_code']);

        if ($q !== '') {
            // `product.name` is collated utf8mb4_bin (case-sensitive) on this
            // DB, so a plain LIKE only matches exact case — telecallers type
            // lowercase/mixed case while most real product names are
            // upper/mixed case, so this silently returned 0 results for the
            // vast majority of genuine searches until forcing both sides
            // through LOWER().
            $query->whereRaw('LOWER(name) LIKE ?', ['%' . mb_strtolower($q) . '%']);
        }

        $rows = $query->orderBy('name')->limit(20)->get();

        // Rates come from `product_taxes`, the same resolver the order write path
        // uses — so the figure the telecaller sees while picking a product is the
        // figure that actually gets booked. `product.gst_percent` is stale/zero
        // for about half the catalog and is only a last-resort fallback inside
        // the resolver.
        $taxes = ProductTaxResolver::forProducts($rows->pluck('product_id'));

        return response()->json([
            'success' => true,
            'data' => $rows->map(function ($r) use ($taxes) {
                $tax = $taxes[(int) $r->product_id];
                return [
                    'product_id'   => (string) $r->product_id,
                    'name'         => $r->name,
                    'hsn_code'     => $r->hsn_code,
                    'gst_percent'  => $tax['tax_percent'],
                    'sgst_percent' => $tax['sgst_percent'],
                    'cgst_percent' => $tax['cgst_percent'],
                ];
            }),
        ]);
    }
}

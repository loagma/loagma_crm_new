<?php

namespace App\Http\Controllers;

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
            $query->where('name', 'like', "%{$q}%");
        }

        $rows = $query->orderBy('name')->limit(20)->get();

        return response()->json([
            'success' => true,
            'data' => $rows->map(fn ($r) => [
                'product_id' => (string) $r->product_id,
                'name'       => $r->name,
                'hsn_code'   => $r->hsn_code,
            ]),
        ]);
    }
}

<?php

namespace App\Support;

use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;

/**
 * Resolves a product's real GST rate from `product_taxes` (joined to `taxes`),
 * which is where the parent app actually maintains rates.
 *
 * `product.gst_percent` is NOT usable as the source: roughly half the catalog
 * (6031 of 12598 live products) has gst_percent = 0.00 while `product_taxes`
 * holds the genuine SGST/CGST rows for 12596 of them — deriving tax from
 * gst_percent silently booked zero tax on those orders.
 */
class ProductTaxResolver
{
    /**
     * @param  iterable<int|string>  $productIds
     * @return array<int, array{tax_percent: float, sgst_percent: float, cgst_percent: float, igst_percent: float, cess_percent: float}>
     *         keyed by product_id
     */
    public static function forProducts(iterable $productIds): array
    {
        $ids = collect($productIds)->filter()->map(fn ($id) => (int) $id)->unique()->values();
        if ($ids->isEmpty()) {
            return [];
        }

        $today = Carbon::now()->toDateString();

        // Only rows whose tax_id resolves to an active `taxes` row are trusted —
        // product_taxes contains a handful of orphaned tax_ids (1 and 6, 9 rows
        // total) with no matching taxes row, which would otherwise be counted as
        // an unknown tax component.
        $rows = DB::table('product_taxes')
            ->join('taxes', 'taxes.id', '=', 'product_taxes.tax_id')
            ->whereIn('product_taxes.product_id', $ids)
            ->where('taxes.is_active', 1)
            ->where(fn ($q) => $q->whereNull('product_taxes.effective_from')->orWhere('product_taxes.effective_from', '<=', $today))
            ->where(fn ($q) => $q->whereNull('product_taxes.effective_to')->orWhere('product_taxes.effective_to', '>=', $today))
            ->orderBy('product_taxes.id')
            ->get([
                'product_taxes.product_id',
                'product_taxes.tax_percent',
                'taxes.tax_name',
            ]);

        // product_taxes has duplicate (product_id, tax_name) rows from repeated
        // backfills — e.g. product 532 carries two identical SGST/CGST/IGST
        // triplets. Ordering by id and overwriting keeps the newest row per
        // component instead of summing the duplicates into a doubled rate.
        $byProduct = [];
        foreach ($rows as $row) {
            $byProduct[(int) $row->product_id][strtoupper($row->tax_name)] = (float) $row->tax_percent;
        }

        $fallback = DB::table('product')
            ->whereIn('product_id', $ids)
            ->pluck('gst_percent', 'product_id');

        $resolved = [];
        foreach ($ids as $id) {
            $components = $byProduct[$id] ?? [];
            $sgst = $components['SGST'] ?? 0.0;
            $cgst = $components['CGST'] ?? 0.0;
            $cess = $components['CESS'] ?? 0.0;
            $igst = $components['IGST'] ?? 0.0;

            // Intra-state sale (SGST + CGST) is the only shape `orders_item.pinfo`
            // can express — it carries sgst_percent/cgst_percent and no igst
            // field. IGST is therefore only used to reconstruct the split when a
            // product has an IGST row but no SGST/CGST rows.
            if ($sgst <= 0 && $cgst <= 0 && $igst > 0) {
                $sgst = round($igst / 2, 2);
                $cgst = round($igst / 2, 2);
            }

            if ($sgst <= 0 && $cgst <= 0 && $cess <= 0) {
                // No usable product_taxes rows (2 live products) — fall back to
                // the legacy column rather than booking zero tax.
                $legacy = (float) ($fallback[$id] ?? 0);
                $sgst = round($legacy / 2, 2);
                $cgst = round($legacy / 2, 2);
            }

            $resolved[$id] = [
                'tax_percent'  => round($sgst + $cgst + $cess, 2),
                'sgst_percent' => $sgst,
                'cgst_percent' => $cgst,
                'igst_percent' => $igst,
                'cess_percent' => $cess,
            ];
        }

        return $resolved;
    }

    /** @return array{tax_percent: float, sgst_percent: float, cgst_percent: float, igst_percent: float, cess_percent: float} */
    public static function forProduct(int|string $productId): array
    {
        return self::forProducts([$productId])[(int) $productId] ?? [
            'tax_percent'  => 0.0,
            'sgst_percent' => 0.0,
            'cgst_percent' => 0.0,
            'igst_percent' => 0.0,
            'cess_percent' => 0.0,
        ];
    }
}

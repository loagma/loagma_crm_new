<?php

namespace App\Support;

/**
 * Stock maths used by the order flow (ORDER_LIFECYCLE doc §1 step 7):
 *   required stock = quantity × extractFirstNumber(pack.ps) × unit_factors[pack.pu]
 *
 * The consumer app keeps the real `unit_factors` map in
 * loagma.com/framework/config.php (lines 197-219), which is not part of this
 * repository. This map is INFERRED from the pack units in use
 * (vendor_products.packs[*].pu: kg, gm, ml, nos, pcs, pack…) and must be
 * confirmed against that config file before relying on it for stock.
 */
class UnitFactors
{
    /** Unit text (normalised) → multiplier into the pack's stock unit. */
    private const MAP = [
        'kg' => 1, 'kgs' => 1, 'kilo' => 1, 'kilogram' => 1,
        'gm' => 0.001, 'gms' => 0.001, 'g' => 0.001, 'gram' => 0.001, 'grams' => 0.001,
        'l' => 1, 'ltr' => 1, 'ltrs' => 1, 'litre' => 1, 'liter' => 1,
        'ml' => 0.001,
        'nos' => 1, 'no' => 1, 'pcs' => 1, 'pc' => 1, 'piece' => 1, 'pieces' => 1,
        'pack' => 1, 'packs' => 1, 'unit' => 1, 'units' => 1, 'box' => 1, 'dozen' => 12,
    ];

    /**
     * Multiplier for a pack unit (`pu`). In real packs `pu` often carries a
     * size too ("500 Gms.", "5 Kg", "0.2 KG", "250ml" — 2% of packs; the rest
     * are "nos"), so the factor is that number × the base unit:
     * "500 Gms." → 500 × 0.001 = 0.5, "5 Kg" → 5, "nos" → 1. Unknown → 1.
     */
    public static function factor(?string $unit): float
    {
        $raw  = strtolower(trim((string) $unit));
        $base = (float) (self::MAP[preg_replace('/[^a-z]/', '', $raw)] ?? 1);
        $size = preg_match('/\d+(?:\.\d+)?/', $raw, $m) ? (float) $m[0] : 1.0;
        return $size > 0 ? $size * $base : $base;
    }

    /** First number in a pack size string: "5pack * 100 gm" → 5, "1 kg" → 1, "" → 1. */
    public static function extractFirstNumber(?string $packSize): float
    {
        return preg_match('/\d+(?:\.\d+)?/', (string) $packSize, $m) ? (float) $m[0] : 1.0;
    }

    /** Stock needed to sell `$quantity` of a pack. */
    public static function stockFor(int|float $quantity, array $pack): float
    {
        return (float) $quantity * self::extractFirstNumber($pack['ps'] ?? '') * self::factor($pack['pu'] ?? '');
    }
}

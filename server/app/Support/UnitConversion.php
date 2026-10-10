<?php

namespace App\Support;

use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Stock conversion with `units_master` as the source of truth.
 *
 * Every pack in vendor_products.packs carries `pui` = units_master.unit_id.
 * The product's stock (`stk`, shared by all its packs) is kept in
 * product.stock_uom, another units_master id. units_master.conversion_rate is
 * relative to a base unit (KG, LTR, NOS…), so one pack holds
 *
 *   extractFirstNumber(ps) × rate(pui) ÷ rate(stock_uom)
 *
 * stock units — the order lifecycle doc's
 * `qty × extractFirstNumber(ps) × unit_factors[pu]`, with the factor read
 * from units_master by id instead of guessed from the `pu` text. For KG / NOS
 * stock (rate 1) it is exactly the doc's formula.
 *
 * A pack whose unit can't be trusted (no pui, unknown unit, unit of a
 * different kind than the stock, or a size that disagrees with its own text
 * such as "1 Pack of 5 Kg" with unit KG) is reported by problem() and is not
 * sold, so stock is never deducted by a wrong amount.
 */
class UnitConversion
{
    /** @var array<int, object>|null */
    private static ?array $units = null;

    /** units_master rows keyed by unit_id (loaded once per request). */
    public static function units(): array
    {
        if (self::$units === null) {
            $cols = ['unit_id', 'unit_name', 'conversion_rate', 'is_active'];
            if (Schema::hasColumn('units_master', 'dimension')) {
                $cols[] = 'dimension';
            }
            self::$units = DB::table('units_master')->get($cols)->keyBy('unit_id')->all();
        }
        return self::$units;
    }

    /** Forget the cached units (tests / after units_master changes). */
    public static function flush(): void
    {
        self::$units = null;
    }

    /** Use these units instead of reading units_master (unit tests). */
    public static function useUnits(array $rows): void
    {
        self::$units = [];
        foreach ($rows as $r) {
            $r = (object) $r;
            self::$units[(int) $r->unit_id] = $r;
        }
    }

    public static function unit($unitId): ?object
    {
        return is_numeric($unitId) ? (self::units()[(int) $unitId] ?? null) : null;
    }

    public static function unitName($unitId): ?string
    {
        return self::unit($unitId)?->unit_name;
    }

    /** units_master.conversion_rate for a unit id, or null when unknown. */
    public static function rate($unitId): ?float
    {
        $u = self::unit($unitId);
        return $u ? (float) $u->conversion_rate : null;
    }

    /**
     * Kind of unit: MASS, VOLUME, LENGTH or COUNT. Uses the dimension column
     * where the table has it (dev); otherwise read from the unit name (prod's
     * units_master has no dimension column).
     */
    public static function dimension($unitId): ?string
    {
        $u = self::unit($unitId);
        if (!$u) return null;
        if (!empty($u->dimension)) return strtoupper((string) $u->dimension);
        $base = preg_replace('/[^a-z]/', '', strtolower((string) $u->unit_name));
        return match (true) {
            in_array($base, ['kg', 'kgs', 'gm', 'gms', 'g', 'gram', 'grams'], true)          => 'MASS',
            in_array($base, ['ltr', 'ltre', 'ltrs', 'l', 'litre', 'liter', 'ml'], true)     => 'VOLUME',
            in_array($base, ['mtr', 'cm', 'm'], true)                                        => 'LENGTH',
            default                                                                          => 'COUNT',
        };
    }

    /** First number in a pack size string: "4 Pack of 500 gm" → 4, "1 Tin" → 1, "" → 1. */
    public static function extractFirstNumber(?string $packSize): float
    {
        return preg_match('/\d+(?:\.\d+)?/', (string) $packSize, $m) ? (float) $m[0] : 1.0;
    }

    /** Stock units one pack holds, or null when the pack's unit isn't usable. */
    public static function basePerPack(array $pack, $stockUom): ?float
    {
        $rate  = self::rate($pack['pui'] ?? null);
        $stock = is_numeric($stockUom) ? self::rate($stockUom) : 1.0; // no stock unit set → base units
        if ($rate === null || $rate <= 0 || $stock === null || $stock <= 0) return null;
        return self::extractFirstNumber($pack['ps'] ?? '') * $rate / $stock;
    }

    /** Stock needed to sell `$qty` of a pack (stock units). */
    public static function need(int|float $qty, array $pack, $stockUom): ?float
    {
        $per = self::basePerPack($pack, $stockUom);
        return $per === null ? null : (float) $qty * $per;
    }

    /**
     * Why a pack can't be sold with a trustworthy stock conversion, or null if
     * it is fine. The message is shown to staff and written in the fix list.
     */
    public static function problem(array $pack, $stockUom): ?string
    {
        $pui = $pack['pui'] ?? null;
        if ($pui === null || $pui === '') return 'unit (pui) not set on the pack';
        $unit = self::unit($pui);
        if (!$unit) return "unit id $pui is not in units_master";
        if ((int) $unit->is_active !== 1) return "unit {$unit->unit_name} is inactive in units_master";
        if ((float) $unit->conversion_rate <= 0) return "unit {$unit->unit_name} has no conversion rate";

        if (is_numeric($stockUom)) {
            if (!self::unit($stockUom)) return "product stock unit id $stockUom is not in units_master";
            $packDim  = self::dimension($pui);
            $stockDim = self::dimension($stockUom);
            if ($packDim !== $stockDim) {
                return "pack unit {$unit->unit_name} ($packDim) does not match product stock unit "
                    . self::unitName($stockUom) . " ($stockDim)";
            }
        }

        $per = self::basePerPack($pack, $stockUom);
        if ($per === null || $per <= 0) return 'pack size gives zero stock per pack';

        // The size written on the pack ("1 Pack of 5 Kg", "500 gm") must agree
        // with the conversion, or a sale would deduct the wrong amount.
        $written = self::writtenBase($pack);
        if ($written !== null && in_array(self::dimension($pui), ['MASS', 'VOLUME'], true)) {
            $stockRate = is_numeric($stockUom) ? (float) self::rate($stockUom) : 1.0;
            $writtenInStock = $written / $stockRate;
            if (abs($writtenInStock - $per) > max(1e-6, 0.001 * $writtenInStock)) {
                return 'pack text says ' . self::fmt($written) . ' ' . (self::dimension($pui) === 'MASS' ? 'kg' : 'ltr')
                    . ' but ps × unit gives ' . self::fmt($per * $stockRate);
            }
        }
        return null;
    }

    /**
     * Size of one pack written in its text, in base units (kg / ltr):
     * "1 Pack of 5 Kg @ 855/-" → 5, "1 pack 500 g" → 0.5, "4 Pack of 500 gm" → 2,
     * "10 Kg x 190/-" → 10. Null when the text names no weight/volume.
     */
    public static function writtenBase(array $pack): ?float
    {
        $text = strtolower(trim((string) (($pack['tx'] ?? '') !== '' ? $pack['tx'] : ($pack['ps'] ?? ''))));
        if (!preg_match('/(\d+(?:\.\d+)?)\s*(kgs?|kilos?|kilograms?|gms?|grams?|g|ltrs?|litres?|liters?|l|ml)\b/', $text, $m)) {
            return null;
        }
        $value = (float) $m[1];
        $small = in_array($m[2], ['gm', 'gms', 'gram', 'grams', 'g', 'ml'], true);
        $size  = $value * ($small ? 0.001 : 1);
        // a leading pack count ("4 Pack of 500 gm") multiplies the size
        if (preg_match('/^(\d+)\s*(?:packs?|pkts?|bags?|pcs|nos|x|\*)\b/', $text, $c) && (float) $c[1] !== $value) {
            $size *= (int) $c[1];
        }
        return $size;
    }

    private static function fmt(float $v): string
    {
        return rtrim(rtrim(number_format($v, 3, '.', ''), '0'), '.');
    }
}

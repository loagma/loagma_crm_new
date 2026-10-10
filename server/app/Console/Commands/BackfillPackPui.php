<?php

namespace App\Console\Commands;

use App\Support\UnitConversion;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;

/**
 * Writes `pui` (units_master.unit_id) into every vendor_products pack that
 * doesn't have one yet, by matching the pack's `pu` text to a unit name
 * ("500 Gms." → "500 GM", "1 kg" → "KG", "nos" → "NOS").
 *
 * A pack only gets a pui when the conversion is trustworthy
 * (UnitConversion::problem() finds nothing); every other pack is left as is
 * and listed with the reason in storage/app/pui_backfill_report.csv — the fix
 * list for whoever maintains packs in the PMS. Packs without a pui can't be
 * ordered from the CRM.
 *
 * Dry run by default; --apply writes. Only the `pui` key is added — nothing
 * else in the pack changes. Safe to re-run.
 */
class BackfillPackPui extends Command
{
    protected $signature = 'packs:backfill-pui {--apply : write pui into vendor_products.packs (default is a dry run)}';

    protected $description = 'Fill the pui (units_master id) key on vendor_products packs from their pu text';

    /** canonical unit word for spelling variants seen in pack `pu` */
    private const WORDS = [
        'kgs' => 'kg', 'kilo' => 'kg', 'kilos' => 'kg', 'kilogram' => 'kg', 'kilograms' => 'kg',
        'gms' => 'gm', 'g' => 'gm', 'gram' => 'gm', 'grams' => 'gm',
        'ltrs' => 'ltr', 'l' => 'ltr', 'litre' => 'ltr', 'liter' => 'ltr', 'litres' => 'ltr',
        'no' => 'nos', 'pc' => 'pcs', 'piece' => 'pcs', 'pieces' => 'pcs',
    ];

    public function handle(): int
    {
        $apply = (bool) $this->option('apply');
        UnitConversion::flush();

        // canonical unit name → unit_id (active units only)
        $index = [];
        foreach (UnitConversion::units() as $u) {
            if ((int) $u->is_active !== 1) continue;
            $key = $this->canon((string) $u->unit_name);
            if ($key !== null) $index[$key] ??= (int) $u->unit_id;
        }

        $report = [];
        $counts = ['packs' => 0, 'already_ok' => 0, 'already_bad' => 0, 'set' => 0, 'unmapped' => 0, 'bad' => 0];
        $toWrite = []; // vp id => [pack id => unit id]

        $rows = DB::table('vendor_products as vp')->leftJoin('product as p', 'p.product_id', '=', 'vp.product_id')
            ->orderBy('vp.id')->get(['vp.id', 'vp.product_id', 'vp.admin_vendor_id', 'vp.packs', 'p.name', 'p.stock_uom']);

        foreach ($rows as $r) {
            foreach ((json_decode((string) $r->packs, true) ?: []) as $packId => $pack) {
                if (!is_array($pack)) continue;
                $counts['packs']++;
                $line = [
                    'vendor_product_id' => $r->id, 'vendor' => $r->admin_vendor_id, 'product_id' => $r->product_id,
                    'product' => $r->name, 'pack_id' => $packId, 'tx' => $pack['tx'] ?? '', 'ps' => $pack['ps'] ?? '',
                    'pu' => $pack['pu'] ?? '', 'stock_unit' => UnitConversion::unitName($r->stock_uom) ?? (string) $r->stock_uom,
                    'pui' => $pack['pui'] ?? '', 'unit' => '', 'status' => '', 'reason' => '',
                ];

                if (isset($pack['pui']) && $pack['pui'] !== '') {
                    $why = UnitConversion::problem($pack, $r->stock_uom);
                    $line['unit'] = UnitConversion::unitName($pack['pui']) ?? '';
                    $line['status'] = $why ? 'already_set_bad' : 'already_set_ok';
                    $line['reason'] = $why ?? '';
                    $counts[$why ? 'already_bad' : 'already_ok']++;
                    $report[] = $line;
                    continue;
                }

                $unitId = $this->match((string) ($pack['pu'] ?? ''), $index);
                if ($unitId === null) {
                    $line['status'] = 'unmapped';
                    $line['reason'] = 'pu "' . ($pack['pu'] ?? '') . '" matches no active unit in units_master';
                    $counts['unmapped']++;
                    $report[] = $line;
                    continue;
                }

                $line['unit'] = UnitConversion::unitName($unitId);
                $why = UnitConversion::problem($pack + ['pui' => $unitId], $r->stock_uom);

                // A count unit (nos / PCS) on a product whose stock is by weight
                // or volume: take the weight unit the pack's own text gives
                // ("10 Kg x 495" → KG, "1 pack 250 g" → 250 GM) when it
                // reproduces that size exactly. Marked for review in the report.
                if ($why && UnitConversion::dimension($unitId) === 'COUNT'
                    && in_array(UnitConversion::dimension($r->stock_uom), ['MASS', 'VOLUME'], true)
                    && ($fromText = $this->unitFromText($pack, $r->stock_uom)) !== null) {
                    $line['unit']   = UnitConversion::unitName($fromText);
                    $line['status'] = $apply ? 'set_from_text' : 'would_set_from_text';
                    $line['reason'] = 'pu "' . ($pack['pu'] ?? '') . '" is a count unit on ' . UnitConversion::unitName($r->stock_uom)
                        . ' stock; unit taken from the pack text — please review';
                    $line['pui']    = $fromText;
                    $counts['set_from_text'] = ($counts['set_from_text'] ?? 0) + 1;
                    $toWrite[$r->id][$packId] = $fromText;
                    $report[] = $line;
                    continue;
                }

                if ($why) {
                    $line['status'] = 'bad';
                    $line['reason'] = $why;
                    $counts['bad']++;
                } else {
                    $line['status'] = $apply ? 'set' : 'would_set';
                    $line['pui'] = $unitId;
                    $counts['set']++;
                    $toWrite[$r->id][$packId] = $unitId;
                }
                $report[] = $line;
            }
        }

        if ($apply) {
            foreach ($toWrite as $vpId => $set) {
                DB::transaction(function () use ($vpId, $set) {
                    $packs = json_decode((string) DB::table('vendor_products')->where('id', $vpId)->lockForUpdate()->value('packs'), true) ?: [];
                    $changed = false;
                    foreach ($set as $packId => $unitId) {
                        if (isset($packs[$packId]) && is_array($packs[$packId]) && empty($packs[$packId]['pui'])) {
                            $packs[$packId]['pui'] = $unitId;
                            $changed = true;
                        }
                    }
                    if ($changed) {
                        DB::table('vendor_products')->where('id', $vpId)->update(['packs' => json_encode($packs)]);
                    }
                });
            }
        }

        $file = storage_path('app/pui_backfill_report.csv');
        $fh = fopen($file, 'w');
        fputcsv($fh, array_keys($report[0] ?? ['vendor_product_id' => '']));
        foreach ($report as $line) fputcsv($fh, $line);
        fclose($fh);

        $this->info(($apply ? 'APPLIED' : 'DRY RUN') . ' — ' . json_encode($counts));
        $this->line("Report: $file");
        return self::SUCCESS;
    }

    /** "500 Gms." → "500gm", "1 kg" → "kg", "NOS" → "nos", "pack" → "pack" (null if empty). */
    private function canon(string $text): ?string
    {
        // drop dots that aren't decimal points ("500 Gms." → "500 Gms", "0.2 KG" stays)
        $t = strtolower(trim(preg_replace('/(?<!\d)\.|\.(?!\d)/', ' ', $text)));
        if (!preg_match('/^(\d+(?:\.\d+)?)?\s*([a-z]+)$/', preg_replace('/\s+/', ' ', $t), $m)) return null;
        $word = self::WORDS[$m[2]] ?? $m[2];
        $num  = $m[1] ?? '';
        if ($num !== '' && (float) $num == 1.0) $num = ''; // "1 kg" is the KG unit itself
        if (str_contains($num, '.')) $num = rtrim(rtrim($num, '0'), '.'); // "0.50" → "0.5"
        return $num . $word;
    }

    /**
     * The active unit (same kind as the stock) for which
     * extractFirstNumber(ps) × rate equals the size written in the pack text,
     * or null. Smallest unit id wins when several fit; problem() must then pass.
     */
    private function unitFromText(array $pack, $stockUom): ?int
    {
        $written = UnitConversion::writtenBase($pack);
        $first   = UnitConversion::extractFirstNumber($pack['ps'] ?? '');
        if ($written === null || $written <= 0 || $first <= 0) return null;
        $target = $written / $first;
        $dim    = UnitConversion::dimension($stockUom);
        foreach (UnitConversion::units() as $u) { // keyed by unit_id; iterate in id order
            if ((int) $u->is_active !== 1 || UnitConversion::dimension($u->unit_id) !== $dim) continue;
            if (abs((float) $u->conversion_rate - $target) > 1e-9 * max(1, $target)) continue;
            if (UnitConversion::problem($pack + ['pui' => (int) $u->unit_id], $stockUom) === null) {
                return (int) $u->unit_id;
            }
        }
        return null;
    }

    private function match(string $pu, array $index): ?int
    {
        $key = $this->canon($pu);
        return $key === null ? null : ($index[$key] ?? null);
    }
}

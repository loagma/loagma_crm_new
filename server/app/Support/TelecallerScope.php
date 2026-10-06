<?php

namespace App\Support;

use App\Models\Area;
use App\Models\AreaAssign;

/**
 * The area-based scope of a telecaller: the areas assigned to them in
 * area_assign_crm (keyed by mobile cast to int) and every pincode those areas
 * contain. Shared by TelecallerController and TelecallerAllocationService.
 */
class TelecallerScope
{
    /** @return array{0: int[], 1: string[]} [areaIds, pincodes] */
    public static function areaScope(string $mobile): array
    {
        $assign = AreaAssign::where('employee_id', (string) $mobile)->first();
        $areaIds = $assign ? array_values(array_filter(array_map('intval', $assign->area_ids ?? []))) : [];

        $pincodes = [];
        if (!empty($areaIds)) {
            foreach (Area::whereIn('id', $areaIds)->get() as $area) {
                // Some area_crm rows store pincodes with stray spaces ("482001 ").
                foreach ((array) ($area->pincodes ?? []) as $p) {
                    $p = trim((string) $p);
                    if ($p !== '') {
                        $pincodes[] = $p;
                    }
                }
            }
        }
        return [$areaIds, array_values(array_unique($pincodes))];
    }
}

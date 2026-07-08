<?php

namespace App\Support;

use Carbon\Carbon;

/**
 * Route distance over a chronologically ordered set of GPS pings.
 *
 * Gap rule (honesty): consecutive pings more than GAP_MINUTES apart mean
 * tracking was interrupted (airplane mode, killed service, dead battery).
 * The straight line across such a gap was not necessarily walked, so it is
 * EXCLUDED from the total and surfaced as has_gaps so the UI can caption
 * "actual distance may be higher".
 *
 * Timezone: pings carry app-timezone Carbon instances (model cast) — see the
 * convention doc-comment atop TrackingController.
 */
class RouteDistance
{
    // Same threshold as the was_interrupted detection in TrackingController.
    public const GAP_MINUTES = 5;

    /**
     * @param iterable $pings ordered by recorded_at ascending; each item
     *                        exposes lat, lng and recorded_at.
     * @return array{distance_km: float, has_gaps: bool}
     */
    public static function stats(iterable $pings): array
    {
        $km      = 0.0;
        $hasGaps = false;
        $prev    = null;

        foreach ($pings as $p) {
            if ($prev !== null) {
                $gapSeconds = abs(
                    Carbon::parse($p->recorded_at)->diffInSeconds(Carbon::parse($prev->recorded_at))
                );
                if ($gapSeconds > self::GAP_MINUTES * 60) {
                    $hasGaps = true; // interrupted — do not count the jump
                } else {
                    $km += self::haversineKm(
                        (float) $prev->lat, (float) $prev->lng,
                        (float) $p->lat, (float) $p->lng
                    );
                }
            }
            $prev = $p;
        }

        return ['distance_km' => round($km, 3), 'has_gaps' => $hasGaps];
    }

    public static function haversineKm(float $lat1, float $lng1, float $lat2, float $lng2): float
    {
        $earthRadiusKm = 6371;
        $dLat = deg2rad($lat2 - $lat1);
        $dLng = deg2rad($lng2 - $lng1);
        $a = sin($dLat / 2) ** 2
            + cos(deg2rad($lat1)) * cos(deg2rad($lat2)) * sin($dLng / 2) ** 2;
        return $earthRadiusKm * 2 * atan2(sqrt($a), sqrt(1 - $a));
    }
}

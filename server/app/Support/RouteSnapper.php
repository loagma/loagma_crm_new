<?php

namespace App\Support;

use Carbon\Carbon;
use Illuminate\Support\Facades\Http;
use Throwable;

/**
 * Optional OSRM /match road-snapping for the route-history display geometry
 * of CLOSED days (TrackingController::route). Live routes are never snapped.
 *
 * Cosmetic only: the snapped line is what the history map DRAWS; every
 * stored number (total_distance_km etc.) stays computed from RAW points —
 * see the note in RouteDistance.
 *
 * Honesty rule carried over from RouteDistance: each contiguous run (split
 * at the same >GAP_MINUTES silence) is matched SEPARATELY. OSRM is never
 * asked to bridge an interruption, so dashed gap connectors in the UI stay
 * raw straight lines.
 *
 * Failure is always graceful: disabled / unreachable / timeout / bad
 * response → null, and the caller serves raw points exactly as before.
 */
class RouteSnapper
{
    // Bound the work per run: a long run is first thinned evenly to at most
    // this many chunks' worth of points, then matched chunk by chunk with a
    // 1-point overlap and stitched. Map-matching doesn't need every ~20 m
    // point — the radiuses tell OSRM how loosely to interpret each one.
    private const MAX_CHUNKS_PER_RUN = 4;

    /**
     * @param iterable $pings ordered by recorded_at ascending; each item
     *                        exposes lat, lng, accuracy and recorded_at.
     * @return array|null one entry per contiguous run: [[lat, lng], ...] or
     *                    null where OSRM could not match that run. Null
     *                    overall when snapping is off or nothing matched.
     */
    public static function snap(iterable $pings): ?array
    {
        try {
            $base = rtrim((string) config('tracking.osrm_url'), '/');
            if ($base === '') {
                return null;
            }

            $runs = self::splitAtGaps($pings);
            if (empty($runs)) {
                return null;
            }

            $segments = [];
            $matchedAny = false;
            foreach ($runs as $run) {
                $geometry = count($run) >= 2 ? self::matchRun($base, $run) : null;
                $segments[] = $geometry;
                if ($geometry !== null) {
                    $matchedAny = true;
                }
            }

            return $matchedAny ? $segments : null;
        } catch (Throwable) {
            return null; // never fail the request over snapping
        }
    }

    /**
     * Same split rule as RouteDistance so the client's raw segmentation and
     * this array line up 1:1 (single-point runs stay as null-geometry slots).
     */
    private static function splitAtGaps(iterable $pings): array
    {
        $runs = [];
        $current = [];
        $prevAt = null;
        $prevTs = null;

        foreach ($pings as $p) {
            $at = Carbon::parse($p->recorded_at);
            if ($prevAt !== null
                && abs($at->diffInSeconds($prevAt)) > RouteDistance::GAP_MINUTES * 60
                && !empty($current)) {
                $runs[] = $current;
                $current = [];
                $prevTs = null;
            }

            // OSRM requires strictly increasing timestamps.
            $ts = $at->getTimestamp();
            if ($prevTs !== null && $ts <= $prevTs) {
                $ts = $prevTs + 1;
            }

            $current[] = [
                'lat'    => (float) $p->lat,
                'lng'    => (float) $p->lng,
                'ts'     => $ts,
                // Ingest already drops accuracy >50m; unknown → assume 15m.
                'radius' => (int) min(max((float) ($p->accuracy ?? 15), 5), 50),
            ];
            $prevAt = $at;
            $prevTs = $ts;
        }
        if (!empty($current)) {
            $runs[] = $current;
        }

        return $runs;
    }

    /** Match one contiguous run, chunked with a 1-point overlap. */
    private static function matchRun(string $base, array $run): ?array
    {
        $chunkSize = max(2, (int) config('tracking.osrm_chunk', 10));
        $maxPoints = ($chunkSize - 1) * self::MAX_CHUNKS_PER_RUN + 1;
        if (count($run) > $maxPoints) {
            $run = self::thinEvenly($run, $maxPoints);
        }

        $geometry = [];
        for ($i = 0; $i < count($run) - 1; $i += $chunkSize - 1) {
            $chunk = array_slice($run, $i, $chunkSize);
            if (count($chunk) < 2) {
                break; // lone trailing point — already covered by the overlap
            }
            $part = self::matchChunk($base, $chunk);
            if ($part === null) {
                return null; // one failed chunk → whole run falls back raw
            }
            $geometry = array_merge($geometry, $part);
        }

        return count($geometry) >= 2 ? $geometry : null;
    }

    /** Evenly spaced subset keeping the first and last points. */
    private static function thinEvenly(array $run, int $target): array
    {
        $last = count($run) - 1;
        $out = [];
        for ($i = 0; $i < $target; $i++) {
            $out[] = $run[(int) round($i * $last / ($target - 1))];
        }

        return $out;
    }

    private static function matchChunk(string $base, array $chunk): ?array
    {
        $profile = (string) config('tracking.osrm_profile', 'driving');
        $coords = implode(';', array_map(
            fn ($p) => sprintf('%.6F,%.6F', $p['lng'], $p['lat']),
            $chunk
        ));

        $http = Http::connectTimeout(2)
            ->timeout((int) config('tracking.osrm_timeout', 3));
        if ($ca = config('tracking.osrm_ca')) {
            $http = $http->withOptions(['verify' => $ca]);
        }

        $res = $http->get("{$base}/match/v1/{$profile}/{$coords}", [
                'overview'   => 'full',
                'geometries' => 'geojson',
                'timestamps' => implode(';', array_column($chunk, 'ts')),
                'radiuses'   => implode(';', array_column($chunk, 'radius')),
                // We already split at gaps ourselves — one trace per chunk.
                'gaps'       => 'ignore',
                // Collapse stationary GPS clusters before matching.
                'tidy'       => 'true',
            ]);

        if (!$res->ok() || $res->json('code') !== 'Ok') {
            return null;
        }

        $line = [];
        foreach ($res->json('matchings', []) as $matching) {
            foreach (($matching['geometry']['coordinates'] ?? []) as $c) {
                $line[] = [(float) $c[1], (float) $c[0]]; // GeoJSON is [lng, lat]
            }
        }

        return count($line) >= 2 ? $line : null;
    }
}

<?php

namespace App\Support;

/**
 * Orders points by real geographic proximity — never by their identifiers.
 *
 * Used by the telecaller allocation to turn a set of pincodes into a walking
 * order: nearby pincodes are grouped into internal clusters (single-linkage
 * within $clusterKm), clusters are chained nearest-first starting from the
 * outermost one, and pincodes inside each cluster are chained nearest-first
 * from the point where the previous cluster ended, then tidied with a 2-opt
 * pass. Points with no coordinates go last (sorted by key, flagged by caller).
 *
 * Pure: no DB access, so it is unit-testable in isolation.
 */
class GeoSequencer
{
    /**
     * @param array<string, array{0: float, 1: float}|null> $points key => [lat, lng] or null
     * @param array{0: float, 1: float}|null $from continue the walk from here
     *        (e.g. where an in-progress plan currently stands) instead of
     *        starting at the outermost cluster
     * @return array{sequence: string[], clusters: string[][], unlocated: string[]}
     */
    public static function sequence(array $points, float $clusterKm = 5.0, ?array $from = null): array
    {
        $located = [];
        $unlocated = [];
        foreach ($points as $key => $p) {
            $key = (string) $key;
            if ($p === null) {
                $unlocated[] = $key;
            } else {
                $located[$key] = [(float) $p[0], (float) $p[1]];
            }
        }
        sort($unlocated, SORT_STRING);

        if (empty($located)) {
            return ['sequence' => $unlocated, 'clusters' => [], 'unlocated' => $unlocated];
        }

        $clusters = self::cluster($located, $clusterKm);

        // Cluster centres, then chain clusters starting from the outermost one
        // (farthest from the overall centre) so the walk sweeps across the
        // region instead of starting in the middle and doubling back.
        $centres = [];
        foreach ($clusters as $i => $keys) {
            $centres[$i] = self::centroid(array_map(fn ($k) => $located[$k], $keys));
        }
        $overall = self::centroid(array_values($located));
        $start = $from === null ? self::farthestFrom($centres, $overall) : self::nearestTo($centres, $from);
        $clusterOrder = self::twoOpt(self::nearestChain($centres, $start), $centres);

        $sequence = [];
        $orderedClusters = [];
        $prev = $from;
        foreach ($clusterOrder as $ci) {
            $members = [];
            foreach ($clusters[$ci] as $k) {
                $members[$k] = $located[$k];
            }
            // Enter each cluster at the member nearest to where we left the
            // previous one; the first cluster starts at its outermost member.
            $entry = $prev === null
                ? self::farthestFrom($members, $overall)
                : self::nearestTo($members, $prev);
            $chain = self::twoOpt(self::nearestChain($members, $entry), $members);
            $orderedClusters[] = $chain;
            foreach ($chain as $k) {
                $sequence[] = (string) $k;
            }
            $prev = $members[end($chain)];
        }

        return [
            'sequence'  => array_merge($sequence, $unlocated),
            'clusters'  => $orderedClusters,
            'unlocated' => $unlocated,
        ];
    }

    public static function km(array $a, array $b): float
    {
        return RouteDistance::haversineKm($a[0], $a[1], $b[0], $b[1]);
    }

    /** Single-linkage clustering via union-find; deterministic member order. */
    private static function cluster(array $located, float $thresholdKm): array
    {
        $keys = array_keys($located);
        $parent = array_combine($keys, $keys);
        $find = function ($x) use (&$parent, &$find) {
            while ($parent[$x] !== $x) {
                $parent[$x] = $parent[$parent[$x]];
                $x = $parent[$x];
            }
            return $x;
        };
        $n = count($keys);
        for ($i = 0; $i < $n; $i++) {
            for ($j = $i + 1; $j < $n; $j++) {
                if (self::km($located[$keys[$i]], $located[$keys[$j]]) <= $thresholdKm) {
                    $parent[$find($keys[$i])] = $find($keys[$j]);
                }
            }
        }
        $groups = [];
        foreach ($keys as $k) {
            $groups[(string) $find($k)][] = $k;
        }
        return array_values($groups);
    }

    private static function centroid(array $pts): array
    {
        $lat = 0.0;
        $lng = 0.0;
        foreach ($pts as $p) {
            $lat += $p[0];
            $lng += $p[1];
        }
        return [$lat / count($pts), $lng / count($pts)];
    }

    private static function farthestFrom(array $pts, array $ref)
    {
        $best = null;
        $bestD = -1.0;
        foreach ($pts as $k => $p) {
            $d = self::km($p, $ref);
            if ($d > $bestD) {
                $bestD = $d;
                $best = $k;
            }
        }
        return $best;
    }

    private static function nearestTo(array $pts, array $ref)
    {
        $best = null;
        $bestD = INF;
        foreach ($pts as $k => $p) {
            $d = self::km($p, $ref);
            if ($d < $bestD) {
                $bestD = $d;
                $best = $k;
            }
        }
        return $best;
    }

    private static function nearestChain(array $pts, $start): array
    {
        $order = [$start];
        $left = $pts;
        unset($left[$start]);
        $cur = $pts[$start];
        while (!empty($left)) {
            $next = self::nearestTo($left, $cur);
            $order[] = $next;
            $cur = $left[$next];
            unset($left[$next]);
        }
        return $order;
    }

    /** 2-opt improvement of an open path with a fixed first element. */
    private static function twoOpt(array $order, array $pts): array
    {
        $n = count($order);
        if ($n < 4) {
            return $order;
        }
        $improved = true;
        $guard = 0;
        while ($improved && $guard++ < 50) {
            $improved = false;
            for ($i = 1; $i < $n - 1; $i++) {
                for ($j = $i + 1; $j < $n; $j++) {
                    $a = $pts[$order[$i - 1]];
                    $b = $pts[$order[$i]];
                    $c = $pts[$order[$j]];
                    $before = self::km($a, $b);
                    $after = self::km($a, $c);
                    if ($j + 1 < $n) {
                        $d = $pts[$order[$j + 1]];
                        $before += self::km($c, $d);
                        $after += self::km($b, $d);
                    }
                    if ($after + 1e-9 < $before) {
                        $order = array_merge(
                            array_slice($order, 0, $i),
                            array_reverse(array_slice($order, $i, $j - $i + 1)),
                            array_slice($order, $j + 1)
                        );
                        $improved = true;
                    }
                }
            }
        }
        return $order;
    }
}

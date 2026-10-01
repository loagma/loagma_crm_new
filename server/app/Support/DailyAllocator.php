<?php

namespace App\Support;

/**
 * The capacity rule of the telecaller allocation, kept separate from the
 * geography rule (GeoSequencer decides *where next*, this decides *how many
 * today*). Given the queue already in geographic order, a day takes the first
 * $capacity pending entries — no per-pincode quota, so a day can be 52+48,
 * 75+25 or 20+30+50 depending on where the previous day stopped.
 */
class DailyAllocator
{
    /**
     * @param array $orderedPending pending queue entries, already in (pincode_rank, account_rank) order
     * @return array the entries allocated today
     */
    public static function take(array $orderedPending, int $capacity): array
    {
        return array_slice(array_values($orderedPending), 0, max(0, $capacity));
    }

    /**
     * Summarise a day's entries as pincode => count, in queue order.
     *
     * @param array<array{pincode: string}> $entries
     */
    public static function perPincode(array $entries): array
    {
        $out = [];
        foreach ($entries as $e) {
            $p = (string) $e['pincode'];
            $out[$p] = ($out[$p] ?? 0) + 1;
        }
        return $out;
    }
}

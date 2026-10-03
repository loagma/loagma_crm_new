<?php

namespace App\Support;

/**
 * The day-split rule of the telecaller allocation, kept separate from the
 * geography rule (GeoSequencer decides *which order*, this decides *which
 * day*). When a plan is created its accounts, already in geographic order,
 * are split once over the From–To range and each account keeps that date —
 * nothing is re-divided later. Pincodes are not split into quotas, so a day
 * can be 52+48, 75+25 or 20+30+50 depending on where the previous day ended.
 */
class DailyAllocator
{
    /**
     * Per-day counts for $n accounts over $startDate..$endDate (inclusive,
     * every calendar day counts), as even as possible with the larger days
     * first: 187 over 4 days → 47, 47, 47, 46.
     *
     * @return array<string, int> Y-m-d => count (days with 0 omitted)
     */
    public static function split(int $n, string $startDate, string $endDate): array
    {
        $days = self::daysInclusive($startDate, $endDate);
        if ($n <= 0 || $days <= 0) {
            return [];
        }
        $out = [];
        $day = new \DateTimeImmutable($startDate);
        $left = $n;
        for ($i = 0; $i < $days && $left > 0; $i++) {
            $take = (int) ceil($left / ($days - $i));
            $out[$day->format('Y-m-d')] = $take;
            $left -= $take;
            $day = $day->modify('+1 day');
        }
        return $out;
    }

    /**
     * The date for each position in an ordered list, following split().
     *
     * @return string[] Y-m-d per position
     */
    public static function datesFor(int $n, string $startDate, string $endDate): array
    {
        $dates = [];
        foreach (self::split($n, $startDate, $endDate) as $date => $count) {
            array_push($dates, ...array_fill(0, $count, $date));
        }
        return $dates;
    }

    public const WEEKDAYS = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

    /**
     * Dates in $startDate..$endDate (inclusive) that fall on one of $weekdays
     * (short names Mon..Sun). An empty $weekdays means every day.
     *
     * @param string[] $weekdays
     * @return string[] Y-m-d, ascending
     */
    public static function datesInRange(string $startDate, string $endDate, array $weekdays = []): array
    {
        $allowed = array_flip(array_map('ucfirst', array_map('strtolower', $weekdays)));
        $out = [];
        $day = new \DateTimeImmutable($startDate);
        $last = new \DateTimeImmutable($endDate);
        for (; $day <= $last; $day = $day->modify('+1 day')) {
            if (empty($allowed) || isset($allowed[$day->format('D')])) {
                $out[] = $day->format('Y-m-d');
            }
        }
        return $out;
    }

    /**
     * The days an Auto-Distribute spreads over: with $days ("N days" mode) the
     * first N matching dates from $startDate, otherwise the matching dates of
     * $startDate..$endDate.
     *
     * @param string[] $weekdays
     * @return string[] Y-m-d, ascending
     */
    public static function resolveDates(string $startDate, ?string $endDate, ?int $days, array $weekdays = []): array
    {
        if ($days !== null && $days > 0) {
            return self::datesByCount($startDate, $days, $weekdays);
        }
        return $endDate === null ? [] : self::datesInRange($startDate, $endDate, $weekdays);
    }

    /**
     * The first $count dates on or after $startDate that fall on one of
     * $weekdays (empty = every day): "N days" mode, where the To date is
     * derived instead of picked. Mon+Fri with $count = 8 gives 4 Mondays and
     * 4 Fridays. $startDate itself counts when it matches.
     *
     * @param string[] $weekdays
     * @return string[] Y-m-d, ascending
     */
    public static function datesByCount(string $startDate, int $count, array $weekdays = []): array
    {
        $allowed = array_flip(array_map('ucfirst', array_map('strtolower', $weekdays)));
        $out = [];
        $day = new \DateTimeImmutable($startDate);
        // At most one week of scanning per wanted date (a single weekday ticked).
        for ($scanned = 0; count($out) < $count && $scanned < $count * 7 + 7; $scanned++) {
            if (empty($allowed) || isset($allowed[$day->format('D')])) {
                $out[] = $day->format('Y-m-d');
            }
            $day = $day->modify('+1 day');
        }
        return $out;
    }

    /**
     * The date for each of $n ordered accounts, in consecutive even blocks
     * over $dates (larger blocks first): 31 over 6 dates → 6,5,5,5,5,5. Fewer
     * accounts than dates → one per date from the first.
     *
     * @param string[] $dates ascending Y-m-d
     * @return string[] Y-m-d per position
     */
    public static function blocksOver(int $n, array $dates): array
    {
        $dates = array_values($dates);
        $days = count($dates);
        if ($n <= 0 || $days === 0) {
            return [];
        }
        $out = [];
        $left = $n;
        foreach ($dates as $i => $date) {
            if ($left <= 0) {
                break;
            }
            $take = (int) ceil($left / ($days - $i));
            array_push($out, ...array_fill(0, $take, $date));
            $left -= $take;
        }
        return $out;
    }

    /** Calendar days from $from to $to, both included (Y-m-d). */
    public static function daysInclusive(string $from, string $to): int
    {
        return (int) (new \DateTimeImmutable($from))->diff(new \DateTimeImmutable($to))->format('%r%a') + 1;
    }

    /**
     * Summarise entries as pincode => count, in order.
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

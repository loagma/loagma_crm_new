<?php

namespace Tests\Unit;

use App\Support\DailyAllocator;
use App\Support\GeoSequencer;
use PHPUnit\Framework\TestCase;

class TelecallerAllocationTest extends TestCase
{
    /** Build an ordered queue: [pincode => count] in geographic order. */
    private function queue(array $counts): array
    {
        $q = [];
        foreach ($counts as $pincode => $n) {
            for ($i = 1; $i <= $n; $i++) {
                $q[] = ['pincode' => (string) $pincode, 'id' => "$pincode-$i"];
            }
        }
        return $q;
    }

    public function test_customers_split_once_over_date_range(): void
    {
        $this->assertSame(5, DailyAllocator::daysInclusive('2026-10-05', '2026-10-09'));

        // 250 customers, 5 Oct..9 Oct (5 days) → 50 per day.
        $this->assertSame(
            ['2026-10-05' => 50, '2026-10-06' => 50, '2026-10-07' => 50, '2026-10-08' => 50, '2026-10-09' => 50],
            DailyAllocator::split(250, '2026-10-05', '2026-10-09')
        );

        // Uneven: larger days first, nothing lost.
        $this->assertSame(
            ['2026-10-01' => 47, '2026-10-02' => 47, '2026-10-03' => 47, '2026-10-04' => 46],
            DailyAllocator::split(187, '2026-10-01', '2026-10-04')
        );

        // Fewer customers than days: one a day, later days empty.
        $this->assertSame(
            ['2026-10-01' => 1, '2026-10-02' => 1, '2026-10-03' => 1],
            DailyAllocator::split(3, '2026-10-01', '2026-10-05')
        );
    }

    public function test_weekday_filter_over_a_date_range(): void
    {
        // 6 Oct 2026 is a Tuesday. Mon/Wed/Fri over 6..19 Oct:
        $this->assertSame(
            ['2026-10-07', '2026-10-09', '2026-10-12', '2026-10-14', '2026-10-16'],
            DailyAllocator::datesInRange('2026-10-06', '2026-10-17', ['Mon', 'Wed', 'Fri'])
        );
        // Empty weekdays = all days; case-insensitive names.
        $this->assertCount(7, DailyAllocator::datesInRange('2026-10-05', '2026-10-11'));
        $this->assertSame(['2026-10-07'], DailyAllocator::datesInRange('2026-10-05', '2026-10-11', ['wed']));
        // No chosen weekday inside the range.
        $this->assertSame([], DailyAllocator::datesInRange('2026-10-05', '2026-10-06', ['Fri']));
    }

    public function test_n_days_mode_counts_only_chosen_weekdays(): void
    {
        // From Sat 3 Oct, Mon + Fri, N = 8 → 4 Mondays and 4 Fridays.
        $dates = DailyAllocator::datesByCount('2026-10-03', 8, ['Mon', 'Fri']);
        $this->assertSame([
            '2026-10-05', '2026-10-09', '2026-10-12', '2026-10-16',
            '2026-10-19', '2026-10-23', '2026-10-26', '2026-10-30',
        ], $dates);
        $names = array_count_values(array_map(fn ($d) => date('D', strtotime($d)), $dates));
        $this->assertSame(['Mon' => 4, 'Fri' => 4], $names);

        // The start date counts when it matches (Mon 5 Oct, N = 3).
        $this->assertSame(['2026-10-05', '2026-10-09', '2026-10-12'], DailyAllocator::datesByCount('2026-10-05', 3, ['Mon', 'Fri']));

        // All days (or none ticked) = N consecutive days.
        $this->assertSame(['2026-10-03', '2026-10-04', '2026-10-05'], DailyAllocator::datesByCount('2026-10-03', 3));
        $this->assertCount(8, DailyAllocator::datesByCount('2026-10-03', 8, DailyAllocator::WEEKDAYS));

        // A single weekday: one date per week.
        $this->assertSame(['2026-10-07', '2026-10-14', '2026-10-21'], DailyAllocator::datesByCount('2026-10-03', 3, ['Wed']));

        // resolveDates picks N-days mode when `days` is given, the range otherwise.
        $this->assertCount(8, DailyAllocator::resolveDates('2026-10-03', null, 8, ['Mon', 'Fri']));
        $this->assertSame(['2026-10-05', '2026-10-09'], DailyAllocator::resolveDates('2026-10-03', '2026-10-10', null, ['Mon', 'Fri']));
        $this->assertSame([], DailyAllocator::resolveDates('2026-10-03', null, null, ['Mon']));
    }

    public function test_blocks_over_selected_dates(): void
    {
        $dates = ['2026-10-07', '2026-10-09', '2026-10-12', '2026-10-14', '2026-10-16', '2026-10-19'];

        // 30 over 6 dates = 5 each, in order.
        $out = DailyAllocator::blocksOver(30, $dates);
        $this->assertCount(30, $out);
        $this->assertSame(array_fill(0, 5, '2026-10-07'), array_slice($out, 0, 5));
        $this->assertSame(array_fill(0, 5, '2026-10-19'), array_slice($out, 25));

        // 31 over 6: 6,5,5,5,5,5 (larger block first).
        $this->assertSame([6, 5, 5, 5, 5, 5], array_values(array_count_values(DailyAllocator::blocksOver(31, $dates))));

        // Fewer accounts than dates: one per date from the first.
        $this->assertSame(['2026-10-07', '2026-10-09'], DailyAllocator::blocksOver(2, $dates));

        // Nothing to place / nowhere to place.
        $this->assertSame([], DailyAllocator::blocksOver(0, $dates));
        $this->assertSame([], DailyAllocator::blocksOver(5, []));
    }

    public function test_dates_follow_queue_order_across_pincodes(): void
    {
        // Spec example, 5 pincodes over 4 days (335 → 84, 84, 84, 83): a day
        // fills in queue order and crosses pincode boundaries — no per-pincode quota.
        $queue = $this->queue(['482001' => 52, '482005' => 48, '482002' => 75, '482008' => 60, '482020' => 100]);
        $dates = DailyAllocator::datesFor(count($queue), '2026-10-01', '2026-10-04');
        $this->assertCount(335, $dates);

        $byDay = [];
        foreach ($queue as $i => $entry) {
            $byDay[$dates[$i]][] = $entry;
        }
        $this->assertSame([
            '2026-10-01' => ['482001' => 52, '482005' => 32],
            '2026-10-02' => ['482005' => 16, '482002' => 68],
            '2026-10-03' => ['482002' => 7, '482008' => 60, '482020' => 17],
            '2026-10-04' => ['482020' => 83],
        ], array_map([DailyAllocator::class, 'perPincode'], $byDay));
    }

    public function test_geography_not_pincode_number_decides_order(): void
    {
        // 482002 is numerically next to 482001 but ~33 km away; 482008 is
        // numerically far but ~2 km away. The walk must keep 001/005/008
        // together and put 002 at an end.
        $seq = GeoSequencer::sequence([
            '482001' => [23.000, 80.000],
            '482002' => [23.300, 80.000],
            '482005' => [23.010, 80.000],
            '482008' => [23.020, 80.000],
        ])['sequence'];

        $this->assertContains($seq, [
            ['482001', '482005', '482008', '482002'],
            ['482002', '482008', '482005', '482001'],
        ]);
    }

    public function test_clusters_are_walked_contiguously(): void
    {
        $out = GeoSequencer::sequence([
            '482020' => [23.215, 80.000],
            '482001' => [23.000, 80.000],
            '482008' => [23.200, 80.000],
            '482002' => [23.030, 80.000],
            '482005' => [23.010, 80.000],
        ], 5.0);

        $this->assertCount(2, $out['clusters']);
        $this->assertContains($out['sequence'], [
            ['482001', '482005', '482002', '482008', '482020'],
            ['482020', '482008', '482002', '482005', '482001'],
        ]);
    }

    public function test_walk_can_continue_from_current_position(): void
    {
        // Merge case: the plan currently stands near 482008, so the remaining
        // pincodes are walked onward from there, not from the outermost one.
        $seq = GeoSequencer::sequence([
            '482001' => [23.000, 80.000],
            '482020' => [23.215, 80.000],
            '482005' => [23.010, 80.000],
        ], 5.0, [23.200, 80.000])['sequence'];

        $this->assertSame(['482020', '482005', '482001'], $seq);
    }

    public function test_unlocated_pincodes_go_last(): void
    {
        $out = GeoSequencer::sequence([
            '482099' => null,
            '482001' => [23.000, 80.000],
            '482005' => [23.010, 80.000],
        ]);

        $this->assertSame('482099', end($out['sequence']));
        $this->assertSame(['482099'], $out['unlocated']);
    }
}

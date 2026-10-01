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

    public function test_four_day_cycle_from_spec(): void
    {
        $pending = $this->queue(['482001' => 52, '482005' => 48, '482002' => 75, '482008' => 60, '482020' => 100]);

        $days = [];
        while (!empty($pending)) {
            $today = DailyAllocator::take($pending, 100);
            $days[] = DailyAllocator::perPincode($today);
            $pending = array_slice($pending, count($today)); // everyone today gets called
        }

        $this->assertSame([
            ['482001' => 52, '482005' => 48],
            ['482002' => 75, '482008' => 25],
            ['482008' => 35, '482020' => 65],
            ['482020' => 35],
        ], $days);
    }

    public function test_unworked_accounts_carry_forward_first(): void
    {
        $pending = $this->queue(['A' => 3, 'B' => 3]);
        $day1 = DailyAllocator::take($pending, 4);           // A1 A2 A3 B1
        $worked = array_slice($day1, 0, 2);                    // only A1, A2 called
        $unworked = array_slice($day1, 2);                     // A3, B1 go back to pending at their rank
        $rest = array_merge($unworked, array_slice($pending, 4));

        $day2 = DailyAllocator::take($rest, 4);
        $this->assertSame(['A-3', 'B-1', 'B-2', 'B-3'], array_column($day2, 'id'));
        $this->assertCount(2, $worked);
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

<?php

namespace Tests\Unit;

use App\Services\OrderPlacementService;
use App\Support\UnitFactors;
use Illuminate\Support\Carbon;
use PHPUnit\Framework\TestCase;

/** Pure rules from ORDER_LIFECYCLE_FOR_NEW_FRONTEND.md §1 (stock) and §3 (time slot). */
class OrderRulesTest extends TestCase
{
    private function cfg(array $o = []): array
    {
        return $o + ['found' => true, 'delivery_interval' => 1, 'num_days_gap' => 0, 'order_time_end' => 2359, 'delivery_time_start' => 800, 'delivery_time_end' => 2200];
    }

    public function test_convert_time_matches_stored_format(): void
    {
        $this->assertSame('8:00am', OrderPlacementService::convertTime(800));
        $this->assertSame('10:00am', OrderPlacementService::convertTime(1000));
        $this->assertSame('6:00pm', OrderPlacementService::convertTime(1800));
        $this->assertSame('10:00pm', OrderPlacementService::convertTime(2200));
        $this->assertSame('12:00pm', OrderPlacementService::convertTime(1200));
        $this->assertSame('12:00am', OrderPlacementService::convertTime(0));
        $this->assertSame('12:00am', OrderPlacementService::convertTime(2400));
    }

    public function test_time_slot_before_cutoff(): void
    {
        $svc = new OrderPlacementService();
        $now = Carbon::create(2026, 10, 9, 15, 30, 0, 'Asia/Kolkata');
        $this->assertSame('10 Oct 8:00am  to  10 Oct 10:00pm', $svc->timeSlotText($this->cfg(), $now));
    }

    public function test_time_slot_after_cutoff_bumps_one_day(): void
    {
        $svc = new OrderPlacementService();
        $now = Carbon::create(2026, 10, 9, 15, 30, 0, 'Asia/Kolkata');
        $this->assertSame('11 Oct 8:00am  to  11 Oct 10:00pm', $svc->timeSlotText($this->cfg(['order_time_end' => 1500]), $now));
    }

    public function test_time_slot_window_gap_and_clamps(): void
    {
        $svc = new OrderPlacementService();
        $now = Carbon::create(2026, 10, 9, 9, 0, 0, 'Asia/Kolkata');
        $this->assertSame('10 Oct 11:00pm  to  16 Oct 12:00am',
            $svc->timeSlotText($this->cfg(['num_days_gap' => 6, 'delivery_time_start' => 2330, 'delivery_time_end' => 2600]), $now));
    }

    public function test_time_slot_empty_without_vendor_config(): void
    {
        $this->assertSame('', (new OrderPlacementService())->timeSlotText(['found' => false]));
    }

    public function test_unit_factors_and_pack_size(): void
    {
        $this->assertSame(1.0, UnitFactors::factor('KG'));
        $this->assertSame(10.0, UnitFactors::factor('10 Kgs'));
        $this->assertSame(5.0, UnitFactors::factor('5 Kg'));
        $this->assertSame(0.5, UnitFactors::factor('500 Gms.'));
        $this->assertSame(0.25, UnitFactors::factor('250ml'));
        $this->assertSame(0.2, UnitFactors::factor('0.2 KG'));
        $this->assertSame(1.0, UnitFactors::factor('Unit1'));
        $this->assertSame(0.5, UnitFactors::factor('500gm'));
        $this->assertSame(0.001, UnitFactors::factor('GM'));
        $this->assertSame(1.0, UnitFactors::factor('nos'));
        $this->assertSame(1.0, UnitFactors::factor('unknown-unit'));
        $this->assertSame(5.0, UnitFactors::extractFirstNumber('5pack * 100 gm'));
        $this->assertSame(0.2, UnitFactors::extractFirstNumber('0.2 KG'));
        $this->assertSame(1.0, UnitFactors::extractFirstNumber(''));
        // real pack: ps "4 Pack of 500 gm x 77/-", pu "500 Gms." → 1 qty = 4 × 0.5 kg
        $this->assertSame(2.0, UnitFactors::stockFor(1, ['ps' => '4 Pack of 500 gm x 77/-', 'pu' => '500 Gms.']));
        // 9 × "5 kg" packs need 45 kg of the shared stock pool
        $this->assertSame(45.0, UnitFactors::stockFor(9, ['ps' => '5 kg', 'pu' => 'kg']));
        // 4 × "5pack * 100 gm" with unit GM → 4 × 5 × 0.001
        $this->assertEqualsWithDelta(0.02, UnitFactors::stockFor(4, ['ps' => '5pack * 100 gm', 'pu' => 'GM']), 1e-9);
    }
}

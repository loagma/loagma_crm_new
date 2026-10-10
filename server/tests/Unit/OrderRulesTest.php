<?php

namespace Tests\Unit;

use App\Services\OrderPlacementService;
use App\Support\UnitConversion;
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

    /** units_master rows as on the dev DB (no dimension column → read from the name, like prod). */
    private function units(): void
    {
        UnitConversion::useUnits([
            ['unit_id' => 65, 'unit_name' => 'NOS', 'conversion_rate' => 1, 'is_active' => 1],
            ['unit_id' => 85, 'unit_name' => 'KG', 'conversion_rate' => 1, 'is_active' => 1],
            ['unit_id' => 86, 'unit_name' => 'GM', 'conversion_rate' => 0.001, 'is_active' => 1],
            ['unit_id' => 90, 'unit_name' => '5 kg', 'conversion_rate' => 5, 'is_active' => 1],
            ['unit_id' => 102, 'unit_name' => '500 GM', 'conversion_rate' => 0.5, 'is_active' => 1],
            ['unit_id' => 64, 'unit_name' => 'ML', 'conversion_rate' => 0.001, 'is_active' => 1],
            ['unit_id' => 84, 'unit_name' => 'test', 'conversion_rate' => 1, 'is_active' => 0],
            ['unit_id' => 128, 'unit_name' => '10 TIN', 'conversion_rate' => 10, 'is_active' => 1],
        ]);
    }

    public function test_units_master_conversion(): void
    {
        $this->units();
        // "1 Pack of 5 Kg" with unit 5 kg: 2 packs = 2 × 1 × 5 = 10 kg of KG stock
        $five = ['tx' => '1 Pack of 5 Kg @ 855/-', 'ps' => '1 Pack of 5 Kg @ 855/-', 'pui' => 90];
        $this->assertSame(10.0, UnitConversion::need(2, $five, 85));
        // "4 Pack of 500 gm" with unit 500 GM = 2 kg per pack
        $this->assertSame(2.0, UnitConversion::basePerPack(['tx' => '4 Pack of 500 gm x 77/-', 'ps' => '4 Pack of 500 gm x 77/-', 'pui' => 102], 85));
        // same 500 g pack against stock kept in GM → 500 grams
        $this->assertSame(500.0, UnitConversion::basePerPack(['tx' => '1 pack 500 g', 'ps' => '1 pack 500 g', 'pui' => 102], 86));
        // count units: "1 Cs" of NOS stock = 1, "10 TIN" unit = 10 NOS
        $this->assertSame(1.0, UnitConversion::basePerPack(['tx' => '1 Tin', 'ps' => '1 Tin', 'pui' => 65], 65));
        $this->assertSame(10.0, UnitConversion::basePerPack(['tx' => '1 box', 'ps' => '1 box', 'pui' => 128], 65));
        $this->assertNull(UnitConversion::problem($five, 85));
        $this->assertSame(2.0, UnitConversion::writtenBase(['tx' => '4 Pack of 500 gm x 77/-']));
        $this->assertSame(10.0, UnitConversion::writtenBase(['tx' => '10 Kg x 190/-']));
    }

    public function test_untrustworthy_packs_are_blocked(): void
    {
        $this->units();
        // no pui / unknown / inactive unit
        $this->assertStringContainsString('not set', UnitConversion::problem(['tx' => '1 kg', 'ps' => '1'], 85));
        $this->assertStringContainsString('not in units_master', UnitConversion::problem(['tx' => '1 kg', 'ps' => '1', 'pui' => 999], 85));
        $this->assertStringContainsString('inactive', UnitConversion::problem(['tx' => '15 nos', 'ps' => '15', 'pui' => 84], 65));
        // Almond: "1 Pack of 5 Kg" saved with unit KG → text says 5 kg, conversion gives 1
        $this->assertStringContainsString('pack text says 5 kg', UnitConversion::problem(['tx' => '1 Pack of 5 Kg @ 855/-', 'ps' => '1 Pack of 5 Kg @ 855/-', 'pui' => 85], 85));
        // Urad: "Pack of 30 Kg" with a 5 kg-type size unit → ps count 30 × rate → wrong
        $this->assertNotNull(UnitConversion::problem(['tx' => 'Pack of 30 Kg', 'ps' => 'Pack of 30 Kg', 'pui' => 90], 85));
        // count unit on weight stock, weight unit on count stock, volume on weight
        $this->assertStringContainsString('does not match', UnitConversion::problem(['tx' => '500 gm', 'ps' => '500 gm', 'pui' => 65], 85));
        $this->assertStringContainsString('does not match', UnitConversion::problem(['tx' => '1 Pack of 1 Kg', 'ps' => '1 Pack of 1 Kg', 'pui' => 85], 65));
        $this->assertStringContainsString('does not match', UnitConversion::problem(['tx' => '1 pack 250 g', 'ps' => '1 pack 250 g', 'pui' => 64], 85));
        // ps "0" → zero stock per pack
        $this->assertStringContainsString('zero', UnitConversion::problem(['tx' => '0', 'ps' => '0', 'pui' => 85], 85));
        UnitConversion::flush();
    }
}

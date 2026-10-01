<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

// A telecaller's geographic calling plan: the pincodes they selected, the
// proximity-ordered sequence the backend derived from them, and the daily
// capacity they entered. At most one `active` plan per telecaller (enforced in
// TelecallerAllocationController — re-selecting merges into the active plan).
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('tc_allocation_plan_crm', function (Blueprint $table) {
            $table->bigIncrements('id');
            $table->string('employee_mobile', 20);        // deli_staff.mobile
            $table->json('selected_pincodes');
            $table->json('pincode_sequence');             // ordered pincodes
            $table->unsignedInteger('daily_capacity');
            $table->string('status', 12)->default('active'); // active | completed | cancelled
            $table->timestamps();

            $table->index(['employee_mobile', 'status']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('tc_allocation_plan_crm');
    }
};

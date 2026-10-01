<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

// The telecaller now picks a From–To date range instead of a per-day count:
// each day's list = remaining accounts ÷ remaining days (today..end_date),
// re-divided every morning so the plan finishes by end_date. Past end_date,
// a day's list is everything still remaining. daily_capacity is kept as the
// informational starting per-day figure (total ÷ days at creation).
// Plain IST dates (cast date:Y-m-d).
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('tc_allocation_plan_crm', function (Blueprint $table) {
            if (!Schema::hasColumn('tc_allocation_plan_crm', 'start_date')) {
                $table->date('start_date')->nullable()->after('daily_capacity');
            }
            if (!Schema::hasColumn('tc_allocation_plan_crm', 'end_date')) {
                $table->date('end_date')->nullable()->after('start_date');
            }
        });
    }

    public function down(): void
    {
        Schema::table('tc_allocation_plan_crm', function (Blueprint $table) {
            $table->dropColumn(['start_date', 'end_date']);
        });
    }
};

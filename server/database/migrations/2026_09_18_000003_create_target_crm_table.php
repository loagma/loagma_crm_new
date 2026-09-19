<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

// Per-telecaller, per-period call/conversion goals — powers the Telecaller
// Performance report's "scorecard vs. target" view. `telecaller_id` stores
// deli_staff.mobile, matching every other staff-attribution field in this app
// (see LeadsAccount_crm.createdById, beat_plan_followup_crm.staff_id).
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('target_crm', function (Blueprint $table) {
            $table->id();
            $table->string('telecaller_id', 191);
            $table->string('period', 20); // e.g. '2026-09' for a monthly target
            $table->unsignedInteger('call_target')->default(0);
            $table->unsignedInteger('conversion_target')->default(0);
            $table->timestamps();

            $table->unique(['telecaller_id', 'period']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('target_crm');
    }
};

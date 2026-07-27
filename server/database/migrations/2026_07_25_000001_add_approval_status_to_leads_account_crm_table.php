<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        // Idempotent: survives a partial rollback that left the column behind.
        if (!Schema::hasColumn('LeadsAccount_crm', 'approval_status')) {
            Schema::table('LeadsAccount_crm', function (Blueprint $table) {
                // Distinct from `isApproved` (kept as secondary metadata): every
                // existing row has isApproved=false today regardless of whether
                // it was ever actually reviewed, so a plain boolean can't tell
                // "never reviewed" apart from "rejected". This column can.
                $table->string('approval_status', 20)->default('pending')->after('isApproved');
            });

            // Backfill: only rows already marked isApproved=true were ever
            // actually approved (nothing in the app sets isApproved=true today
            // except this migration's own future approve() action) — every
            // other existing row has simply never been reviewed.
            DB::table('LeadsAccount_crm')
                ->where('isApproved', true)
                ->update(['approval_status' => 'approved']);
        }
    }

    public function down(): void
    {
        Schema::table('LeadsAccount_crm', function (Blueprint $table) {
            $table->dropColumn('approval_status');
        });
    }
};

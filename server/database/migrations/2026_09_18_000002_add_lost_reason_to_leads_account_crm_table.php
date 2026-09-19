<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

// Companion to rejectionNotes: set when a still-pending lead is marked lost
// (approval_status='lost') rather than approved or rejected outright — the
// prospect went cold before ever reaching a review decision.
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('LeadsAccount_crm', function (Blueprint $table) {
            if (! Schema::hasColumn('LeadsAccount_crm', 'lost_reason')) {
                $table->string('lost_reason', 50)->nullable()->after('rejectionNotes');
            }
        });
    }

    public function down(): void
    {
        Schema::table('LeadsAccount_crm', function (Blueprint $table) {
            if (Schema::hasColumn('LeadsAccount_crm', 'lost_reason')) {
                $table->dropColumn('lost_reason');
            }
        });
    }
};

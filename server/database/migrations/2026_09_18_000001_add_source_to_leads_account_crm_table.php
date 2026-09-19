<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

// Where the lead came from. Fixed set (unlike language_crm, this doesn't need
// an admin-editable master list), used to power the Lead Source report.
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('LeadsAccount_crm', function (Blueprint $table) {
            if (! Schema::hasColumn('LeadsAccount_crm', 'source')) {
                $table->enum('source', ['referral', 'campaign', 'walk_in', 'cold_call', 'website', 'other'])
                    ->nullable()
                    ->after('personName');
            }
        });
    }

    public function down(): void
    {
        Schema::table('LeadsAccount_crm', function (Blueprint $table) {
            if (Schema::hasColumn('LeadsAccount_crm', 'source')) {
                $table->dropColumn('source');
            }
        });
    }
};

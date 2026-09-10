<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

// Preferred / spoken language of the lead account's contact person. Free
// string holding a language_crm.name value, set from the Lead Account form.
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('LeadsAccount_crm', function (Blueprint $table) {
            if (! Schema::hasColumn('LeadsAccount_crm', 'language')) {
                $table->string('language', 191)->nullable()->after('contactNumber');
            }
        });
    }

    public function down(): void
    {
        Schema::table('LeadsAccount_crm', function (Blueprint $table) {
            if (Schema::hasColumn('LeadsAccount_crm', 'language')) {
                $table->dropColumn('language');
            }
        });
    }
};

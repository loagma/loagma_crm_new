<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

// Preferred / spoken language of an employee. Free string holding a
// language_crm.name value, set from the Create/Edit Employee dropdown.
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('deli_staff', function (Blueprint $table) {
            if (! Schema::hasColumn('deli_staff', 'language')) {
                $table->string('language', 50)->nullable()->after('state');
            }
        });
    }

    public function down(): void
    {
        Schema::table('deli_staff', function (Blueprint $table) {
            if (Schema::hasColumn('deli_staff', 'language')) {
                $table->dropColumn('language');
            }
        });
    }
};

<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('location_pings_crm', function (Blueprint $table) {
            $table->decimal('heading', 6, 2)->nullable()->after('speed'); // degrees 0-360, as reported by GPS
        });
    }

    public function down(): void
    {
        Schema::table('location_pings_crm', function (Blueprint $table) {
            $table->dropColumn('heading');
        });
    }
};

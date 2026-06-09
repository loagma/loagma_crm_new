<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    public function up(): void
    {
        Schema::table('beat_plan_crm', function (Blueprint $table) {
            $table->date('week_anchor_date')->nullable()->after('days');
        });
    }

    public function down(): void
    {
        Schema::table('beat_plan_crm', function (Blueprint $table) {
            $table->dropColumn('week_anchor_date');
        });
    }
};

<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('deli_staff', function (Blueprint $table) {
            $table->time('punch_in_time')->nullable()->default('09:00:00')->after('is_locked');
            $table->time('punch_out_time')->nullable()->default('18:00:00')->after('punch_in_time');
            $table->integer('grace_minutes')->default(15)->after('punch_out_time');
        });
    }

    public function down(): void
    {
        Schema::table('deli_staff', function (Blueprint $table) {
            $table->dropColumn(['punch_in_time', 'punch_out_time', 'grace_minutes']);
        });
    }
};

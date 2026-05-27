<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('attendance_crm', function (Blueprint $table) {
            $table->string('punch_in_photo')->nullable()->after('punch_in_time');
            $table->string('punch_out_photo')->nullable()->after('punch_out_time');
        });
    }

    public function down(): void
    {
        Schema::table('attendance_crm', function (Blueprint $table) {
            $table->dropColumn(['punch_in_photo', 'punch_out_photo']);
        });
    }
};

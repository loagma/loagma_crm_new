<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('attendance_crm', function (Blueprint $table) {
            $table->json('punch_in_location')->nullable()->after('punch_in_photo');
            $table->json('punch_out_location')->nullable()->after('punch_out_photo');
        });
    }

    public function down(): void
    {
        Schema::table('attendance_crm', function (Blueprint $table) {
            $table->dropColumn(['punch_in_location', 'punch_out_location']);
        });
    }
};

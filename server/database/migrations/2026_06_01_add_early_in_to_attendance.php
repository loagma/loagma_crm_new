<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('attendance_crm', function (Blueprint $table) {
            $table->boolean('is_early_in')->default(false)->after('is_early_out');
            $table->text('early_in_reason')->nullable()->after('early_out_reason');
        });

        DB::statement("ALTER TABLE attendance_crm MODIFY COLUMN status
            ENUM('on_time','pending','approved','rejected','early_in') DEFAULT 'on_time'");
    }

    public function down(): void
    {
        Schema::table('attendance_crm', function (Blueprint $table) {
            $table->dropColumn(['is_early_in', 'early_in_reason']);
        });

        DB::statement("ALTER TABLE attendance_crm MODIFY COLUMN status
            ENUM('on_time','pending','approved','rejected') DEFAULT 'on_time'");
    }
};

<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        // Idempotent: survives a partial rollback that left the column behind.
        if (!Schema::hasColumn('attendance_crm', 'total_distance_km')) {
            Schema::table('attendance_crm', function (Blueprint $table) {
                // Filled at punch-out, or lazily by TrackingController::route()
                // once the shift is closed. Null = not yet computed.
                $table->double('total_distance_km')->nullable()->after('was_interrupted');
            });
        }
    }

    public function down(): void
    {
        Schema::table('attendance_crm', function (Blueprint $table) {
            $table->dropColumn('total_distance_km');
        });
    }
};

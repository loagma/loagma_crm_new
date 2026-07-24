<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        // Idempotent: survives a partial rollback that left the column behind.
        if (!Schema::hasColumn('attendance_crm', 'route_snapped')) {
            Schema::table('attendance_crm', function (Blueprint $table) {
                // OSRM-matched display geometry for a CLOSED day, cached so
                // each day is snapped at most once (RouteSnapper). One entry
                // per contiguous run: [[lat, lng], ...] or null. Cosmetic
                // only — total_distance_km stays raw (see RouteDistance).
                $table->json('route_snapped')->nullable()->after('total_distance_km');
            });
        }
    }

    public function down(): void
    {
        Schema::table('attendance_crm', function (Blueprint $table) {
            $table->dropColumn('route_snapped');
        });
    }
};

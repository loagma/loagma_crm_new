<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        // Idempotent: survives a partial rollback that left these columns behind.
        if (!Schema::hasColumn('attendance_crm', 'last_ping_at')) {
            Schema::table('attendance_crm', function (Blueprint $table) {
                $table->dateTime('last_ping_at')->nullable()->after('punch_out_location');
            });
        }
        if (!Schema::hasColumn('attendance_crm', 'was_interrupted')) {
            Schema::table('attendance_crm', function (Blueprint $table) {
                $table->boolean('was_interrupted')->default(false)->after('last_ping_at');
            });
        }
    }

    public function down(): void
    {
        Schema::table('attendance_crm', function (Blueprint $table) {
            $table->dropColumn(['last_ping_at', 'was_interrupted']);
        });
    }
};

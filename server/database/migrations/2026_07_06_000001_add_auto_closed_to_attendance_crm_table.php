<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        // Idempotent: survives a partial rollback that left this column behind.
        if (Schema::hasColumn('attendance_crm', 'auto_closed')) {
            return;
        }
        Schema::table('attendance_crm', function (Blueprint $table) {
            $table->boolean('auto_closed')->default(false)->after('was_interrupted');
        });
    }

    public function down(): void
    {
        Schema::table('attendance_crm', function (Blueprint $table) {
            $table->dropColumn('auto_closed');
        });
    }
};

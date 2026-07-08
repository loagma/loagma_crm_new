<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Facades\DB;

return new class extends Migration {
    public function up(): void
    {
        $afterColumn = Schema::hasColumn('beat_plan_crm', 'specific_dates')
            ? 'specific_dates'
            : 'month_date';

        Schema::table('beat_plan_crm', function (Blueprint $table) use ($afterColumn) {
            $table->dateTime('appointment_date')->nullable()->after($afterColumn);
        });

        if (Schema::hasTable('beat_plan_crm')) {
            $column = DB::select("SHOW COLUMNS FROM beat_plan_crm WHERE Field = 'frequency'");
            if ($column) {
                Schema::table('beat_plan_crm', function (Blueprint $table) {
                    $table->enum('frequency', ['weekly', 'monthly', 'n_days', 'specific_dates', 'appointment'])
                        ->change();
                });
            }
        }
    }

    public function down(): void
    {
        Schema::table('beat_plan_crm', function (Blueprint $table) {
            $table->dropColumn('appointment_date');
        });

        if (Schema::hasTable('beat_plan_crm')) {
            Schema::table('beat_plan_crm', function (Blueprint $table) {
                $table->enum('frequency', ['weekly', 'monthly', 'n_days', 'specific_dates'])
                    ->change();
            });
        }
    }
};

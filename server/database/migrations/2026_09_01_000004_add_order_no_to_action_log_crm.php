<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * When a salesman picks the "Placed order" stage at check-out, the Action Log
 * popup also asks which order number was placed.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('action_log_crm', function (Blueprint $table) {
            $table->string('order_no', 50)->nullable()->after('outcome_name');
        });
    }

    public function down(): void
    {
        Schema::table('action_log_crm', function (Blueprint $table) {
            $table->dropColumn('order_no');
        });
    }
};

<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('call_log_crm', function (Blueprint $table) {
            if (!Schema::hasColumn('call_log_crm', 'callback_done')) {
                $table->boolean('callback_done')->default(false)->after('follow_up_date');
            }
        });
    }

    public function down(): void
    {
        Schema::table('call_log_crm', function (Blueprint $table) {
            if (Schema::hasColumn('call_log_crm', 'callback_done')) {
                $table->dropColumn('callback_done');
            }
        });
    }
};

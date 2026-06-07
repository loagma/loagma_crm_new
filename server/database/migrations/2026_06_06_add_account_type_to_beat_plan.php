<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    public function up(): void
    {
        Schema::table('beat_plan_crm', function (Blueprint $table) {
            $table->string('account_type')->default('lead')->after('account_id');
        });
    }

    public function down(): void
    {
        Schema::table('beat_plan_crm', function (Blueprint $table) {
            $table->dropColumn('account_type');
        });
    }
};

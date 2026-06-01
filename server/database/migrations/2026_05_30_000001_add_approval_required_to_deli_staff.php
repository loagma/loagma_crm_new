<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('deli_staff', function (Blueprint $table) {
            $table->boolean('approval_required')->default(true)->after('grace_minutes');
        });
    }

    public function down(): void
    {
        Schema::table('deli_staff', function (Blueprint $table) {
            $table->dropColumn('approval_required');
        });
    }
};

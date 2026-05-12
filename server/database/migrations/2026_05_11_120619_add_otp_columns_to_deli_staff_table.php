<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Run the migrations.
     */
    public function up(): void
    {
        Schema::table('deli_staff', function (Blueprint $table) {
            $table->string('otp', 6)->nullable()->after('role');
            $table->dateTime('otp_expires_at')->nullable()->after('otp');
        });
    }

    public function down(): void
    {
        Schema::table('deli_staff', function (Blueprint $table) {
            $table->dropColumn(['otp', 'otp_expires_at']);
        });
    }
};

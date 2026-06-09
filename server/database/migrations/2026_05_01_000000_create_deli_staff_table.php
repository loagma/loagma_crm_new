<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        if (Schema::hasTable('deli_staff')) {
            return;
        }

        Schema::create('deli_staff', function (Blueprint $table) {
            $table->unsignedBigInteger('deli_id')->autoIncrement();
            $table->string('mobile', 20)->primary();
            $table->string('name', 255);
            $table->string('role', 50)->nullable();
            $table->string('pincode', 20)->nullable();
            $table->string('city', 100)->nullable();
            $table->string('state', 100)->nullable();
            $table->boolean('is_locked')->default(false);
            $table->string('sess_id')->nullable();
            $table->dateTime('location_last_updated')->nullable();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('deli_staff');
    }
};

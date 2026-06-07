<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('beat_plan_crm', function (Blueprint $table) {
            $table->bigIncrements('id');
            $table->string('account_id');          // FK → LeadsAccount_crm.id (UUID string)
            $table->string('salesman_id', 20);     // salesman mobile
            $table->enum('frequency', ['weekly', 'monthly', 'n_days']);
            $table->json('days')->nullable();      // ['Mon','Fri'] — weekly only
            $table->unsignedTinyInteger('month_date')->nullable(); // 1-31 — monthly only
            $table->unsignedSmallInteger('interval_days')->nullable(); // N — n_days only
            $table->date('start_date')->nullable(); // anchor date for n_days
            $table->boolean('is_active')->default(true);
            $table->timestamps();

            $table->unique(['account_id', 'salesman_id']); // one plan per account per salesman
            $table->index('salesman_id');
            $table->index('is_active');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('beat_plan_crm');
    }
};

<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('beat_plan_visit_crm', function (Blueprint $table) {
            $table->bigIncrements('id');
            $table->unsignedBigInteger('beat_plan_id');
            $table->string('account_id');          // denormalised for fast queries
            $table->string('salesman_id', 20);     // denormalised
            $table->date('visit_date');
            $table->enum('status', ['visited', 'missed', 'skipped'])->default('visited');
            $table->text('notes')->nullable();
            $table->timestamps();

            $table->unique(['beat_plan_id', 'visit_date']); // one log per plan per day
            $table->index('salesman_id');
            $table->index('visit_date');

            $table->foreign('beat_plan_id')
                  ->references('id')
                  ->on('beat_plan_crm')
                  ->onDelete('cascade');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('beat_plan_visit_crm');
    }
};

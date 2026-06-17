<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('order_funnel_response_crm', function (Blueprint $table) {
            $table->id();
            $table->string('employee_mobile');
            $table->string('account_id');
            $table->enum('account_type', ['lead', 'customer'])->nullable();
            $table->unsignedBigInteger('beat_plan_id')->nullable();
            $table->string('funnel_slug', 100);     // selected order_funnel_crm slug
            $table->string('funnel_name', 150);     // denormalised display label
            $table->text('general_notes')->nullable();
            $table->string('notes_related_to', 150)->nullable();
            $table->timestamps();

            $table->index('employee_mobile');
            $table->index('account_id');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('order_funnel_response_crm');
    }
};

<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * A follow-up scheduled from the Action Log check-out popup. Surfaces on the
 * future day's Beat Plan (salesman) / Worklist (telecaller) and on the
 * telecaller Callbacks screen — the one place both roles' follow-ups live.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('beat_plan_followup_crm', function (Blueprint $table) {
            $table->bigIncrements('id');
            $table->string('account_id');
            $table->enum('account_type', ['lead', 'customer'])->nullable();
            $table->string('staff_id', 20);                 // deli_staff.mobile of whoever scheduled it
            $table->date('due_date');
            $table->string('note', 255)->nullable();
            $table->unsignedBigInteger('source_action_log_id')->nullable();
            $table->boolean('done')->default(false);
            $table->timestamp('done_at')->nullable();
            $table->timestamps();

            $table->index('staff_id');
            $table->index('due_date');
            $table->index('account_id');
            $table->index(['staff_id', 'done', 'due_date']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('beat_plan_followup_crm');
    }
};

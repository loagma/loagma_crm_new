<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

// The allocation queue: one row per account in a plan. Queue order is
// (pincode_rank, account_rank); the next day's list is simply the lowest-ranked
// `pending` rows up to the plan's daily_capacity, which is what carries a
// half-finished pincode forward into the next day. allocated_date is a naive
// IST date (see timezone convention).
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('tc_allocation_item_crm', function (Blueprint $table) {
            $table->bigIncrements('id');
            $table->unsignedBigInteger('plan_id');            // tc_allocation_plan_crm.id
            $table->string('employee_mobile', 20);
            $table->string('account_id', 64);                 // user.userid or LeadsAccount_crm.id
            $table->string('account_type', 10);               // customer | lead
            $table->string('pincode', 10)->nullable();
            $table->unsignedInteger('pincode_rank');
            $table->unsignedInteger('account_rank');
            // pending | assigned | in_progress | completed | skipped | callback
            $table->string('status', 12)->default('pending');
            $table->date('allocated_date')->nullable();
            $table->unsignedBigInteger('call_log_id')->nullable();
            $table->dateTime('completed_at')->nullable();
            $table->timestamps();

            $table->unique(['plan_id', 'account_id']);
            $table->index(['plan_id', 'status', 'pincode_rank', 'account_rank'], 'tc_alloc_item_queue_idx');
            $table->index(['employee_mobile', 'allocated_date'], 'tc_alloc_item_day_idx');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('tc_allocation_item_crm');
    }
};

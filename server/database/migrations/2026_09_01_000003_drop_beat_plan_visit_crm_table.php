<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * beat_plan_visit_crm is folded into action_log_crm (a checked-out action_log
 * row IS the "visited today" record now). The table currently holds 0 rows on
 * the live DB, but back-fill anything present just in case, then drop it.
 */
return new class extends Migration
{
    public function up(): void
    {
        if (Schema::hasTable('beat_plan_visit_crm')) {
            foreach (DB::table('beat_plan_visit_crm')->get() as $v) {
                DB::table('action_log_crm')->insert([
                    'employee_mobile' => $v->salesman_id,
                    'role'            => 'salesman',
                    'account_id'      => $v->account_id,
                    'account_type'    => null,
                    'beat_plan_id'    => $v->beat_plan_id,
                    'check_out_at'    => $v->visit_date . ' 12:00:00',
                    'status'          => $v->status,
                    'general_notes'   => $v->notes,
                    'created_at'      => $v->created_at ?? now(),
                    'updated_at'      => $v->updated_at ?? now(),
                ]);
            }

            Schema::table('beat_plan_visit_crm', function (Blueprint $table) {
                // FK to beat_plan_crm must go before the drop on some engines.
                try {
                    $table->dropForeign(['beat_plan_id']);
                } catch (\Throwable $e) {
                    // no-op if the constraint name differs / already gone
                }
            });

            Schema::dropIfExists('beat_plan_visit_crm');
        }
    }

    public function down(): void
    {
        Schema::create('beat_plan_visit_crm', function (Blueprint $table) {
            $table->bigIncrements('id');
            $table->unsignedBigInteger('beat_plan_id');
            $table->string('account_id');
            $table->string('salesman_id', 20);
            $table->date('visit_date');
            $table->enum('status', ['visited', 'missed', 'skipped'])->default('visited');
            $table->text('notes')->nullable();
            $table->timestamps();

            $table->unique(['beat_plan_id', 'visit_date']);
            $table->index('salesman_id');
            $table->index('visit_date');
            $table->foreign('beat_plan_id')->references('id')->on('beat_plan_crm')->onDelete('cascade');
        });
    }
};

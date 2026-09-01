<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * "Order Funnel" -> "Action Log". The salesman visit-funnel form and the
 * telecaller post-call form now write one shared table. Renames the two
 * order_funnel_* tables, renames visit_in/out -> check_in/out, and widens the
 * table with the role-specific fields the unified check-out popup collects.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::rename('order_funnel_crm', 'action_log_stage_crm');
        Schema::rename('order_funnel_response_crm', 'action_log_crm');

        Schema::table('action_log_crm', function (Blueprint $table) {
            $table->renameColumn('visit_in_at', 'check_in_at');
            $table->renameColumn('visit_out_at', 'check_out_at');
            $table->renameColumn('funnel_slug', 'outcome_slug');
            $table->renameColumn('funnel_name', 'outcome_name');
        });

        // funnel_slug/name were NOT NULL — a telecaller row has no stage, so relax them.
        DB::statement("ALTER TABLE action_log_crm MODIFY outcome_slug VARCHAR(100) NULL");
        DB::statement("ALTER TABLE action_log_crm MODIFY outcome_name VARCHAR(150) NULL");

        Schema::table('action_log_crm', function (Blueprint $table) {
            $table->enum('role', ['salesman', 'telecaller'])->default('salesman')->after('employee_mobile');

            // Silent best-effort GPS fix on check-in / check-out.
            $table->decimal('check_in_lat', 10, 7)->nullable()->after('check_in_at');
            $table->decimal('check_in_lng', 10, 7)->nullable()->after('check_in_lat');
            $table->decimal('check_out_lat', 10, 7)->nullable()->after('check_out_at');
            $table->decimal('check_out_lng', 10, 7)->nullable()->after('check_out_lat');

            // Folded in from beat_plan_visit_crm.
            $table->enum('status', ['visited', 'missed', 'skipped'])->default('visited')->after('outcome_name');

            // Telecaller output.
            $table->string('call_outcome', 30)->nullable()->after('status');       // answered/busy/no_answer/switch_off/invalid/callback/complaint
            $table->string('call_status', 60)->nullable()->after('call_outcome');   // raw status from the call engine
            $table->boolean('is_invalid_call')->default(false)->after('call_status');
            $table->unsignedBigInteger('call_log_id')->nullable()->after('is_invalid_call'); // -> call_log_crm.id (Knowlarity row, recording)
            $table->text('conversation_notes')->nullable()->after('call_log_id');
            $table->text('discussion_points')->nullable()->after('conversation_notes');
            $table->string('customer_stage', 40)->nullable()->after('discussion_points');
            $table->string('funnel_stage', 40)->nullable()->after('customer_stage');

            // Salesman output.
            $table->decimal('payment_collected', 12, 2)->nullable()->after('funnel_stage');
            $table->string('payment_mode', 30)->nullable()->after('payment_collected');
            $table->text('market_note')->nullable()->after('payment_mode');

            // Shared.
            $table->date('follow_up_date')->nullable()->after('market_note');
            $table->string('follow_up_note', 255)->nullable()->after('follow_up_date');

            $table->index('call_log_id');
            $table->index(['account_id', 'created_at']);
        });
    }

    public function down(): void
    {
        Schema::table('action_log_crm', function (Blueprint $table) {
            $table->dropIndex(['account_id', 'created_at']);
            $table->dropIndex(['call_log_id']);
            $table->dropColumn([
                'role', 'check_in_lat', 'check_in_lng', 'check_out_lat', 'check_out_lng',
                'status', 'call_outcome', 'call_status', 'is_invalid_call', 'call_log_id',
                'conversation_notes', 'discussion_points', 'customer_stage', 'funnel_stage',
                'payment_collected', 'payment_mode', 'market_note', 'follow_up_date', 'follow_up_note',
            ]);
        });

        DB::statement("UPDATE action_log_crm SET outcome_slug = '' WHERE outcome_slug IS NULL");
        DB::statement("UPDATE action_log_crm SET outcome_name = '' WHERE outcome_name IS NULL");
        DB::statement("ALTER TABLE action_log_crm MODIFY outcome_slug VARCHAR(100) NOT NULL");
        DB::statement("ALTER TABLE action_log_crm MODIFY outcome_name VARCHAR(150) NOT NULL");

        Schema::table('action_log_crm', function (Blueprint $table) {
            $table->renameColumn('check_in_at', 'visit_in_at');
            $table->renameColumn('check_out_at', 'visit_out_at');
            $table->renameColumn('outcome_slug', 'funnel_slug');
            $table->renameColumn('outcome_name', 'funnel_name');
        });

        Schema::rename('action_log_stage_crm', 'order_funnel_crm');
        Schema::rename('action_log_crm', 'order_funnel_response_crm');
    }
};

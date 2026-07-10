<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Facades\DB;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('call_log_crm', function (Blueprint $table) {
            $table->string('source')->default('manual')->after('employee_mobile'); // manual | knowlarity
            $table->string('direction')->nullable()->after('source'); // inbound | outbound
            $table->string('knowlarity_call_id')->nullable()->index()->after('direction');
            $table->unsignedInteger('duration_seconds')->nullable()->after('knowlarity_call_id');
            $table->string('recording_url')->nullable()->after('duration_seconds');
            $table->json('raw_payload')->nullable()->after('recording_url');
        });

        // employee_mobile must become nullable (unmatched inbound calls have no agent yet)
        // and call_outcome/account_type need to accept provider-only states not used by
        // the manual-logging flow. Widen both via raw SQL since the original columns
        // were created with fixed ENUM/NOT NULL definitions Doctrine DBAL can't alter.
        DB::statement("ALTER TABLE call_log_crm MODIFY employee_mobile VARCHAR(255) NULL");
        DB::statement("ALTER TABLE call_log_crm MODIFY account_type ENUM('lead','customer','unknown') NOT NULL DEFAULT 'unknown'");
        DB::statement("ALTER TABLE call_log_crm MODIFY call_outcome ENUM('answered','busy','no_answer','switch_off','invalid','callback','pending') NULL");
    }

    public function down(): void
    {
        Schema::table('call_log_crm', function (Blueprint $table) {
            $table->dropColumn(['source', 'direction', 'knowlarity_call_id', 'duration_seconds', 'recording_url', 'raw_payload']);
        });

        DB::statement("ALTER TABLE call_log_crm MODIFY employee_mobile VARCHAR(255) NOT NULL");
        DB::statement("ALTER TABLE call_log_crm MODIFY account_type ENUM('lead','customer') NOT NULL");
        DB::statement("ALTER TABLE call_log_crm MODIFY call_outcome ENUM('answered','busy','no_answer','switch_off','invalid','callback') NOT NULL");
    }
};

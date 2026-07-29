<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

return new class extends Migration
{
    public function up(): void
    {
        // Same technique as 2026_07_09_010000_add_knowlarity_fields_to_call_log_crm.php —
        // fixed ENUMs can't be altered via Doctrine DBAL, raw SQL is required.
        DB::statement("ALTER TABLE call_log_crm MODIFY call_outcome ENUM('answered','busy','no_answer','switch_off','invalid','callback','pending','complaint') NULL");
    }

    public function down(): void
    {
        DB::statement("ALTER TABLE call_log_crm MODIFY call_outcome ENUM('answered','busy','no_answer','switch_off','invalid','callback','pending') NULL");
    }
};

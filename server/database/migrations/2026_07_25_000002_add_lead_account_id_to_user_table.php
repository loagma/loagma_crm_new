<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        // Purely additive on the legacy `user` table — links a customer row
        // back to the LeadsAccount it was converted from (lead approval flow).
        if (!Schema::hasColumn('user', 'lead_account_id')) {
            Schema::table('user', function (Blueprint $table) {
                $table->string('lead_account_id', 36)->nullable();
            });
        }
    }

    public function down(): void
    {
        Schema::table('user', function (Blueprint $table) {
            $table->dropColumn('lead_account_id');
        });
    }
};

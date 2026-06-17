<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('order_funnel_response_crm', function (Blueprint $table) {
            $table->timestamp('visit_in_at')->nullable()->after('beat_plan_id');
            $table->timestamp('visit_out_at')->nullable()->after('visit_in_at');
            $table->unsignedInteger('duration_seconds')->nullable()->after('visit_out_at');
            $table->json('images')->nullable()->after('notes_related_to');
        });
    }

    public function down(): void
    {
        Schema::table('order_funnel_response_crm', function (Blueprint $table) {
            $table->dropColumn(['visit_in_at', 'visit_out_at', 'duration_seconds', 'images']);
        });
    }
};

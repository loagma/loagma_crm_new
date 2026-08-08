<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('complaint_crm', function (Blueprint $table) {
            $table->string('assigned_to')->nullable()->after('raised_by'); // employee mobile
            $table->string('assigned_by')->nullable()->after('assigned_to'); // employee mobile
            $table->timestamp('assigned_at')->nullable()->after('assigned_by');

            $table->index('assigned_to');
        });
    }

    public function down(): void
    {
        Schema::table('complaint_crm', function (Blueprint $table) {
            $table->dropIndex(['assigned_to']);
            $table->dropColumn(['assigned_to', 'assigned_by', 'assigned_at']);
        });
    }
};

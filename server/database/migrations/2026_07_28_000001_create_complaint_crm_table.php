<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('complaint_crm', function (Blueprint $table) {
            $table->id();
            $table->string('account_id');
            $table->enum('account_type', ['lead', 'customer']);
            $table->enum('source_channel', ['telecaller_call', 'salesman_visit']);
            $table->string('raised_by'); // employee mobile
            $table->unsignedBigInteger('call_log_id')->nullable();
            $table->unsignedBigInteger('beat_plan_id')->nullable();
            $table->string('category');
            $table->text('description');
            $table->enum('status', ['open', 'in_progress', 'resolved', 'closed'])->default('open');
            $table->text('resolution_notes')->nullable();
            $table->string('resolved_by')->nullable();
            $table->timestamp('resolved_at')->nullable();
            $table->timestamps();

            $table->index('account_id');
            $table->index('raised_by');
            $table->index('status');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('complaint_crm');
    }
};

<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('call_log_crm', function (Blueprint $table) {
            $table->id();
            $table->string('employee_mobile');
            $table->string('account_id')->nullable();
            $table->enum('account_type', ['lead', 'customer']);
            $table->enum('call_outcome', ['answered', 'busy', 'no_answer', 'switch_off', 'invalid', 'callback']);
            $table->text('notes')->nullable();
            $table->date('follow_up_date')->nullable();
            $table->timestamp('called_at')->useCurrent();
            $table->timestamps();

            $table->index('employee_mobile');
            $table->index('account_id');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('call_log_crm');
    }
};

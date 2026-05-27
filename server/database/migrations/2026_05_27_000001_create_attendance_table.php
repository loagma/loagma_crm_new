<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('attendance_crm', function (Blueprint $table) {
            $table->id();
            $table->string('employee_mobile', 20); // references deli_staff.mobile (PK)
            $table->date('date');
            $table->dateTime('punch_in_time')->nullable();
            $table->dateTime('punch_out_time')->nullable();
            $table->json('break_details')->nullable(); // [{type, start, end}]
            $table->integer('total_work_minutes')->nullable();
            $table->integer('total_break_minutes')->nullable();
            $table->boolean('is_late')->default(false);
            $table->boolean('is_early_out')->default(false);
            $table->text('late_reason')->nullable();
            $table->text('early_out_reason')->nullable();
            $table->enum('status', ['on_time', 'pending', 'approved', 'rejected'])->default('on_time');
            $table->text('admin_notes')->nullable();
            $table->string('approved_by', 20)->nullable(); // admin mobile
            $table->dateTime('approved_at')->nullable();
            $table->timestamps();

            $table->unique(['employee_mobile', 'date']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('attendance_crm');
    }
};

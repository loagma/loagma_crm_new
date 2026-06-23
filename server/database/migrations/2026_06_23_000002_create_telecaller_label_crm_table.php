<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('telecaller_label_crm', function (Blueprint $table) {
            $table->id();
            $table->string('employee_mobile');
            $table->string('account_id');
            $table->enum('account_type', ['lead', 'customer']);
            $table->string('label', 50); // e.g. wrong_number, do_not_call
            $table->timestamps();

            $table->unique(['employee_mobile', 'account_id']);
            $table->index('employee_mobile');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('telecaller_label_crm');
    }
};

<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('call_scripts_crm', function (Blueprint $table) {
            $table->id();
            $table->string('employee_mobile');
            $table->string('title');
            $table->string('stage_label')->nullable();
            $table->json('lines');
            $table->integer('sort_order')->default(0);
            $table->timestamps();

            $table->index('employee_mobile');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('call_scripts_crm');
    }
};

<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('area_assign_crm', function (Blueprint $table) {
            $table->bigIncrements('id');
            $table->json('area_ids');
            $table->json('area_names');
            $table->unsignedBigInteger('employee_id')->unique();
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('area_assign_crm');
    }
};

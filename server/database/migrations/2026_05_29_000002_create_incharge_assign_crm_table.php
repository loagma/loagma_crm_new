<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('incharge_assign_crm', function (Blueprint $table) {
            $table->id();
            $table->unsignedBigInteger('head_incharge_id')->unique();
            $table->json('incharge_ids');
            $table->json('incharge_names');
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('incharge_assign_crm');
    }
};

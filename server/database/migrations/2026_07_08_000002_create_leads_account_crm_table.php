<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('LeadsAccount_crm', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->string('accountCode', 191)->unique();
            $table->string('businessName', 191)->nullable();
            $table->string('businessType', 191)->nullable();
            $table->string('businessSize', 191)->nullable();
            $table->string('personName', 191);
            $table->string('contactNumber', 191);
            $table->dateTime('dateOfBirth')->nullable();
            $table->string('customerStage', 191)->nullable();
            $table->string('funnelStage', 191)->nullable();
            $table->string('gstNumber', 191)->nullable();
            $table->string('panCard', 191)->nullable();
            $table->string('ownerImage', 191)->nullable();
            $table->string('shopImage', 191)->nullable();
            $table->boolean('isActive')->default(true);
            $table->string('pincode', 191)->nullable();
            $table->string('country', 191)->nullable();
            $table->string('state', 191)->nullable();
            $table->string('district', 191)->nullable();
            $table->string('city', 191)->nullable();
            $table->string('area', 191)->nullable();
            $table->string('address', 191)->nullable();
            $table->float('latitude')->nullable();
            $table->float('longitude')->nullable();
            $table->unsignedBigInteger('areaId')->nullable();
            $table->string('assignedToId', 191)->nullable();
            $table->json('assignedDays')->nullable();
            $table->string('createdById', 191)->nullable();
            $table->string('approvedById', 191)->nullable();
            $table->dateTime('approvedAt')->nullable();
            $table->boolean('isApproved')->default(false);
            $table->string('verificationNotes', 191)->nullable();
            $table->string('rejectionNotes', 191)->nullable();
            $table->timestamp('createdAt')->useCurrent();
            $table->timestamp('updatedAt')->useCurrent()->useCurrentOnUpdate();

            $table->index('businessType');
            $table->index('businessSize');
            $table->index('customerStage');
            $table->index('pincode');
            $table->index('isActive');
            $table->index('areaId');
            $table->index('assignedToId');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('LeadsAccount_crm');
    }
};

<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

// One representative point per pincode, used to order a telecaller's pincodes
// by real geography (pincode numbers say nothing about proximity). `geocoded`
// rows are the pincode's own location, looked up once (PincodeGeocoder) —
// customer coordinates are never used; `manual` rows are admin overrides and
// are never replaced by the geocoder. sample_count is unused (always 0).
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('pincode_geo_crm', function (Blueprint $table) {
            $table->string('pincode', 10)->primary();
            $table->double('lat');
            $table->double('lng');
            $table->string('source', 10)->default('derived'); // geocoded | manual (code always sets it)
            $table->unsignedInteger('sample_count')->default(0);
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('pincode_geo_crm');
    }
};

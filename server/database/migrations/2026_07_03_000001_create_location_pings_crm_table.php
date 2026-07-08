<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('location_pings_crm', function (Blueprint $table) {
            $table->id();
            $table->string('employee_mobile', 20); // references deli_staff.mobile
            $table->date('date');
            $table->decimal('lat', 10, 7);
            $table->decimal('lng', 10, 7);
            $table->decimal('accuracy', 8, 2)->nullable(); // meters
            $table->decimal('speed', 8, 2)->nullable();    // m/s, as reported by Geolocator
            $table->unsignedTinyInteger('battery')->nullable();
            $table->boolean('is_mock')->default(false);
            $table->dateTime('recorded_at'); // client-side capture time

            $table->index(['employee_mobile', 'date']);
            $table->index(['employee_mobile', 'recorded_at']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('location_pings_crm');
    }
};

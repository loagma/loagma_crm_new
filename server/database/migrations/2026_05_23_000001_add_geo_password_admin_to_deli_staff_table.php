<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('deli_staff', function (Blueprint $table) {
            if (!Schema::hasColumn('deli_staff', 'lat')) {
                $table->decimal('lat', 10, 7)->nullable()->after('state');
            }
            if (!Schema::hasColumn('deli_staff', 'lng')) {
                $table->decimal('lng', 10, 7)->nullable()->after('lat');
            }
            if (!Schema::hasColumn('deli_staff', 'password')) {
                $table->string('password')->nullable()->after('lng');
            }
            if (!Schema::hasColumn('deli_staff', 'admin_id')) {
                $table->unsignedBigInteger('admin_id')->nullable()->after('mobile');
            }
        });
    }

    public function down(): void
    {
        Schema::table('deli_staff', function (Blueprint $table) {
            $table->dropColumn(
                collect(['lat', 'lng', 'password', 'admin_id'])
                    ->filter(fn($col) => Schema::hasColumn('deli_staff', $col))
                    ->values()
                    ->all()
            );
        });
    }
};

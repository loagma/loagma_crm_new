<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Facades\DB;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('role_crm', function (Blueprint $table) {
            $table->id();
            $table->string('role_name', 50)->unique();
            $table->timestamps();
        });

        // Seed default roles
        DB::table('role_crm')->insert([
            ['role_name' => 'admin',        'created_at' => now(), 'updated_at' => now()],
            ['role_name' => 'manager',      'created_at' => now(), 'updated_at' => now()],
            ['role_name' => 'salesman',     'created_at' => now(), 'updated_at' => now()],
            ['role_name' => 'telecaller',   'created_at' => now(), 'updated_at' => now()],
            ['role_name' => 'incharge',     'created_at' => now(), 'updated_at' => now()],
            ['role_name' => 'head_incharge','created_at' => now(), 'updated_at' => now()],
        ]);
    }

    public function down(): void
    {
        Schema::dropIfExists('role_crm');
    }
};

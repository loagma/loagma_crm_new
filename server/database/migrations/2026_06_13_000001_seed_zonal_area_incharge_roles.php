<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

return new class extends Migration
{
    public function up(): void
    {
        DB::table('role_crm')->insertOrIgnore([
            ['role_name' => 'zonal_incharge', 'created_at' => now(), 'updated_at' => now()],
            ['role_name' => 'area_incharge',  'created_at' => now(), 'updated_at' => now()],
        ]);
    }

    public function down(): void
    {
        DB::table('role_crm')->whereIn('role_name', ['zonal_incharge', 'area_incharge'])->delete();
    }
};

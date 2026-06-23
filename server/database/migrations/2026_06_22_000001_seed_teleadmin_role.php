<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

return new class extends Migration
{
    public function up(): void
    {
        DB::table('role_crm')->insertOrIgnore([
            ['role_name' => 'teleadmin', 'created_at' => now(), 'updated_at' => now()],
        ]);
    }

    public function down(): void
    {
        DB::table('role_crm')->whereIn('role_name', ['teleadmin'])->delete();
    }
};

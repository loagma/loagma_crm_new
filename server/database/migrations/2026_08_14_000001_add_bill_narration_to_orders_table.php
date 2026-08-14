<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

// `orders` is a live table shared with the parent app, not owned by this one —
// so this only ever adds a nullable column (never rewrites existing rows), and
// guards on hasColumn in case the parent app adds it first.
return new class extends Migration
{
    public function up(): void
    {
        if (Schema::hasColumn('orders', 'bill_narration')) {
            return;
        }

        Schema::table('orders', function (Blueprint $table) {
            $table->string('bill_narration', 500)->nullable()->after('department');
        });
    }

    public function down(): void
    {
        if (!Schema::hasColumn('orders', 'bill_narration')) {
            return;
        }

        Schema::table('orders', function (Blueprint $table) {
            $table->dropColumn('bill_narration');
        });
    }
};

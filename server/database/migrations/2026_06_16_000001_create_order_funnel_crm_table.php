<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('order_funnel_crm', function (Blueprint $table) {
            $table->bigIncrements('id');
            $table->string('slug', 100)->unique();   // stable key e.g. 'placed_order'
            $table->string('name', 150);             // display label e.g. 'Placed order'
            $table->unsignedInteger('sort_order')->default(0);
            $table->boolean('is_active')->default(true);
            $table->timestamps();
        });

        // Seed default funnel stages (mirrors the Order Funnel UI)
        $now      = now();
        $defaults = [
            'Placed order',
            'Shop closed',
            'New customer',
            'Negotiation',
            'Next week',
            'Not interested',
            'Not buying',
            'Interested',
        ];

        $rows = [];
        foreach ($defaults as $i => $name) {
            $rows[] = [
                'slug'       => str_replace(' ', '_', strtolower($name)),
                'name'       => $name,
                'sort_order' => $i + 1,
                'is_active'  => true,
                'created_at' => $now,
                'updated_at' => $now,
            ];
        }
        DB::table('order_funnel_crm')->insert($rows);
    }

    public function down(): void
    {
        Schema::dropIfExists('order_funnel_crm');
    }
};

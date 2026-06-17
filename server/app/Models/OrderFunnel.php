<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class OrderFunnel extends Model
{
    protected $table = 'order_funnel_crm';

    protected $fillable = ['slug', 'name', 'sort_order', 'is_active'];

    protected $casts = [
        'is_active'  => 'boolean',
        'sort_order' => 'integer',
    ];
}

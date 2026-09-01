<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

/**
 * Salesman check-out stage lookup (was order_funnel_crm): Placed order,
 * Shop closed, Negotiation, Interested, ...
 */
class ActionLogStage extends Model
{
    protected $table = 'action_log_stage_crm';

    protected $fillable = ['slug', 'name', 'sort_order', 'is_active'];

    protected $casts = [
        'is_active'  => 'boolean',
        'sort_order' => 'integer',
    ];
}

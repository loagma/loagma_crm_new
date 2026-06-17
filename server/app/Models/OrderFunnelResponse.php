<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class OrderFunnelResponse extends Model
{
    protected $table = 'order_funnel_response_crm';

    protected $fillable = [
        'employee_mobile',
        'account_id',
        'account_type',
        'beat_plan_id',
        'visit_in_at',
        'visit_out_at',
        'duration_seconds',
        'funnel_slug',
        'funnel_name',
        'general_notes',
        'notes_related_to',
        'images',
    ];

    protected $casts = [
        'visit_in_at'  => 'datetime',
        'visit_out_at' => 'datetime',
        'images'       => 'array',
    ];
}

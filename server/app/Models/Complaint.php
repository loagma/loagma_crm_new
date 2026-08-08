<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class Complaint extends Model
{
    protected $table = 'complaint_crm';

    protected $fillable = [
        'account_id',
        'account_type',
        'source_channel',
        'raised_by',
        'assigned_to',
        'assigned_by',
        'assigned_at',
        'call_log_id',
        'beat_plan_id',
        'category',
        'description',
        'status',
        'resolution_notes',
        'resolved_by',
        'resolved_at',
    ];

    protected $casts = [
        'assigned_at' => 'datetime',
        'resolved_at' => 'datetime',
    ];
}

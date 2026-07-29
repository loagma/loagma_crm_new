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
        'resolved_at' => 'datetime',
    ];
}

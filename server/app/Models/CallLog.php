<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class CallLog extends Model
{
    protected $table = 'call_log_crm';

    protected $fillable = [
        'employee_mobile',
        'source',
        'direction',
        'knowlarity_call_id',
        'account_id',
        'account_type',
        'call_outcome',
        'notes',
        'follow_up_date',
        'called_at',
        'callback_done',
        'duration_seconds',
        'recording_url',
        'raw_payload',
    ];

    protected $casts = [
        'follow_up_date' => 'date:Y-m-d', // plain day — default UTC-Z serialization shifts IST dates a day back
        'called_at'      => 'datetime',
        'callback_done'  => 'boolean',
        'raw_payload'    => 'array',
    ];
}

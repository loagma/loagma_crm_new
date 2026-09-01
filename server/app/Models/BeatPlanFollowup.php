<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class BeatPlanFollowup extends Model
{
    protected $table = 'beat_plan_followup_crm';

    protected $fillable = [
        'account_id',
        'account_type',
        'staff_id',
        'due_date',
        'note',
        'source_action_log_id',
        'done',
        'done_at',
    ];

    protected $casts = [
        'due_date' => 'date:Y-m-d',
        'done'     => 'boolean',
        'done_at'  => 'datetime',
    ];
}

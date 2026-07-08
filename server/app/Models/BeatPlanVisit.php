<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class BeatPlanVisit extends Model
{
    protected $table = 'beat_plan_visit_crm';

    protected $fillable = [
        'beat_plan_id',
        'account_id',
        'salesman_id',
        'visit_date',
        'status',
        'notes',
    ];

    protected $casts = [
        'visit_date' => 'date:Y-m-d', // plain day — default UTC-Z serialization shifts IST dates a day back
    ];

    public function beatPlan(): BelongsTo
    {
        return $this->belongsTo(BeatPlan::class, 'beat_plan_id');
    }

    public function account(): BelongsTo
    {
        return $this->belongsTo(LeadsAccount::class, 'account_id', 'id');
    }
}

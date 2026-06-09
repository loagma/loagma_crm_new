<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\HasMany;

class BeatPlan extends Model
{
    protected $table = 'beat_plan_crm';

    protected $fillable = [
        'account_id',
        'account_type',
        'salesman_id',
        'frequency',
        'days',
        'month_date',
        'specific_dates',
        'appointment_date',
        'interval_days',
        'start_date',
        'is_active',
    ];

    protected $casts = [
        'days'              => 'array',
        'month_date'        => 'integer',
        'specific_dates'    => 'array',
        'appointment_date'  => 'datetime',
        'interval_days'     => 'integer',
        'start_date'        => 'date',
        'is_active'         => 'boolean',
    ];

    public function visits(): HasMany
    {
        return $this->hasMany(BeatPlanVisit::class, 'beat_plan_id');
    }

    /**
     * Whether this plan fires on a given Carbon date.
     */
    public function firesOn(\Carbon\Carbon $date): bool
    {
        return match ($this->frequency) {
            'weekly'  => in_array($date->shortDayName, $this->days ?? []),
            'monthly' => $this->month_date === $date->day,
            'specific_dates' => in_array($date->format('Y-m-d'), $this->specific_dates ?? []),
            'appointment' => $this->appointment_date !== null
                           && $this->appointment_date->format('Y-m-d') === $date->format('Y-m-d'),
            'n_days'  => $this->start_date !== null
                         && $this->interval_days > 0
                         && $date->diffInDays($this->start_date) % $this->interval_days === 0,
            default   => false,
        };
    }
}

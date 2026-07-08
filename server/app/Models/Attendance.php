<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class Attendance extends Model
{
    protected $table = 'attendance_crm';

    protected $fillable = [
        'employee_mobile',
        'date',
        'punch_in_time',
        'punch_in_photo',
        'punch_in_location',
        'punch_out_time',
        'punch_out_photo',
        'punch_out_location',
        'break_details',
        'total_work_minutes',
        'total_break_minutes',
        'is_late',
        'is_early_out',
        'is_early_in',
        'late_reason',
        'early_out_reason',
        'early_in_reason',
        'status',
        'admin_notes',
        'approved_by',
        'approved_at',
        'last_ping_at',
        'was_interrupted',
        'auto_closed',
    ];

    protected $casts = [
        'break_details'      => 'array',
        'punch_in_location'  => 'array',
        'punch_out_location' => 'array',
        'is_late'            => 'boolean',
        'is_early_out'       => 'boolean',
        'is_early_in'        => 'boolean',
        'was_interrupted'    => 'boolean',
        'auto_closed'        => 'boolean',
        'punch_in_time'      => 'datetime',
        'punch_out_time'     => 'datetime',
        'approved_at'        => 'datetime',
        'last_ping_at'       => 'datetime',
        'date'               => 'date:Y-m-d', // plain day — default UTC-Z serialization shifts IST dates a day back
    ];

    public function employee(): BelongsTo
    {
        return $this->belongsTo(DeliStaff::class, 'employee_mobile', 'mobile');
    }
}

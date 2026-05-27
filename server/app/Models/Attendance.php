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
        'punch_out_time',
        'break_details',
        'total_work_minutes',
        'total_break_minutes',
        'is_late',
        'is_early_out',
        'late_reason',
        'early_out_reason',
        'status',
        'admin_notes',
        'approved_by',
        'approved_at',
    ];

    protected $casts = [
        'break_details'  => 'array',
        'is_late'        => 'boolean',
        'is_early_out'   => 'boolean',
        'punch_in_time'  => 'datetime',
        'punch_out_time' => 'datetime',
        'approved_at'    => 'datetime',
        'date'           => 'date',
    ];

    public function employee(): BelongsTo
    {
        return $this->belongsTo(DeliStaff::class, 'employee_mobile', 'mobile');
    }
}

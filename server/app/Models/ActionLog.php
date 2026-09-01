<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * One "worked this customer" record (was order_funnel_response_crm) — written
 * at Check Out by the Action Log popup. Holds the visit timing + GPS, and the
 * role-specific output (salesman stage/payment/market note, or telecaller call
 * outcome/conversation notes). Telecaller rows link to the Knowlarity
 * call_log_crm row via call_log_id for the recording.
 */
class ActionLog extends Model
{
    protected $table = 'action_log_crm';

    protected $fillable = [
        'employee_mobile',
        'role',
        'account_id',
        'account_type',
        'beat_plan_id',
        'check_in_at',
        'check_in_lat',
        'check_in_lng',
        'check_out_at',
        'check_out_lat',
        'check_out_lng',
        'duration_seconds',
        'status',
        'outcome_slug',
        'outcome_name',
        'order_no',
        'general_notes',
        'notes_related_to',
        'images',
        // telecaller
        'call_outcome',
        'call_status',
        'is_invalid_call',
        'call_log_id',
        'conversation_notes',
        'discussion_points',
        'customer_stage',
        'funnel_stage',
        // salesman
        'payment_collected',
        'payment_mode',
        'market_note',
        // shared
        'follow_up_date',
        'follow_up_note',
    ];

    protected $casts = [
        'check_in_at'      => 'datetime',
        'check_out_at'     => 'datetime',
        'follow_up_date'   => 'date:Y-m-d',
        'is_invalid_call'  => 'boolean',
        'images'           => 'array',
        'payment_collected' => 'decimal:2',
    ];

    public function callLog(): BelongsTo
    {
        return $this->belongsTo(CallLog::class, 'call_log_id');
    }
}

<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class TcAllocationItem extends Model
{
    protected $table = 'tc_allocation_item_crm';

    protected $fillable = [
        'plan_id', 'employee_mobile', 'account_id', 'account_type', 'pincode',
        'pincode_rank', 'account_rank', 'status', 'allocated_date', 'call_log_id', 'completed_at',
    ];

    protected $casts = [
        'pincode_rank'   => 'integer',
        'account_rank'   => 'integer',
        'allocated_date' => 'date:Y-m-d', // plain IST day — default UTC-Z serialization shifts it a day back
        'completed_at'   => 'datetime',
    ];
}

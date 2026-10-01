<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class TcAllocationPlan extends Model
{
    protected $table = 'tc_allocation_plan_crm';

    protected $fillable = [
        'employee_mobile', 'selected_pincodes', 'pincode_sequence', 'daily_capacity',
        'start_date', 'end_date', 'status',
    ];

    protected $casts = [
        'selected_pincodes' => 'array',
        'pincode_sequence'  => 'array',
        'daily_capacity'    => 'integer',
        'start_date'        => 'date:Y-m-d', // plain IST days — default UTC-Z serialization shifts them a day back
        'end_date'          => 'date:Y-m-d',
    ];
}

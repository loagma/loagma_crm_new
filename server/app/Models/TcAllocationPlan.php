<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class TcAllocationPlan extends Model
{
    protected $table = 'tc_allocation_plan_crm';

    protected $fillable = ['employee_mobile', 'selected_pincodes', 'pincode_sequence', 'daily_capacity', 'status'];

    protected $casts = [
        'selected_pincodes' => 'array',
        'pincode_sequence'  => 'array',
        'daily_capacity'    => 'integer',
    ];
}

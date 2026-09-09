<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class CustomerAssign extends Model
{
    protected $table = 'customer_assign_crm';

    protected $fillable = [
        'customer_userid',
        'employee_mobile',
        'assigned_by',
    ];

    protected $casts = [
        'customer_userid' => 'integer',
    ];
}

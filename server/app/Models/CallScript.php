<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class CallScript extends Model
{
    protected $table = 'call_scripts_crm';

    protected $fillable = [
        'employee_mobile',
        'title',
        'stage_label',
        'lines',
        'sort_order',
    ];

    protected $casts = [
        'lines'      => 'array',
        'sort_order' => 'integer',
    ];
}

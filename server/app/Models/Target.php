<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class Target extends Model
{
    protected $table = 'target_crm';

    protected $fillable = ['telecaller_id', 'period', 'call_target', 'conversion_target'];

    protected $casts = [
        'call_target'       => 'integer',
        'conversion_target' => 'integer',
    ];
}

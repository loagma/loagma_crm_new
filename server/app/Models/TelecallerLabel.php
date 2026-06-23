<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class TelecallerLabel extends Model
{
    protected $table = 'telecaller_label_crm';

    protected $fillable = [
        'employee_mobile',
        'account_id',
        'account_type',
        'label',
    ];
}

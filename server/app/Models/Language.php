<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class Language extends Model
{
    protected $table = 'language_crm';

    protected $fillable = ['name', 'code', 'is_active', 'sort_order'];

    protected $casts = ['is_active' => 'boolean'];
}

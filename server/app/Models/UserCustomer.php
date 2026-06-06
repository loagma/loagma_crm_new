<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class UserCustomer extends Model
{
    protected $table = 'user';
    protected $primaryKey = 'userid';
    public $timestamps = false;

    protected $fillable = [
        'name',
        'email',
        'contactno',
        'shop_name',
        'shop_address',
        'address',
        'pincode',
        'city',
        'state',
        'latitude',
        'longitude',
        'user_type',
        'is_approved',
        'account_state',
    ];
}

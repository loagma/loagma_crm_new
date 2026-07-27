<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class UserCustomer extends Model
{
    protected $table = 'user';
    protected $primaryKey = 'userid';
    public $timestamps = false;
    // `userid` has no AUTO_INCREMENT on this shared table — Eloquent must
    // not overwrite our explicitly-assigned id with lastInsertId() (which
    // would be 0 here since MySQL never generated one).
    public $incrementing = false;

    protected $fillable = [
        'userid',
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
        'lead_account_id',
        'session_id',
        'push_notif_id',
    ];
}

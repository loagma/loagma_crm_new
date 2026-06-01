<?php

namespace App\Models;

use Illuminate\Foundation\Auth\User as Authenticatable;
use Tymon\JWTAuth\Contracts\JWTSubject;

class DeliStaff extends Authenticatable implements JWTSubject
{
    protected $table = 'deli_staff';
    protected $primaryKey = 'mobile';
    public $incrementing = false;
    protected $keyType = 'string';
    public $timestamps = false;

    protected $fillable = [
        'admin_id',
        'name',
        'mobile',
        'role',
        'otp',
        'otp_expires_at',
        'pincode',
        'city',
        'state',
        'lat',
        'lng',
        'is_locked',
        'punch_in_time',
        'punch_out_time',
        'grace_minutes',
        'approval_required',
    ];

    protected $hidden = ['password', 'sess_id', 'otp', 'otp_expires_at'];

    protected $casts = [
        'otp_expires_at'         => 'datetime',
        'location_last_updated'  => 'datetime',
        'lat'                    => 'float',
        'lng'                    => 'float',
        'is_locked'              => 'boolean',
        'approval_required'      => 'boolean',
    ];

    public function getJWTIdentifier(): mixed
    {
        return $this->getKey();
    }

    public function getJWTCustomClaims(): array
    {
        return ['role' => $this->role];
    }
}

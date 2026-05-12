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
        'name',
        'mobile',
        'role',
        'otp',
        'otp_expires_at',
    ];

    protected $hidden = ['otp', 'otp_expires_at'];

    protected $casts = [
        'otp_expires_at' => 'datetime',
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

<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class PincodeGeo extends Model
{
    protected $table = 'pincode_geo_crm';
    protected $primaryKey = 'pincode';
    public $incrementing = false;
    protected $keyType = 'string';

    protected $fillable = ['pincode', 'lat', 'lng', 'source'];

    protected $casts = [
        'lat'          => 'float',
        'lng'          => 'float',
    ];
}

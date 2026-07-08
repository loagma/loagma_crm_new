<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class LocationPing extends Model
{
    protected $table = 'location_pings_crm';

    public $timestamps = false;

    protected $fillable = [
        'employee_mobile',
        'date',
        'lat',
        'lng',
        'accuracy',
        'speed',
        'heading',
        'battery',
        'is_mock',
        'recorded_at',
    ];

    protected $casts = [
        'lat'         => 'float',
        'lng'         => 'float',
        'accuracy'    => 'float',
        'speed'       => 'float',
        'heading'     => 'float',
        'battery'     => 'integer',
        'is_mock'     => 'boolean',
        'recorded_at' => 'datetime',
        'date'        => 'date',
    ];

    public function employee(): BelongsTo
    {
        return $this->belongsTo(DeliStaff::class, 'employee_mobile', 'mobile');
    }
}

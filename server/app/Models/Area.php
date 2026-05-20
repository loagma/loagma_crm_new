<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class Area extends Model
{
    protected $table = 'area_crm';

    protected $fillable = [
        'area_name',
        'pincodes',
    ];

    protected $casts = [
        'pincodes' => 'array',
    ];

    public function toArray(): array
    {
        $data = parent::toArray();
        $data['id'] = (int) ($data['id'] ?? 0);
        $data['area_name'] = (string) ($data['area_name'] ?? '');
        $pins = $data['pincodes'] ?? [];
        $data['pincodes'] = is_array($pins)
            ? array_values(array_map(fn ($p) => (string) $p, $pins))
            : [];
        return $data;
    }
}


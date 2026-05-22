<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class AreaAssign extends Model
{
    protected $table = 'area_assign_crm';

    protected $fillable = [
        'area_ids',
        'area_names',
        'employee_id',
    ];

    protected $casts = [
        'area_ids'    => 'array',
        'area_names'  => 'array',
        'employee_id' => 'integer',
    ];

    public function toArray(): array
    {
        $data = parent::toArray();
        $data['id']          = (int) ($data['id'] ?? 0);
        $data['employee_id'] = (int) ($data['employee_id'] ?? 0);
        $data['area_ids']    = array_values(array_map('intval', $data['area_ids'] ?? []));
        $data['area_names']  = array_values(array_map('strval', $data['area_names'] ?? []));
        return $data;
    }
}

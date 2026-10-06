<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class InchargeAssign extends Model
{
    protected $table = 'incharge_assign_crm';

    protected $fillable = [
        'head_incharge_id',
        'incharge_ids',
        'incharge_names',
    ];

    protected $casts = [
        'head_incharge_id' => 'string', // staff mobile, varchar(20) like deli_staff.mobile (API still returns it as a number — see toArray)
        'incharge_ids'     => 'array',
        'incharge_names'   => 'array',
    ];

    public function toArray(): array
    {
        $data = parent::toArray();
        $data['id']               = (int) ($data['id'] ?? 0);
        $data['head_incharge_id'] = (int) ($data['head_incharge_id'] ?? 0);
        $data['incharge_ids']     = array_values(array_map('intval', $data['incharge_ids'] ?? []));
        $data['incharge_names']   = array_values(array_map('strval', $data['incharge_names'] ?? []));
        return $data;
    }
}

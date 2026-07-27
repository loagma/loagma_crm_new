<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

class LeadsAccount extends Model
{
    protected $table      = 'LeadsAccount_crm';
    protected $primaryKey = 'id';
    public    $keyType    = 'string';
    public    $incrementing = false;

    const CREATED_AT = 'createdAt';
    const UPDATED_AT = 'updatedAt';

    protected $fillable = [
        'accountCode',
        'businessName',
        'businessType',
        'businessSize',
        'personName',
        'contactNumber',
        'dateOfBirth',
        'customerStage',
        'funnelStage',
        'gstNumber',
        'panCard',
        'ownerImage',
        'shopImage',
        'isActive',
        'pincode',
        'country',
        'state',
        'district',
        'city',
        'area',
        'address',
        'latitude',
        'longitude',
        'areaId',
        'assignedToId',
        'assignedDays',
        'createdById',
        'approvedById',
        'approvedAt',
        'isApproved',
        'approval_status',
        'verificationNotes',
        'rejectionNotes',
    ];

    protected $casts = [
        'dateOfBirth'  => 'datetime',
        'approvedAt'   => 'datetime',
        'isActive'     => 'boolean',
        'isApproved'   => 'boolean',
        'assignedDays' => 'array',
        'latitude'     => 'float',
        'longitude'    => 'float',
        'areaId'       => 'integer',
    ];

    protected static function boot(): void
    {
        parent::boot();

        static::creating(function (self $model) {
            if (empty($model->id)) {
                $model->id = Str::uuid()->toString();
            }
            if (empty($model->accountCode)) {
                $maxNumeric = DB::table($model->getTable())
                    ->whereRaw("accountCode REGEXP '^[0-9]+$'")
                    ->selectRaw('MAX(CAST(accountCode AS UNSIGNED)) as max_code')
                    ->value('max_code');

                $next = ((int) $maxNumeric) > 0 ? ((int) $maxNumeric) + 1 : 1001;
                $model->accountCode = (string) $next;
            }
            if (!isset($model->isActive)) {
                $model->isActive = true;
            }
            // approval_status defaults to 'pending' via the column default;
            // isApproved is left unset until a real approve/reject decision
            // is made, so it no longer falsely reads as "rejected" from birth.
        });
    }

    // Staff member who created this lead (createdById stores their mobile,
    // matching every other staff-attribution field in this app).
    public function creator(): BelongsTo
    {
        return $this->belongsTo(DeliStaff::class, 'createdById', 'mobile');
    }
}

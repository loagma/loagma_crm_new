<?php

namespace App\Support;

use Illuminate\Support\Facades\DB;

/**
 * deli_staff is shared with the delivery/billing apps (drivers, cashiers,
 * counter staff… all with passwords). Only staff whose role is a CRM role
 * (a row in role_crm) may log in to — or keep using — the CRM.
 */
class CrmAccess
{
    private static ?array $roles = null;

    public static function allows(?string $role): bool
    {
        $role = strtolower(trim((string) $role));
        if ($role === '') {
            return false;
        }
        self::$roles ??= DB::table('role_crm')->pluck('role_name')
            ->map(fn ($r) => strtolower(trim((string) $r)))->all();

        return \in_array($role, self::$roles, true);
    }
}

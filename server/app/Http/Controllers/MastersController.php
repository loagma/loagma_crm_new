<?php

namespace App\Http\Controllers;

use App\Models\DeliStaff;
use Illuminate\Http\JsonResponse;

class MastersController extends Controller
{
    public function roles(): JsonResponse
    {
        $roles = DeliStaff::select('role')
            ->distinct()
            ->whereNotNull('role')
            ->orderBy('role')
            ->get()
            ->map(fn ($r) => ['name' => $r->role, 'label' => ucfirst($r->role)]);

        return response()->json([
            'success' => true,
            'data'    => $roles,
        ]);
    }
}

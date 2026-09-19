<?php

namespace App\Http\Controllers;

use App\Models\DeliStaff;
use App\Models\Target;
use Illuminate\Http\JsonResponse;
use Tymon\JWTAuth\Facades\JWTAuth;

class TargetController extends Controller
{
    // GET /api/targets?period=2026-09 (admin/teleadmin) — one row per
    // telecaller for the period, defaulting unset targets to zero so the
    // Admin Targets screen can render every telecaller even before a target
    // has ever been set for them.
    public function index(): JsonResponse
    {
        $period = request()->query('period', now()->format('Y-m'));

        $telecallers = DeliStaff::whereRaw('LOWER(TRIM(role)) = ?', ['telecaller'])
            ->orderBy('name')
            ->get(['mobile', 'name']);

        $targets = Target::where('period', $period)
            ->get()
            ->keyBy('telecaller_id');

        $data = $telecallers->map(function ($t) use ($targets, $period) {
            $target = $targets->get($t->mobile);
            return [
                'telecaller_id'     => $t->mobile,
                'name'              => $t->name,
                'period'            => $period,
                'call_target'       => $target->call_target ?? 0,
                'conversion_target' => $target->conversion_target ?? 0,
            ];
        });

        return response()->json(['success' => true, 'data' => $data]);
    }

    // POST /api/targets (admin/teleadmin) — upsert one telecaller's target
    // for a period. body: {telecaller_id, period, call_target, conversion_target}
    public function store(): JsonResponse
    {
        $validated = validator(request()->only('telecaller_id', 'period', 'call_target', 'conversion_target'), [
            'telecaller_id'     => 'required|string|max:191',
            'period'            => 'required|string|max:20',
            'call_target'       => 'required|integer|min:0',
            'conversion_target' => 'required|integer|min:0',
        ])->validate();

        $target = Target::updateOrCreate(
            ['telecaller_id' => $validated['telecaller_id'], 'period' => $validated['period']],
            ['call_target' => $validated['call_target'], 'conversion_target' => $validated['conversion_target']]
        );

        return response()->json(['success' => true, 'data' => $target]);
    }

    // GET /api/targets/mine?period=2026-09 — the logged-in telecaller's own
    // target, for their "my scorecard" view. Defaults to zero if never set.
    public function mine(): JsonResponse
    {
        $mobile = JWTAuth::parseToken()->authenticate()->mobile;
        $period = request()->query('period', now()->format('Y-m'));

        $target = Target::where('telecaller_id', $mobile)->where('period', $period)->first();

        return response()->json([
            'success' => true,
            'data'    => [
                'telecaller_id'     => $mobile,
                'period'            => $period,
                'call_target'       => $target->call_target ?? 0,
                'conversion_target' => $target->conversion_target ?? 0,
            ],
        ]);
    }
}

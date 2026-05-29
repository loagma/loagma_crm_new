<?php

namespace App\Http\Controllers;

use App\Models\InchargeAssign;
use Illuminate\Http\JsonResponse;

class InchargeAssignController extends Controller
{
    public function index(): JsonResponse
    {
        $assigns = InchargeAssign::all();
        return response()->json([
            'success' => true,
            'data'    => $assigns->map(fn ($a) => $a->toArray())->values(),
        ]);
    }

    public function show(string $headInchargeId): JsonResponse
    {
        $assign = InchargeAssign::where('head_incharge_id', (int) $headInchargeId)->first();
        return response()->json([
            'success' => true,
            'data'    => $assign ? $assign->toArray() : null,
        ]);
    }

    public function save(string $headInchargeId): JsonResponse
    {
        $validated = validator(request()->all(), [
            'incharge_ids'     => 'required|array',
            'incharge_ids.*'   => 'integer',
            'incharge_names'   => 'required|array',
            'incharge_names.*' => 'string|max:255',
        ])->validate();

        $assign = InchargeAssign::updateOrCreate(
            ['head_incharge_id' => (int) $headInchargeId],
            [
                'incharge_ids'   => array_values(array_map('intval',  $validated['incharge_ids'])),
                'incharge_names' => array_values(array_map('strval', $validated['incharge_names'])),
            ]
        );

        return response()->json([
            'success' => true,
            'data'    => $assign->toArray(),
        ], $assign->wasRecentlyCreated ? 201 : 200);
    }

    public function destroy(string $headInchargeId): JsonResponse
    {
        $deleted = InchargeAssign::where('head_incharge_id', (int) $headInchargeId)->delete();
        return response()->json([
            'success' => (bool) $deleted,
            'message' => $deleted ? 'Assignment removed' : 'No assignment found',
        ]);
    }
}

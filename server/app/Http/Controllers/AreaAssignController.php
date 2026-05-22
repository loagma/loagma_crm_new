<?php

namespace App\Http\Controllers;

use App\Models\AreaAssign;
use Illuminate\Http\JsonResponse;

class AreaAssignController extends Controller
{
    public function index(): JsonResponse
    {
        $assigns = AreaAssign::all();
        return response()->json([
            'success' => true,
            'data'    => $assigns->map(fn ($a) => $a->toArray())->values(),
        ]);
    }

    public function show(string $employeeId): JsonResponse
    {
        $assign = AreaAssign::where('employee_id', (int) $employeeId)->first();

        return response()->json([
            'success' => true,
            'data'    => $assign ? $assign->toArray() : null,
        ]);
    }

    public function save(string $employeeId): JsonResponse
    {
        $validated = validator(request()->all(), [
            'area_ids'     => 'required|array',
            'area_ids.*'   => 'integer',
            'area_names'   => 'required|array',
            'area_names.*' => 'string|max:255',
        ])->validate();

        $assign = AreaAssign::updateOrCreate(
            ['employee_id' => (int) $employeeId],
            [
                'area_ids'   => array_values(array_map('intval', $validated['area_ids'])),
                'area_names' => array_values(array_map('strval', $validated['area_names'])),
            ]
        );

        return response()->json([
            'success' => true,
            'data'    => $assign->toArray(),
        ], $assign->wasRecentlyCreated ? 201 : 200);
    }

    public function destroy(string $employeeId): JsonResponse
    {
        $deleted = AreaAssign::where('employee_id', (int) $employeeId)->delete();

        return response()->json([
            'success' => (bool) $deleted,
            'message' => $deleted ? 'Assignment removed' : 'No assignment found',
        ]);
    }
}

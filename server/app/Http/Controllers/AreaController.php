<?php

namespace App\Http\Controllers;

use App\Models\Area;
use Illuminate\Http\JsonResponse;

class AreaController extends Controller
{
    public function index(): JsonResponse
    {
        $q = trim((string) request()->query('q', ''));
        $perPage = (int) request()->query('per_page', 20);
        $query = Area::query()->orderByDesc('id');

        if ($q !== '') {
            $query->where('area_name', 'like', "%{$q}%");
        }

        if (request()->has('page')) {
            $page = (int) request()->query('page', 1);
            $p = $query->paginate($perPage, ['*'], 'page', $page);
            return response()->json([
                'success' => true,
                'data' => array_map(fn ($a) => $a->toArray(), $p->items()),
                'meta' => [
                    'current_page' => $p->currentPage(),
                    'last_page' => $p->lastPage(),
                    'per_page' => $p->perPage(),
                    'total' => $p->total(),
                ],
            ]);
        }

        return response()->json([
            'success' => true,
            'data' => $query->get()->map(fn (Area $a) => $a->toArray())->values(),
        ]);
    }

    public function show(int $id): JsonResponse
    {
        $area = Area::find($id);
        if (!$area) {
            return response()->json(['success' => false, 'message' => 'Area not found'], 404);
        }
        return response()->json(['success' => true, 'data' => $area->toArray()]);
    }

    public function store(): JsonResponse
    {
        $validated = validator(request()->all(), [
            'area_name' => 'required|string|max:255',
            'pincodes' => 'nullable|array',
            'pincodes.*' => ['string', 'regex:/^\d{6}$/'],
        ])->validate();

        $name = trim((string) ($validated['area_name'] ?? ''));
        $pins = $this->normalizePincodes($validated['pincodes'] ?? []);

        $area = Area::create([
            'area_name' => $name,
            'pincodes' => $pins,
        ]);

        return response()->json(['success' => true, 'data' => $area->toArray()], 201);
    }

    public function update(int $id): JsonResponse
    {
        $area = Area::find($id);
        if (!$area) {
            return response()->json(['success' => false, 'message' => 'Area not found'], 404);
        }

        $validated = validator(request()->all(), [
            'area_name' => 'sometimes|required|string|max:255',
            'pincodes' => 'sometimes|array',
            'pincodes.*' => ['string', 'regex:/^\d{6}$/'],
        ])->validate();

        if (array_key_exists('area_name', $validated)) {
            $area->area_name = trim((string) $validated['area_name']);
        }
        if (array_key_exists('pincodes', $validated)) {
            $area->pincodes = $this->normalizePincodes($validated['pincodes'] ?? []);
        }
        $area->save();

        return response()->json(['success' => true, 'data' => $area->toArray()]);
    }

    public function destroy(int $id): JsonResponse
    {
        $area = Area::find($id);
        if (!$area) {
            return response()->json(['success' => false, 'message' => 'Area not found'], 404);
        }
        $area->delete();
        return response()->json(['success' => true, 'message' => 'Area deleted']);
    }

    public function addPincodes(int $id): JsonResponse
    {
        $area = Area::find($id);
        if (!$area) {
            return response()->json(['success' => false, 'message' => 'Area not found'], 404);
        }

        $validated = validator(request()->all(), [
            'pincode' => ['nullable', 'string', 'regex:/^\d{6}$/'],
            'pincodes' => 'nullable|array',
            'pincodes.*' => ['string', 'regex:/^\d{6}$/'],
        ])->validate();

        $incoming = [];
        if (!empty($validated['pincode'])) {
            $incoming[] = (string) $validated['pincode'];
        }
        if (!empty($validated['pincodes']) && is_array($validated['pincodes'])) {
            $incoming = array_merge($incoming, $validated['pincodes']);
        }
        $incoming = $this->normalizePincodes($incoming);

        if (empty($incoming)) {
            return response()->json(['success' => false, 'message' => 'No pincode provided'], 422);
        }

        $current = $this->normalizePincodes($area->pincodes ?? []);
        $merged = array_values(array_unique(array_merge($current, $incoming)));
        sort($merged);
        $area->pincodes = $merged;
        $area->save();

        return response()->json(['success' => true, 'data' => $area->toArray()]);
    }

    public function updatePincode(int $id, string $pincode): JsonResponse
    {
        $area = Area::find($id);
        if (!$area) {
            return response()->json(['success' => false, 'message' => 'Area not found'], 404);
        }

        $validated = validator(request()->all(), [
            'new_pincode' => ['required', 'string', 'regex:/^\d{6}$/'],
        ])->validate();

        if (!preg_match('/^\d{6}$/', $pincode)) {
            return response()->json(['success' => false, 'message' => 'Invalid source pincode'], 422);
        }

        $pins = $this->normalizePincodes($area->pincodes ?? []);
        $idx = array_search($pincode, $pins, true);
        if ($idx === false) {
            return response()->json(['success' => false, 'message' => 'Pincode not found'], 404);
        }

        $pins[$idx] = (string) $validated['new_pincode'];
        $pins = array_values(array_unique($pins));
        sort($pins);
        $area->pincodes = $pins;
        $area->save();

        return response()->json(['success' => true, 'data' => $area->toArray()]);
    }

    public function deletePincode(int $id, string $pincode): JsonResponse
    {
        $area = Area::find($id);
        if (!$area) {
            return response()->json(['success' => false, 'message' => 'Area not found'], 404);
        }

        $pins = $this->normalizePincodes($area->pincodes ?? []);
        $before = count($pins);
        $pins = array_values(array_filter($pins, fn ($p) => $p !== $pincode));
        if (count($pins) === $before) {
            return response()->json(['success' => false, 'message' => 'Pincode not found'], 404);
        }

        $area->pincodes = $pins;
        $area->save();

        return response()->json(['success' => true, 'data' => $area->toArray()]);
    }

    private function normalizePincodes(array $pins): array
    {
        $clean = array_map(fn ($p) => trim((string) $p), $pins);
        $clean = array_filter($clean, fn ($p) => preg_match('/^\d{6}$/', $p) === 1);
        $clean = array_values(array_unique($clean));
        sort($clean);
        return $clean;
    }
}

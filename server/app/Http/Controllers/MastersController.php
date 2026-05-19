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

    public function employees(): JsonResponse
    {
        $q       = request()->query('q', null);
        $perPage = (int) request()->query('per_page', 20);

        $query = DeliStaff::select(
            'deli_id', 'mobile', 'name', 'role',
            'city', 'state', 'pincode', 'is_locked'
        )->orderBy('name');

        if ($q) {
            $query->where(function ($sub) use ($q) {
                $sub->where('name',   'like', "%{$q}%")
                    ->orWhere('role',   'like', "%{$q}%")
                    ->orWhere('mobile', 'like', "%{$q}%")
                    ->orWhere('city',   'like', "%{$q}%");
            });
        }

        if (request()->has('page')) {
            $page = (int) request()->query('page', 1);
            $p    = $query->paginate($perPage, ['*'], 'page', $page);

            return response()->json([
                'success' => true,
                'data'    => $p->items(),
                'meta'    => [
                    'current_page' => $p->currentPage(),
                    'last_page'    => $p->lastPage(),
                    'per_page'     => $p->perPage(),
                    'total'        => $p->total(),
                ],
            ]);
        }

        return response()->json([
            'success' => true,
            'data'    => $query->get(),
        ]);
    }

    public function show($id): JsonResponse
    {
        $staff = DeliStaff::where('mobile', $id)->first();
        if (!$staff) {
            return response()->json(['success' => false, 'message' => 'Not found'], 404);
        }

        return response()->json(['success' => true, 'data' => $staff]);
    }

    public function store(): JsonResponse
    {
        $data = request()->only([
            'name', 'mobile', 'role',
            'pincode', 'city', 'state',
            'is_locked', 'admin_id',
        ]);

        $validated = validator($data, [
            'name'      => 'required|string|max:255',
            'mobile'    => 'required|string|max:20',
            'role'      => 'nullable|string|max:20',
            'pincode'   => 'nullable|string|max:20',
            'city'      => 'nullable|string|max:100',
            'state'     => 'nullable|string|max:100',
            'is_locked' => 'nullable|boolean',
            'admin_id'  => 'nullable|integer',
        ])->validate();

        $staff = DeliStaff::updateOrCreate(
            ['mobile' => $validated['mobile']],
            collect($validated)->except('mobile')->toArray()
        );

        return response()->json(['success' => true, 'data' => $staff]);
    }

    public function update($id): JsonResponse
    {
        $data = request()->only([
            'name', 'role',
            'pincode', 'city', 'state',
            'is_locked',
        ]);

        $validated = validator($data, [
            'name'      => 'required|string|max:255',
            'role'      => 'nullable|string|max:20',
            'pincode'   => 'nullable|string|max:20',
            'city'      => 'nullable|string|max:100',
            'state'     => 'nullable|string|max:100',
            'is_locked' => 'nullable|boolean',
        ])->validate();

        $staff = DeliStaff::where('mobile', $id)->first();
        if (!$staff) {
            return response()->json(['success' => false, 'message' => 'Not found'], 404);
        }

        $staff->fill($validated)->save();

        return response()->json(['success' => true, 'data' => $staff]);
    }
}

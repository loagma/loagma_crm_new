<?php

namespace App\Http\Controllers;

use App\Models\DeliStaff;
use App\Models\RoleCrm;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

class MastersController extends Controller
{
    public function roles(): JsonResponse
    {
        $roles = RoleCrm::orderBy('role_name')
            ->get()
            ->map(fn ($r) => [
                'id'    => $r->id,
                'name'  => $r->role_name,
                'label' => implode(' ', array_map('ucfirst', explode('_', $r->role_name))),
            ]);

        return response()->json(['success' => true, 'data' => $roles]);
    }

    public function storeRole(Request $request): JsonResponse
    {
        $request->validate(['role_name' => 'required|string|max:50|unique:role_crm,role_name']);
        $role = RoleCrm::create(['role_name' => strtolower(trim($request->role_name))]);
        return response()->json(['success' => true, 'data' => $role], 201);
    }

    public function destroyRole(int $id): JsonResponse
    {
        $role = RoleCrm::findOrFail($id);
        $role->delete();
        return response()->json(['success' => true]);
    }

    /**
     * GET /api/masters/languages
     *
     * Real language list from `language_crm` — used by the Create/Edit
     * Employee and Lead Account forms (language dropdown).
     */
    public function languages(): JsonResponse
    {
        $languages = \App\Models\Language::where('is_active', 1)
            ->orderBy('sort_order')
            ->orderBy('name')
            ->get(['id', 'name', 'code'])
            ->map(fn ($l) => [
                'id'   => (int) $l->id,
                'name' => $l->name,
                'code' => $l->code,
            ]);

        return response()->json(['success' => true, 'data' => $languages]);
    }

    /**
     * GET /api/masters/units
     *
     * Real unit list from `units_master` — used wherever a Sales Order line
     * item needs a unit (dropdown), instead of a hardcoded set.
     */
    public function units(): JsonResponse
    {
        $q = DB::table('units_master')->where('is_active', 1);
        // prod has serial_no; the dev copy doesn't
        if (Schema::hasColumn('units_master', 'serial_no')) {
            $q->orderBy('serial_no');
        }
        $units = $q->orderBy('unit_name')
            ->get(['unit_id', 'unit_name', 'conversion_rate'])
            ->map(fn ($u) => [
                'unit_id'         => (int) $u->unit_id,
                'unit_name'       => $u->unit_name,
                // units_master is the source of truth for stock conversion
                'conversion_rate' => (float) $u->conversion_rate,
            ]);

        return response()->json(['success' => true, 'data' => $units]);
    }

    public function employees(): JsonResponse
    {
        $q       = request()->query('q', null);
        $perPage = min(max((int) request()->query('per_page', 20), 1), 1000);

        $query = DeliStaff::select(
            'deli_id', 'mobile', 'name', 'role',
            'city', 'state', 'language', 'pincode', 'is_locked',
            'lat', 'lng', 'admin_id'
        )->orderBy('name');

        if ($q) {
            // Columns use a case-sensitive collation on this DB — lower-case
            // both sides so "ram" / "RAM" / "Ram" match the same rows.
            $needle = '%' . mb_strtolower($q) . '%';
            $query->where(function ($sub) use ($needle) {
                $sub->whereRaw('LOWER(name) LIKE ?', [$needle])
                    ->orWhereRaw('LOWER(role) LIKE ?', [$needle])
                    ->orWhereRaw('LOWER(mobile) LIKE ?', [$needle])
                    ->orWhereRaw('LOWER(city) LIKE ?', [$needle]);
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
            'pincode', 'city', 'state', 'language',
            'is_locked', 'admin_id',
            'lat', 'lng', 'password',
        ]);

        $validated = validator($data, [
            'name'      => 'required|string|max:255',
            'mobile'    => 'required|string|max:20',
            'role'      => 'nullable|string|max:20',
            'pincode'   => 'nullable|string|max:20',
            'city'      => 'nullable|string|max:100',
            'state'     => 'nullable|string|max:100',
            'language'  => 'nullable|string|max:50',
            'is_locked' => 'nullable|boolean',
            'admin_id'  => 'nullable|integer',
            'lat'       => 'nullable|numeric|between:-90,90',
            'lng'       => 'nullable|numeric|between:-180,180',
            'password'  => 'nullable|string|min:6|max:100',
        ])->validate();

        if (empty($validated['password'])) {
            unset($validated['password']);
        }

        // deli_staff is shared with the delivery app: never let "create"
        // silently overwrite someone who already exists (edits go through PUT).
        if (DeliStaff::where('mobile', $validated['mobile'])->exists()) {
            return response()->json([
                'success' => false,
                'message' => 'An employee with this mobile number already exists.',
                'errors'  => ['mobile' => ['An employee with this mobile number already exists.']],
            ], 422);
        }

        // A new employee with no vendor picked inherits the creating admin's
        // vendor — admin_id decides their product catalog and which vendor
        // their orders go to (orders.admin_id).
        if (empty($validated['admin_id'])) {
            $creatorVendor = (int) (\Tymon\JWTAuth\Facades\JWTAuth::parseToken()->authenticate()->admin_id ?? 0);
            if ($creatorVendor > 0) {
                $validated['admin_id'] = $creatorVendor;
            }
        }

        $validated = $this->coerceNotNullColumns($validated);

        // deli_id has no default / auto-increment on the live table — allocate manually
        // (see DeliStaffSeeder). Lock the table while reading max() to avoid duplicate
        // ids from concurrent requests.
        $staff = DB::transaction(function () use ($validated) {
            $staff = DeliStaff::lockForUpdate()->firstOrNew(['mobile' => $validated['mobile']]);

            if (! $staff->exists) {
                $staff->deli_id = (int) DeliStaff::lockForUpdate()->max('deli_id') + 1;
            }

            $staff->fill(collect($validated)->except('mobile')->toArray())->save();

            return $staff;
        });

        return response()->json(['success' => true, 'data' => $staff]);
    }

    public function update($id): JsonResponse
    {
        $data = request()->only([
            'name', 'role',
            'pincode', 'city', 'state', 'language',
            'is_locked', 'admin_id',
            'lat', 'lng', 'password',
        ]);

        $validated = validator($data, [
            'name'      => 'required|string|max:255',
            'role'      => 'nullable|string|max:20',
            'pincode'   => 'nullable|string|max:20',
            'city'      => 'nullable|string|max:100',
            'state'     => 'nullable|string|max:100',
            'language'  => 'nullable|string|max:50',
            'is_locked' => 'nullable|boolean',
            'admin_id'  => 'nullable|integer',
            'lat'       => 'nullable|numeric|between:-90,90',
            'lng'       => 'nullable|numeric|between:-180,180',
            'password'  => 'nullable|string|min:6|max:100',
        ])->validate();

        if (empty($validated['password'])) {
            unset($validated['password']);
        }

        $staff = DeliStaff::where('mobile', $id)->first();
        if (!$staff) {
            return response()->json(['success' => false, 'message' => 'Not found'], 404);
        }

        $staff->fill($this->coerceNotNullColumns($validated))->save();

        return response()->json(['success' => true, 'data' => $staff]);
    }

    /**
     * Prod `deli_staff.admin_id` / `is_locked` are NOT NULL (default 0) — an
     * explicit null from the form must become 0 or MariaDB rejects the write.
     */
    private function coerceNotNullColumns(array $data): array
    {
        // deli_staff is latin1 on prod — reject non-English text with a 422
        // rather than letting MariaDB fail the write with a 500.
        $bad = \App\Support\Latin1::badFields($data, ['name', 'city', 'state', 'pincode', 'language']);
        if ($bad) {
            throw \Illuminate\Validation\ValidationException::withMessages(
                array_fill_keys($bad, 'Please use English (Latin) characters only.')
            );
        }

        foreach (['admin_id', 'is_locked'] as $col) {
            if (array_key_exists($col, $data) && $data[$col] === null) {
                $data[$col] = 0;
            }
        }
        return $data;
    }
}

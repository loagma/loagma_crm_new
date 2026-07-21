<?php

namespace App\Http\Controllers;

use App\Models\LeadsAccount;
use App\Models\UserCustomer;
use Illuminate\Http\JsonResponse;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

class LeadsAccountController extends Controller
{
    public function uploadImage(): JsonResponse
    {
        $validated = request()->validate([
            'image' => 'required|image|mimes:jpg,jpeg,png,webp|max:5120',
        ]);

        $file = $validated['image'];
        $name = 'lead_' . Str::uuid()->toString() . '.' . $file->getClientOriginalExtension();
        $path = $file->storeAs('leads', $name, 'public');

        return response()->json([
            'success' => true,
            'path' => '/storage/' . $path,
        ]);
    }

    // ── Check contact number ───────────────────────────────────────────────────

    public function checkContact(): JsonResponse
    {
        $contact   = request()->query('contact_number');
        $excludeId = request()->query('exclude_id');

        if (empty($contact)) {
            return response()->json(['exists' => false]);
        }

        $query = LeadsAccount::where('contactNumber', $contact);

        if ($excludeId) {
            $query->where('id', '!=', $excludeId);
        }

        $account = $query->first();

        if ($account) {
            return response()->json([
                'exists' => true,
                'data'   => $account,
            ]);
        }

        return response()->json(['exists' => false]);
    }

    // ── List (with search & pagination) ────────────────────────────────────────

    public function index(): JsonResponse
    {
        $q       = request()->query('q');
        $perPage = (int) request()->query('per_page', 20);

        $query = LeadsAccount::orderBy('createdAt', 'desc');

        if ($q) {
            $query->where(function ($sub) use ($q) {
                $sub->where('businessName',  'like', "%{$q}%")
                    ->orWhere('personName',   'like', "%{$q}%")
                    ->orWhere('contactNumber','like', "%{$q}%")
                    ->orWhere('accountCode',  'like', "%{$q}%")
                    ->orWhere('city',         'like', "%{$q}%")
                    ->orWhere('area',         'like', "%{$q}%");
            });
        }

        // Filter by single pincode
        if (request()->has('pincode') && !request()->has('area_ids') && !request()->has('pincodes')) {
            $query->where('pincode', request()->query('pincode'));
        }

        // Combined OR filter: match accounts by areaId OR by pincode list
        // Handles accounts created before areaId was introduced (pincode-only)
        // and accounts created with areaId set.
        $areaIds = [];
        $pins    = [];

        if (request()->has('area_ids')) {
            $areaIds = array_values(array_filter(array_map('intval', (array) request()->query('area_ids'))));
        }
        if (request()->has('pincodes')) {
            $pins = array_values(array_filter((array) request()->query('pincodes')));
        }

        if (!empty($areaIds) || !empty($pins)) {
            $query->where(function ($sub) use ($areaIds, $pins) {
                if (!empty($areaIds)) {
                    $sub->whereIn('areaId', $areaIds);
                }
                if (!empty($pins)) {
                    $sub->orWhereIn('pincode', $pins);
                }
            });
        }

        if (request()->has('is_approved')) {
            $val = filter_var(request()->query('is_approved'), FILTER_VALIDATE_BOOLEAN, FILTER_NULL_ON_FAILURE);
            if ($val !== null) {
                $query->where('isApproved', $val);
            }
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

    // ── Show single ────────────────────────────────────────────────────────────

    public function show(string $id): JsonResponse
    {
        $account = LeadsAccount::find($id);

        if (!$account) {
            return response()->json(['success' => false, 'message' => 'Lead account not found'], 404);
        }

        return response()->json(['success' => true, 'data' => $account]);
    }

    // ── Create ─────────────────────────────────────────────────────────────────

    public function store(): JsonResponse
    {
        $data = request()->only([
            'businessName', 'businessType', 'businessSize', 'personName',
            'contactNumber', 'dateOfBirth', 'customerStage', 'funnelStage',
            'gstNumber', 'panCard', 'ownerImage', 'shopImage', 'isActive',
            'pincode', 'country', 'state', 'district', 'city', 'area',
            'address', 'latitude', 'longitude', 'areaId',
            'assignedToId', 'assignedDays', 'createdById',
        ]);

        $validated = validator($data, [
            'businessName'  => 'required|string|max:191',
            'businessType'  => 'required|string|max:191',
            'businessSize'  => 'required|string|max:191',
            'personName'    => 'required|string|max:191',
            'contactNumber' => 'required|string|max:191',
            'customerStage' => 'required|string|max:191',
            'funnelStage'   => 'required|string|max:191',
            'area'          => 'required|string|max:191',
            'pincode'       => 'required|string|max:191',
            'dateOfBirth'   => 'nullable|date',
            'gstNumber'     => 'nullable|string|max:191',
            'panCard'       => 'nullable|string|max:191',
            'ownerImage'    => 'nullable|string|max:191',
            'shopImage'     => 'nullable|string|max:191',
            'isActive'      => 'nullable|boolean',
            'country'       => 'nullable|string|max:191',
            'state'         => 'nullable|string|max:191',
            'district'      => 'nullable|string|max:191',
            'city'          => 'nullable|string|max:191',
            'address'       => 'nullable|string|max:191',
            'latitude'      => 'nullable|numeric|between:-90,90',
            'longitude'     => 'nullable|numeric|between:-180,180',
            'areaId'        => 'nullable|integer',
            'assignedToId'  => 'nullable|string|max:191',
            'assignedDays'  => 'nullable|array',
            'createdById'   => 'nullable|string|max:191',
        ])->validate();

        $account = LeadsAccount::create($validated);

        return response()->json(['success' => true, 'data' => $account], 201);
    }

    // ── Update ─────────────────────────────────────────────────────────────────

    public function update(string $id): JsonResponse
    {
        $account = LeadsAccount::find($id);

        if (!$account) {
            return response()->json(['success' => false, 'message' => 'Lead account not found'], 404);
        }

        $data = request()->only([
            'businessName', 'businessType', 'businessSize', 'personName',
            'contactNumber', 'dateOfBirth', 'customerStage', 'funnelStage',
            'gstNumber', 'panCard', 'ownerImage', 'shopImage', 'isActive',
            'pincode', 'country', 'state', 'district', 'city', 'area',
            'address', 'latitude', 'longitude', 'areaId',
            'assignedToId', 'assignedDays',
            'approvedById', 'approvedAt', 'isApproved',
            'verificationNotes', 'rejectionNotes',
        ]);

        $validated = validator($data, [
            'businessName'      => 'sometimes|required|string|max:191',
            'businessType'      => 'sometimes|required|string|max:191',
            'businessSize'      => 'sometimes|required|string|max:191',
            'personName'        => 'sometimes|required|string|max:191',
            'contactNumber'     => 'sometimes|required|string|max:191',
            'customerStage'     => 'sometimes|required|string|max:191',
            'funnelStage'       => 'sometimes|required|string|max:191',
            'area'              => 'sometimes|required|string|max:191',
            'pincode'           => 'sometimes|required|string|max:191',
            'dateOfBirth'       => 'nullable|date',
            'gstNumber'         => 'nullable|string|max:191',
            'panCard'           => 'nullable|string|max:191',
            'ownerImage'        => 'nullable|string|max:191',
            'shopImage'         => 'nullable|string|max:191',
            'isActive'          => 'nullable|boolean',
            'country'           => 'nullable|string|max:191',
            'state'             => 'nullable|string|max:191',
            'district'          => 'nullable|string|max:191',
            'city'              => 'nullable|string|max:191',
            'address'           => 'nullable|string|max:191',
            'latitude'          => 'nullable|numeric|between:-90,90',
            'longitude'         => 'nullable|numeric|between:-180,180',
            'areaId'            => 'nullable|integer',
            'assignedToId'      => 'nullable|string|max:191',
            'assignedDays'      => 'nullable|array',
            'approvedById'      => 'nullable|string|max:191',
            'approvedAt'        => 'nullable|date',
            'isApproved'        => 'nullable|boolean',
            'verificationNotes' => 'nullable|string|max:191',
            'rejectionNotes'    => 'nullable|string|max:191',
        ])->validate();

        $account->fill($validated)->save();

        return response()->json(['success' => true, 'data' => $account]);
    }

    // ── Delete ─────────────────────────────────────────────────────────────────

    public function destroy(string $id): JsonResponse
    {
        $account = LeadsAccount::find($id);

        if (!$account) {
            return response()->json(['success' => false, 'message' => 'Lead account not found'], 404);
        }

        $account->delete();

        return response()->json(['success' => true, 'message' => 'Lead account deleted successfully']);
    }

    // ── Get customers from user table ──────────────────────────────────────────

    public function customers(): JsonResponse
    {
        $pincodes = array_filter((array) request()->query('pincodes', []));
        $q = request()->query('q', '');

        $query = UserCustomer::query();

        if (!empty($pincodes)) {
            $query->whereIn('pincode', $pincodes);
        }

        if ($q) {
            $query->where(function ($x) use ($q) {
                $x->where('name', 'like', "%$q%")
                  ->orWhere('shop_name', 'like', "%$q%")
                  ->orWhere('contactno', 'like', "%$q%");
            });
        }

        $customers = $query->get([
            'userid', 'name', 'shop_name', 'contactno', 'email', 'address', 'shop_address',
            'pincode', 'city', 'state', 'latitude', 'longitude', 'user_type',
        ]);

        // `user_addresses` is the customer's actual saved address book — a
        // customer can have several (Home/Office/etc). Batch-fetch every
        // address for the customers on this page, grouped by user, instead of
        // the flat single user.address/latitude/longitude columns.
        $addressesByUser = DB::table('user_addresses')
            ->whereIn('user_id', $customers->pluck('userid'))
            ->orderByDesc('is_default')
            ->orderBy('id')
            ->get(['user_id', 'address', 'type', 'is_default', 'lat', 'lng'])
            ->groupBy('user_id');

        $data = $customers->map(function ($c) use ($addressesByUser) {
            $savedAddresses = $addressesByUser->get($c->userid, collect());

            // Address 1 is the account's own `user.address` column; Address
            // 2+ are the saved entries in `user_addresses` (default first).
            $addressList = collect();
            if (trim((string) $c->address) !== '') {
                $addressList->push([
                    'address'    => $c->address,
                    'type'       => 'Account',
                    'is_default' => $savedAddresses->isEmpty(),
                    'latitude'   => $c->latitude,
                    'longitude'  => $c->longitude,
                ]);
            }
            $addressList = $addressList->concat($savedAddresses->map(fn ($a) => [
                'address'    => $a->address,
                'type'       => $a->type,
                'is_default' => $a->is_default === '1',
                'latitude'   => $a->lat,
                'longitude'  => $a->lng,
            ]));

            // Drop duplicates (e.g. `user.address` matching a saved entry
            // verbatim) so the same text isn't listed twice.
            $addressList = $addressList->unique(fn ($a) => strtolower(trim((string) $a['address'])))->values();

            $primary = $addressList->first();

            return [
                'userid'       => $c->userid,
                'name'         => $c->name,
                'shop_name'    => $c->shop_name,
                'contactno'    => $c->contactno,
                'email'        => $c->email,
                'address'      => $primary['address'] ?? ($c->shop_address ?: ''),
                'shop_address' => $c->shop_address,
                'pincode'      => $c->pincode,
                'city'         => $c->city,
                'state'        => $c->state,
                'latitude'     => $primary['latitude'] ?? $c->latitude,
                'longitude'    => $primary['longitude'] ?? $c->longitude,
                'user_type'    => $c->user_type,
                'addresses'    => $addressList->values(),
            ];
        });

        return response()->json([
            'success' => true,
            'data' => $data,
        ]);
    }
}

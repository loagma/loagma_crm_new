<?php

namespace App\Http\Controllers;

use App\Models\DeliStaff;
use App\Models\LeadsAccount;
use App\Models\UserCustomer;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Response;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Str;
use Symfony\Component\HttpFoundation\StreamedResponse;
use Tymon\JWTAuth\Facades\JWTAuth;

class LeadsAccountController extends Controller
{
    // ── Auth helpers (same pattern as AttendanceController) ─────────────────────

    private function authMobile(): string
    {
        return JWTAuth::parseToken()->authenticate()->mobile;
    }

    private function approverStaff(): ?DeliStaff
    {
        return DeliStaff::where('mobile', $this->authMobile())->first();
    }

    private function isApprover(?DeliStaff $staff = null): bool
    {
        $staff ??= $this->approverStaff();
        $role = strtolower($staff->role ?? '');
        return \in_array($role, ['admin', 'teleadmin'], true);
    }

    // `user.user_type` is a strict enum('B2C','B2B'), but the lead form's
    // businessType field is free-choice (Retail, Wholesale, Manufacturer,
    // Service, Distributor, Other) — map it down on approval instead of
    // letting MySQL silently truncate an unrecognised value into the column.
    private function mapBusinessTypeToUserType(?string $businessType): string
    {
        $b2b = ['wholesale', 'manufacturer', 'distributor'];
        return \in_array(strtolower(trim($businessType ?? '')), $b2b, true) ? 'B2B' : 'B2C';
    }

    // Uploaded lead images are kept outside the public web root and served
    // through this controller (under /api/lead-accounts/...) rather than as
    // static files, so requests always go through Laravel's HTTP kernel and
    // pick up the CORS headers configured for 'api/*' — a plain static file
    // (e.g. under public/storage or public/uploads) would bypass that: Apache
    // serves it directly with no CORS header, and `php artisan serve`'s
    // built-in router does the same for any file that already exists on
    // disk, so neither environment could add the header after the fact.
    private const UPLOAD_DIR = 'uploads/leads';

    public function uploadImage(): JsonResponse
    {
        $validated = request()->validate([
            'image' => 'required|image|mimes:jpg,jpeg,png,webp|max:5120',
        ]);

        $file = $validated['image'];
        $name = 'lead_' . Str::uuid()->toString() . '.' . $file->getClientOriginalExtension();
        $file->storeAs(self::UPLOAD_DIR, $name);

        return response()->json([
            'success' => true,
            'path' => '/api/lead-accounts/image/' . $name,
        ]);
    }

    public function showImage(string $filename): StreamedResponse|Response
    {
        // basename() strips any path segments so this can't escape UPLOAD_DIR.
        $safeName = basename($filename);
        $path     = self::UPLOAD_DIR . '/' . $safeName;

        if (!Storage::exists($path)) {
            return response('Not found', 404);
        }

        return Storage::response($path);
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

        // "My leads" — a salesman/telecaller viewing only what they created.
        if (request()->filled('created_by')) {
            $query->where('createdById', request()->query('created_by'));
        }

        // Approval status filter: pending | approved | rejected
        if (request()->filled('status')) {
            $status = request()->query('status');
            if (\in_array($status, ['pending', 'approved', 'rejected'], true)) {
                $query->where('approval_status', $status);
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

    // ── Pending approval queue (admin / teleadmin) ───────────────────────────────
    // Scope is global by design: no per-team hierarchy exists linking a
    // salesman/telecaller to a specific teleadmin, unlike the incharge chain
    // AttendanceController walks — any admin/teleadmin can act on any lead.

    public function pendingCount(): JsonResponse
    {
        return response()->json([
            'success' => true,
            'count'   => LeadsAccount::where('approval_status', 'pending')->count(),
        ]);
    }

    public function pendingList(): JsonResponse
    {
        $perPage = (int) request()->query('per_page', 20);
        $page    = (int) request()->query('page', 1);
        $q       = request()->query('q');

        $query = LeadsAccount::with('creator:mobile,name,role')
            ->where('approval_status', 'pending');

        if ($q) {
            $query->where(function ($sub) use ($q) {
                $sub->where('businessName',  'like', "%{$q}%")
                    ->orWhere('personName',   'like', "%{$q}%")
                    ->orWhere('contactNumber','like', "%{$q}%");
            });
        }

        if (request()->filled('created_by')) {
            $query->where('createdById', request()->query('created_by'));
        }

        $p = $query->orderBy('createdAt')->paginate($perPage, ['*'], 'page', $page);

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

    // Distinct creators with at least one pending lead — powers the
    // "assigned by" filter dropdown on the pending-leads screen.
    public function pendingCreators(): JsonResponse
    {
        $ids = LeadsAccount::where('approval_status', 'pending')
            ->whereNotNull('createdById')
            ->distinct()
            ->pluck('createdById');

        $creators = DeliStaff::whereIn('mobile', $ids)
            ->get(['mobile', 'name', 'role']);

        return response()->json([
            'success' => true,
            'data'    => $creators,
        ]);
    }

    // ── Approve: converts the lead into a real customer (`user` table) ──────────

    public function approve(string $id): JsonResponse
    {
        $account = LeadsAccount::find($id);
        if (!$account) {
            return response()->json(['success' => false, 'message' => 'Lead account not found'], 404);
        }
        if ($account->approval_status !== 'pending') {
            return response()->json(['success' => false, 'message' => 'This lead has already been reviewed'], 422);
        }

        // Avoid creating a second customer for a contact number already on file.
        if (UserCustomer::where('contactno', $account->contactNumber)->exists()) {
            return response()->json([
                'success' => false,
                'message' => 'A customer with this contact number already exists',
            ], 422);
        }

        $customer = \DB::transaction(function () use ($account) {
            // `user.userid` has no auto-increment or default on this shared,
            // legacy-managed table — every other write path in this app only
            // ever reads it, so we have to mint the next id ourselves. Lock
            // the max() read to keep two concurrent approvals from colliding.
            $nextId = (int) (\DB::table('user')->lockForUpdate()->max('userid') ?? 0) + 1;

            $customer = UserCustomer::create([
                'userid'        => $nextId,
                'name'          => $account->personName,
                'shop_name'     => $account->businessName,
                'contactno'     => $account->contactNumber,
                // `address` is a NOT NULL TEXT column (no real DEFAULT) and
                // latitude/longitude are NOT NULL FLOAT — a lead approved
                // without a full address/geo pin still has to satisfy those
                // constraints, so an explicit NULL from the lead has to be
                // coalesced rather than passed straight through.
                'address'       => $account->address ?? '',
                'shop_address'  => $account->address ?? '',
                'pincode'       => $account->pincode,
                'city'          => $account->city,
                'state'         => $account->state,
                'latitude'      => $account->latitude ?? 0,
                'longitude'     => $account->longitude ?? 0,
                'user_type'     => $this->mapBusinessTypeToUserType($account->businessType),
                'is_approved'   => 'YES',
                'account_state' => 'active',
                'lead_account_id' => $account->id,
                // These `text` columns have no real DEFAULT in MySQL/TiDB
                // (TEXT/BLOB can't take one) despite SHOW COLUMNS implying
                // otherwise — omitting them fails the insert outright.
                'session_id'    => '',
                'push_notif_id' => '',
            ]);

            $account->update([
                'approval_status'   => 'approved',
                'isApproved'        => true,
                'approvedById'      => $this->authMobile(),
                'approvedAt'        => now(),
                'verificationNotes' => request()->input('verification_notes'),
                'rejectionNotes'    => null,
            ]);

            return $customer;
        });

        return response()->json(['success' => true, 'data' => $account->fresh(), 'customer' => $customer]);
    }

    // ── Reject: sends the lead back to its creator with a required reason ───────

    public function reject(string $id): JsonResponse
    {
        $account = LeadsAccount::find($id);
        if (!$account) {
            return response()->json(['success' => false, 'message' => 'Lead account not found'], 404);
        }
        if ($account->approval_status !== 'pending') {
            return response()->json(['success' => false, 'message' => 'This lead has already been reviewed'], 422);
        }

        $validated = validator(request()->only('rejection_notes'), [
            'rejection_notes' => 'required|string|max:1000',
        ])->validate();

        $account->update([
            'approval_status' => 'rejected',
            'isApproved'      => false,
            'rejectionNotes'  => $validated['rejection_notes'],
        ]);

        return response()->json(['success' => true, 'data' => $account->fresh()]);
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

        // A creator fixing a rejected lead and saving again re-enters the
        // review queue automatically — regardless of what the client sends —
        // so a resubmission can never get silently stuck as "rejected".
        $wasRejected = $account->approval_status === 'rejected';
        $editorIsApprover = false;
        try {
            $editorIsApprover = $this->isApprover();
        } catch (\Throwable $e) {
            // No/invalid token — treat as a non-approver (safe default).
        }
        if ($wasRejected && !$editorIsApprover && !\array_key_exists('approval_status', $validated)) {
            $validated['approval_status'] = 'pending';
            $validated['rejectionNotes']  = null;
        }

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

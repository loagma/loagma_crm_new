<?php

namespace App\Http\Controllers;

use App\Models\CustomerAssign;
use App\Models\DeliStaff;
use App\Models\UserCustomer;
use Illuminate\Http\JsonResponse;
use Illuminate\Support\Facades\DB;
use Tymon\JWTAuth\Facades\JWTAuth;

// Direct single-customer -> single-employee assignment (customer_assign_crm).
// Admin picks one `user` customer and pins it to one employee; the employee
// then sees it merged into their Allotted Customers list alongside the
// area-based allotment.
class CustomerAssignController extends Controller
{
    private function authMobile(): string
    {
        return JWTAuth::parseToken()->authenticate()->mobile;
    }

    // ── Admin: list every direct assignment (optionally for one employee) ──────
    // Returns rows enriched with the customer + employee display names so the
    // admin screen can render without a second round-trip.
    public function index(): JsonResponse
    {
        $query = CustomerAssign::query();

        if (request()->filled('employee_mobile')) {
            $query->where('employee_mobile', request()->query('employee_mobile'));
        }
        if (request()->filled('customer_userid')) {
            $query->where('customer_userid', (int) request()->query('customer_userid'));
        }

        $rows = $query->orderByDesc('updated_at')->get();

        $customers = UserCustomer::whereIn('userid', $rows->pluck('customer_userid'))
            ->get(['userid', 'name', 'shop_name', 'contactno', 'pincode', 'city'])
            ->keyBy('userid');

        $staff = DeliStaff::whereIn('mobile', $rows->pluck('employee_mobile'))
            ->get(['mobile', 'name', 'role'])
            ->keyBy('mobile');

        $data = $rows->map(function ($r) use ($customers, $staff) {
            $c = $customers->get($r->customer_userid);
            $s = $staff->get($r->employee_mobile);

            return [
                'id'              => (int) $r->id,
                'customer_userid' => (int) $r->customer_userid,
                'employee_mobile' => $r->employee_mobile,
                'assigned_by'     => $r->assigned_by,
                'updated_at'      => optional($r->updated_at)->toIso8601String(),
                'customer_name'   => $c->shop_name ?: ($c->name ?? '') ?: "User #{$r->customer_userid}",
                'customer_person' => $c->name ?? '',
                'customer_phone'  => $c->contactno ?? '',
                'customer_pincode' => $c->pincode ?? '',
                'customer_city'   => $c->city ?? '',
                'employee_name'   => $s->name ?? $r->employee_mobile,
                'employee_role'   => $s->role ?? '',
            ];
        })->values();

        return response()->json(['success' => true, 'data' => $data]);
    }

    // ── Admin: create / move an assignment (one row per customer) ─────────────
    public function assign(): JsonResponse
    {
        $validated = validator(request()->all(), [
            'customer_userid' => 'required|integer',
            'employee_mobile' => 'required|string|max:20',
        ])->validate();

        if (!UserCustomer::where('userid', $validated['customer_userid'])->exists()) {
            return response()->json(['success' => false, 'message' => 'Customer not found'], 404);
        }
        if (!DeliStaff::where('mobile', $validated['employee_mobile'])->exists()) {
            return response()->json(['success' => false, 'message' => 'Employee not found'], 404);
        }

        $assign = CustomerAssign::updateOrCreate(
            ['customer_userid' => $validated['customer_userid']],
            [
                'employee_mobile' => $validated['employee_mobile'],
                'assigned_by'     => $this->authMobile(),
            ],
        );

        return response()->json([
            'success' => true,
            'data'    => $assign,
        ], $assign->wasRecentlyCreated ? 201 : 200);
    }

    // ── Admin: create / move many assignments to one employee at once ────────
    public function bulkAssign(): JsonResponse
    {
        $validated = validator(request()->all(), [
            'customer_userids'   => 'required|array|min:1',
            'customer_userids.*' => 'integer',
            'employee_mobile'    => 'required|string|max:20',
        ])->validate();

        if (!DeliStaff::where('mobile', $validated['employee_mobile'])->exists()) {
            return response()->json(['success' => false, 'message' => 'Employee not found'], 404);
        }

        $userids = array_values(array_unique(array_map('intval', $validated['customer_userids'])));
        $existing = UserCustomer::whereIn('userid', $userids)->pluck('userid')->all();

        $by = $this->authMobile();
        $count = 0;
        foreach ($existing as $uid) {
            CustomerAssign::updateOrCreate(
                ['customer_userid' => $uid],
                ['employee_mobile' => $validated['employee_mobile'], 'assigned_by' => $by],
            );
            $count++;
        }

        $missing = array_values(array_diff($userids, $existing));

        return response()->json([
            'success'  => true,
            'assigned' => $count,
            'skipped'  => $missing,
        ]);
    }

    // ── Admin: remove an assignment ──────────────────────────────────────────
    public function destroy(string $customerUserid): JsonResponse
    {
        $deleted = CustomerAssign::where('customer_userid', (int) $customerUserid)->delete();

        return response()->json([
            'success' => (bool) $deleted,
            'message' => $deleted ? 'Assignment removed' : 'No assignment found',
        ]);
    }

    // ── Employee: the customers directly assigned to me ──────────────────────
    // Shaped identically to LeadsAccountController::customers() so the client
    // can drop the rows straight into the Allotted Customers list.
    public function mine(): JsonResponse
    {
        $userids = CustomerAssign::where('employee_mobile', $this->authMobile())
            ->pluck('customer_userid');

        if ($userids->isEmpty()) {
            return response()->json(['success' => true, 'data' => []]);
        }

        $customers = UserCustomer::whereIn('userid', $userids)->get([
            'userid', 'name', 'shop_name', 'contactno', 'email', 'address', 'shop_address',
            'pincode', 'city', 'state', 'latitude', 'longitude', 'user_type',
        ]);

        $addressesByUser = DB::table('user_addresses')
            ->whereIn('user_id', $customers->pluck('userid'))
            ->orderByDesc('is_default')
            ->orderBy('id')
            ->get(['user_id', 'address', 'type', 'is_default', 'lat', 'lng'])
            ->groupBy('user_id');

        $data = $customers->map(function ($c) use ($addressesByUser) {
            $savedAddresses = $addressesByUser->get($c->userid, collect());

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
            ]))->unique(fn ($a) => strtolower(trim((string) $a['address'])))->values();

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

        return response()->json(['success' => true, 'data' => $data]);
    }
}

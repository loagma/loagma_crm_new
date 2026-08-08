<?php

namespace App\Http\Controllers;

use App\Models\Complaint;
use App\Models\DeliStaff;
use App\Models\InchargeAssign;
use App\Models\LeadsAccount;
use Illuminate\Http\JsonResponse;
use Illuminate\Support\Facades\DB;
use Tymon\JWTAuth\Facades\JWTAuth;

class ComplaintController extends Controller
{
    // ── Auth + hierarchy helpers (same pattern as AttendanceController) ─────────

    private function authMobile(): string
    {
        return JWTAuth::parseToken()->authenticate()->mobile;
    }

    private function approverStaff(): ?DeliStaff
    {
        return DeliStaff::where('mobile', $this->authMobile())->first();
    }

    // Returns mobile strings of the children directly assigned to this parent
    // incharge in incharge_assign_crm. Works at every level of the hierarchy
    // since the table is keyed by the parent's mobile (head_incharge_id) with
    // children mobiles in incharge_ids.
    private function getAssignedInchargeMobiles(string $parentMobile): array
    {
        $assign = InchargeAssign::where('head_incharge_id', (int) $parentMobile)->first();
        if (!$assign || empty($assign->incharge_ids)) return [];
        return array_map('strval', $assign->incharge_ids);
    }

    // Returns mobile strings of ALL descendants below this incharge, walking the
    // hierarchy recursively. Cycle-safe via the $visited set.
    private function getDescendantMobiles(string $parentMobile, array &$visited = []): array
    {
        if (isset($visited[$parentMobile])) return [];
        $visited[$parentMobile] = true;

        $descendants = [];
        foreach ($this->getAssignedInchargeMobiles($parentMobile) as $childMobile) {
            $descendants[] = $childMobile;
            $descendants = array_merge($descendants, $this->getDescendantMobiles($childMobile, $visited));
        }
        return array_values(array_unique($descendants));
    }

    // True if the requester may act on / view this specific complaint: admin
    // sees everything, any incharge-type role sees complaints raised by their
    // descendants, the original raiser can always see (not necessarily
    // change) their own ticket, and whoever it's currently assigned to may
    // act on it even if they're outside the raiser's own reporting line.
    private function authorizeAction(Complaint $complaint): bool
    {
        $staff = $this->approverStaff();
        if (!$staff) return false;

        if (strtolower($staff->role ?? '') === 'admin') return true;
        if ($staff->mobile === $complaint->raised_by) return true;
        if ($complaint->assigned_to && $staff->mobile === $complaint->assigned_to) return true;

        $descendants = $this->getDescendantMobiles($staff->mobile);
        return \in_array((string) $complaint->raised_by, $descendants, true);
    }

    // Resolves account_id/account_type into full display details, same
    // approach as TelecallerController::enrich().
    private function enrich($complaints): array
    {
        $leadIds = $complaints->where('account_type', 'lead')->pluck('account_id')->filter()->unique()->values()->all();
        $custIds = $complaints->where('account_type', 'customer')->pluck('account_id')->filter()->unique()->values()->all();

        $map = [];
        if (!empty($leadIds)) {
            $leads = LeadsAccount::whereIn('id', $leadIds)
                ->get(['id', 'businessName', 'personName', 'contactNumber', 'address', 'area', 'city', 'latitude', 'longitude']);
            foreach ($leads as $l) {
                $map[(string) $l->id] = [
                    'name'      => $l->businessName ?: $l->personName,
                    'owner'     => $l->personName,
                    'phone'     => $l->contactNumber,
                    'address'   => $l->address,
                    'area'      => $l->area,
                    'city'      => $l->city,
                    'latitude'  => $l->latitude,
                    'longitude' => $l->longitude,
                ];
            }
        }
        if (!empty($custIds)) {
            $customers = DB::table('user')->whereIn('userid', $custIds)
                ->get(['userid', 'name', 'shop_name', 'contactno', 'address', 'city', 'latitude', 'longitude']);
            foreach ($customers as $c) {
                $map[(string) $c->userid] = [
                    'name'      => $c->shop_name ?: $c->name,
                    'owner'     => $c->name,
                    'phone'     => $c->contactno,
                    'address'   => $c->address,
                    'area'      => null,
                    'city'      => $c->city,
                    'latitude'  => $c->latitude,
                    'longitude' => $c->longitude,
                ];
            }
        }
        return $map;
    }

    // Resolves a set of staff mobiles (raised_by / assigned_to / assigned_by)
    // into name/role, so the UI never has to show a bare mobile number.
    private function enrichStaff($complaints): array
    {
        $mobiles = $complaints->pluck('raised_by')
            ->merge($complaints->pluck('assigned_to'))
            ->merge($complaints->pluck('assigned_by'))
            ->filter()->unique()->values()->all();
        if (empty($mobiles)) return [];

        $staff = DeliStaff::whereIn('mobile', $mobiles)->get(['mobile', 'name', 'role']);
        $map = [];
        foreach ($staff as $s) {
            $map[$s->mobile] = ['name' => $s->name, 'role' => $s->role];
        }
        return $map;
    }

    // ── Create (salesman-visit channel) ──────────────────────────────────────
    // The telecaller-call channel does NOT call this — it's created inline,
    // in the same transaction, by CallLogController::store().

    public function store(): JsonResponse
    {
        $mobile = $this->authMobile();

        $validated = validator(request()->only([
            'account_id', 'account_type', 'beat_plan_id', 'category', 'description',
        ]), [
            'account_id'   => 'required|string|max:191',
            'account_type' => 'required|in:lead,customer',
            'beat_plan_id' => 'nullable|integer',
            'category'     => 'required|string|max:191',
            'description'  => 'required|string',
        ])->validate();

        $complaint = Complaint::create(array_merge($validated, [
            'source_channel' => 'salesman_visit',
            'raised_by'      => $mobile,
        ]));

        return response()->json(['success' => true, 'data' => $complaint], 201);
    }

    // ── List (hierarchy-scoped) ──────────────────────────────────────────────

    public function index(): JsonResponse
    {
        $staff = $this->approverStaff();
        if (!$staff) {
            return response()->json(['success' => false, 'message' => 'Unauthorized'], 403);
        }

        $role = strtolower($staff->role ?? '');
        $query = Complaint::orderByDesc('created_at');

        if (request()->filled('raised_by')) {
            // Explicit "my complaints" view — always allowed for one's own mobile;
            // an approver may also filter down to a specific descendant.
            $query->where('raised_by', request()->query('raised_by'));
        } elseif (request()->filled('assigned_to')) {
            // Explicit "assigned to me" view — works for any role, since a
            // complaint can be delegated all the way down to a salesman or
            // telecaller, not just to fellow incharges.
            $query->where('assigned_to', request()->query('assigned_to'));
        } elseif ($role !== 'admin') {
            $mobiles = $this->getDescendantMobiles($staff->mobile);
            $mobiles[] = $staff->mobile; // also see complaints they raised themselves
            // A complaint assigned to this staff member is visible even if the
            // original raiser sits outside their own reporting line (e.g. a
            // head incharge assigned it to someone in a different branch).
            $query->where(function ($q) use ($mobiles, $staff) {
                $q->whereIn('raised_by', $mobiles)
                    ->orWhere('assigned_to', $staff->mobile);
            });
        }

        if (request()->filled('status')) {
            $status = request()->query('status');
            if (\in_array($status, ['open', 'in_progress', 'resolved', 'closed'], true)) {
                $query->where('status', $status);
            }
        }

        $perPage = (int) request()->query('per_page', 20);
        $page    = (int) request()->query('page', 1);
        $p       = $query->paginate($perPage, ['*'], 'page', $page);

        $items    = collect($p->items());
        $accounts = $this->enrich($items);
        $staffMap = $this->enrichStaff($items);

        $data = $items->map(function (Complaint $c) use ($accounts, $staffMap) {
            $acc      = $accounts[$c->account_id] ?? [];
            $raiser   = $staffMap[$c->raised_by] ?? [];
            $assignee = $staffMap[$c->assigned_to] ?? [];
            $assigner = $staffMap[$c->assigned_by] ?? [];
            $arr = $c->toArray();
            $arr['account_name']      = $acc['name']      ?? null;
            $arr['account_owner']     = $acc['owner']     ?? null;
            $arr['account_phone']     = $acc['phone']     ?? null;
            $arr['account_address']   = $acc['address']   ?? null;
            $arr['account_area']      = $acc['area']      ?? null;
            $arr['account_city']      = $acc['city']      ?? null;
            $arr['account_latitude']  = $acc['latitude']  ?? null;
            $arr['account_longitude'] = $acc['longitude'] ?? null;
            $arr['raised_by_name']    = $raiser['name']   ?? null;
            $arr['raised_by_role']    = $raiser['role']   ?? null;
            $arr['assigned_to_name']  = $assignee['name'] ?? null;
            $arr['assigned_to_role']  = $assignee['role'] ?? null;
            $arr['assigned_by_name']  = $assigner['name'] ?? null;
            $arr['assigned_by_role']  = $assigner['role'] ?? null;
            return $arr;
        });

        return response()->json([
            'success' => true,
            'data'    => $data,
            'meta'    => [
                'current_page' => $p->currentPage(),
                'last_page'    => $p->lastPage(),
                'per_page'     => $p->perPage(),
                'total'        => $p->total(),
            ],
        ]);
    }

    // ── Update status ─────────────────────────────────────────────────────────

    public function updateStatus(string $id): JsonResponse
    {
        $complaint = Complaint::find((int) $id);
        if (!$complaint) {
            return response()->json(['success' => false, 'message' => 'Complaint not found'], 404);
        }
        if (!$this->authorizeAction($complaint)) {
            return response()->json(['success' => false, 'message' => 'You are not authorized to update this complaint'], 403);
        }

        $validated = validator(request()->only(['status', 'resolution_notes']), [
            'status'           => 'required|in:open,in_progress,resolved,closed',
            'resolution_notes' => 'nullable|string',
        ])->validate();

        $update = ['status' => $validated['status']];
        if (array_key_exists('resolution_notes', $validated)) {
            $update['resolution_notes'] = $validated['resolution_notes'];
        }
        if (\in_array($validated['status'], ['resolved', 'closed'], true)) {
            $update['resolved_by'] = $this->authMobile();
            $update['resolved_at'] = now();
        }

        $complaint->update($update);

        return response()->json(['success' => true, 'data' => $complaint->fresh()]);
    }

    // ── Assign ─────────────────────────────────────────────────────────────────
    // Anyone who can already act on a complaint (admin, the raiser's own
    // superior chain, or the current assignee re-delegating) may hand it to
    // someone else — but only to themselves or a member of their own
    // downward hierarchy, never to an arbitrary unrelated staff member.
    // Admin is exempt from the hierarchy check since admin has no incharge
    // subtree of their own.

    public function assign(string $id): JsonResponse
    {
        $complaint = Complaint::find((int) $id);
        if (!$complaint) {
            return response()->json(['success' => false, 'message' => 'Complaint not found'], 404);
        }
        if (!$this->authorizeAction($complaint)) {
            return response()->json(['success' => false, 'message' => 'You are not authorized to assign this complaint'], 403);
        }

        $validated = validator(request()->only(['assigned_to']), [
            'assigned_to' => 'required|string|max:20',
        ])->validate();

        $actor        = $this->approverStaff();
        $targetMobile = $validated['assigned_to'];
        $isAdmin      = strtolower($actor->role ?? '') === 'admin';
        $isSelf       = $targetMobile === $actor->mobile;

        if (!$isAdmin && !$isSelf) {
            $descendants = $this->getDescendantMobiles($actor->mobile);
            if (!\in_array($targetMobile, $descendants, true)) {
                return response()->json(['success' => false, 'message' => 'You can only assign to yourself or someone in your own team'], 403);
            }
        }

        $target = DeliStaff::where('mobile', $targetMobile)->first();
        if (!$target) {
            return response()->json(['success' => false, 'message' => 'Assignee not found'], 404);
        }

        $update = [
            'assigned_to' => $targetMobile,
            'assigned_by' => $actor->mobile,
            'assigned_at' => now(),
        ];
        // Assigning an untouched ticket implicitly starts work on it.
        if ($complaint->status === 'open') {
            $update['status'] = 'in_progress';
        }

        $complaint->update($update);

        return response()->json(['success' => true, 'data' => $complaint->fresh()]);
    }

    // ── Assigned-to-me count (for notification badge) ───────────────────────────
    // Any role can be an assignee (a supervisor may delegate all the way down
    // to a salesman/telecaller), so this is unscoped by hierarchy — just "how
    // many still-open tickets are sitting in my own queue right now".

    public function assignedCount(): JsonResponse
    {
        $staff = $this->approverStaff();
        if (!$staff) return response()->json(['success' => true, 'count' => 0]);

        $count = Complaint::where('assigned_to', $staff->mobile)
            ->whereIn('status', ['open', 'in_progress'])
            ->count();

        return response()->json(['success' => true, 'count' => $count]);
    }
}

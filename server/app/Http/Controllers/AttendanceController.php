<?php

namespace App\Http\Controllers;

use App\Models\Attendance;
use App\Models\DeliStaff;
use App\Models\InchargeAssign;
use Carbon\Carbon;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Str;
use Tymon\JWTAuth\Facades\JWTAuth;

class AttendanceController extends Controller
{
    // ─── Helpers ─────────────────────────────────────────────────────────────

    private function authMobile(): string
    {
        // Use the same proven token-parsing pattern as OtpAuthController::me()
        // (the default guard is `web`/session, so auth() resolves to null here).
        return JWTAuth::parseToken()->authenticate()->mobile;
    }

    private function isLate(DeliStaff $staff): bool
    {
        if (!$staff->punch_in_time) return false;
        $expected = Carbon::today()->setTimeFromTimeString($staff->punch_in_time)
            ->addMinutes($staff->grace_minutes ?? 15);
        return Carbon::now()->gt($expected);
    }

    private function isEarlyOut(DeliStaff $staff): bool
    {
        if (!$staff->punch_out_time) return false;
        $expected = Carbon::today()->setTimeFromTimeString($staff->punch_out_time);
        return Carbon::now()->lt($expected);
    }

    private function isEarlyIn(DeliStaff $staff): bool
    {
        if (!$staff->punch_in_time) return false;
        $shiftStart = Carbon::today()->setTimeFromTimeString($staff->punch_in_time);
        return Carbon::now()->lt($shiftStart);
    }

    // Returns mobile strings of the children directly assigned to this parent
    // incharge in incharge_assign_crm. Works at every level of the hierarchy
    // (head→zonal, zonal→area, area→salesman) since the table is keyed by the
    // parent's mobile (head_incharge_id) with children mobiles in incharge_ids.
    private function getAssignedInchargeMobiles(string $parentMobile): array
    {
        $assign = InchargeAssign::where('head_incharge_id', (int) $parentMobile)->first();
        if (!$assign || empty($assign->incharge_ids)) return [];
        // incharge_ids are mobile numbers stored as integers
        return array_map('strval', $assign->incharge_ids);
    }

    // Returns mobile strings of ALL descendants below this incharge, walking the
    // hierarchy recursively (head→zonal→area→salesman). This makes a salesman's
    // record visible to every ancestor in their chain, not just their direct
    // parent. Cycle-safe via the $visited set.
    private function getDescendantMobiles(string $parentMobile, array &$visited = []): array
    {
        if (isset($visited[$parentMobile])) return [];
        $visited[$parentMobile] = true;

        $descendants = [];
        foreach ($this->getAssignedInchargeMobiles($parentMobile) as $childMobile) {
            $descendants[] = $childMobile;
            $descendants = array_merge(
                $descendants,
                $this->getDescendantMobiles($childMobile, $visited)
            );
        }
        return array_values(array_unique($descendants));
    }

    // Returns the role-aware approver staff, or null if not found.
    private function approverStaff(): ?DeliStaff
    {
        return DeliStaff::where('mobile', $this->authMobile())->first();
    }

    // True if the approver has authority to approve/reject the given attendance
    // record: admin can approve anyone; any incharge can approve anyone in their
    // chain below them (direct or indirect descendant in the hierarchy).
    private function authorizeApproval(Attendance $record): bool
    {
        $approver = $this->approverStaff();
        if (!$approver) return false;

        if (strtolower($approver->role ?? '') === 'admin') return true;

        $descendants = $this->getDescendantMobiles($approver->mobile);
        return \in_array((string) $record->employee_mobile, $descendants, true);
    }

    // ─── Employee: Upload punch photo ─────────────────────────────────────────

    public function uploadPhoto(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'image' => 'required|image|mimes:jpg,jpeg,png,webp|max:5120',
        ]);

        $file = $validated['image'];
        $name = 'att_' . Str::uuid() . '.' . $file->getClientOriginalExtension();
        $path = $file->storeAs('attendance', $name, 'public');

        return response()->json(['success' => true, 'path' => '/storage/' . $path]);
    }

    // ─── Employee: Punch In ───────────────────────────────────────────────────

    public function punchIn(Request $request): JsonResponse
    {
        $mobile = $this->authMobile();
        $today  = Carbon::today()->toDateString();

        $record = Attendance::where('employee_mobile', $mobile)->where('date', $today)->first();

        if ($record && $record->punch_in_time) {
            return response()->json(['success' => false, 'message' => 'Already punched in today'], 422);
        }

        $staff            = DeliStaff::where('mobile', $mobile)->first();
        $isLate           = $this->isLate($staff);
        $isEarlyIn        = !$isLate && $this->isEarlyIn($staff); // mutually exclusive with late
        $approvalRequired = $staff->approval_required ?? true;
        $needsApproval    = $isLate && $approvalRequired; // early-in never needs approval

        $data = [
            'employee_mobile'   => $mobile,
            'date'              => $today,
            'punch_in_time'     => Carbon::now(),
            'is_late'           => $isLate,
            'is_early_in'       => $isEarlyIn,
            'late_reason'       => $isLate    ? $request->input('late_reason')     : null,
            'early_in_reason'   => $isEarlyIn ? $request->input('early_in_reason') : null,
            'punch_in_photo'    => $needsApproval ? null : $request->input('punch_in_photo'),
            'punch_in_location' => $needsApproval ? null : $request->input('punch_in_location'),
            'status'            => $needsApproval ? 'pending' : ($isEarlyIn ? 'early_in' : 'on_time'),
            'break_details'     => [],
        ];

        $record = Attendance::updateOrCreate(
            ['employee_mobile' => $mobile, 'date' => $today],
            $data
        );

        return response()->json(['success' => true, 'data' => $record], 201);
    }

    // ─── Employee: Punch Out ──────────────────────────────────────────────────

    public function punchOut(Request $request): JsonResponse
    {
        $mobile = $this->authMobile();
        $today  = Carbon::today()->toDateString();

        $record = Attendance::where('employee_mobile', $mobile)->where('date', $today)->first();

        if (!$record || !$record->punch_in_time) {
            return response()->json(['success' => false, 'message' => 'Not punched in today'], 422);
        }
        if ($record->punch_out_time) {
            return response()->json(['success' => false, 'message' => 'Already punched out today'], 422);
        }

        $staff            = DeliStaff::where('mobile', $mobile)->first();
        $isEarlyOut       = $this->isEarlyOut($staff);
        $approvalRequired = $staff->approval_required ?? true;
        $needsApproval    = $isEarlyOut && $approvalRequired;

        $workMinutes  = (int) $request->input('total_work_minutes', 0);
        $breakMinutes = (int) $request->input('total_break_minutes', 0);

        $status = $record->status;
        // Also covers early_in: employee who punched in early can still punch out early
        if ($needsApproval && \in_array($status, ['on_time', 'early_in'])) {
            $status = 'pending';
        }

        $record->update([
            'punch_out_time'      => Carbon::now(),
            'punch_out_photo'     => $needsApproval ? null : $request->input('punch_out_photo'),
            'punch_out_location'  => $needsApproval ? null : $request->input('punch_out_location'),
            'is_early_out'        => $isEarlyOut,
            'early_out_reason'    => $isEarlyOut ? $request->input('early_out_reason') : null,
            'total_work_minutes'  => $workMinutes,
            'total_break_minutes' => $breakMinutes,
            'status'              => $status,
        ]);

        return response()->json(['success' => true, 'data' => $record->fresh()]);
    }

    // ─── Employee: Confirm punch after approval ───────────────────────────────
    // Called after admin approves a late/early record. Employee provides
    // photo + location to confirm they are actually present.

    public function confirmPunch(Request $request): JsonResponse
    {
        $request->validate([
            'type' => 'required|in:in,out',
        ]);

        $mobile = $this->authMobile();
        $today  = Carbon::today()->toDateString();

        $record = Attendance::where('employee_mobile', $mobile)->where('date', $today)->first();

        if (!$record) {
            return response()->json(['success' => false, 'message' => 'No attendance record for today'], 422);
        }
        if ($record->status !== 'approved') {
            return response()->json(['success' => false, 'message' => 'Attendance not yet approved'], 422);
        }

        $type = $request->input('type');
        $photo    = $request->input('photo');
        $location = $request->input('location'); // array {lat, lng}

        if ($type === 'in') {
            $record->update([
                'punch_in_photo'    => $photo,
                'punch_in_location' => $location,
            ]);
        } else {
            $record->update([
                'punch_out_photo'    => $photo,
                'punch_out_location' => $location,
            ]);
        }

        return response()->json(['success' => true, 'data' => $record->fresh()]);
    }

    // ─── Employee: Break ──────────────────────────────────────────────────────

    public function updateBreak(Request $request): JsonResponse
    {
        $request->validate([
            'type'   => 'required|in:tea,lunch,emergency',
            'action' => 'required|in:start,end',
        ]);

        $mobile = $this->authMobile();
        $today  = Carbon::today()->toDateString();

        $record = Attendance::where('employee_mobile', $mobile)->where('date', $today)->first();

        if (!$record || !$record->punch_in_time) {
            return response()->json(['success' => false, 'message' => 'Not punched in'], 422);
        }

        $breaks = $record->break_details ?? [];
        $type   = $request->input('type');
        $action = $request->input('action');
        $now    = Carbon::now()->toDateTimeString();

        if ($action === 'start') {
            $breaks[] = ['type' => $type, 'start' => $now, 'end' => null];
        } else {
            for ($i = count($breaks) - 1; $i >= 0; $i--) {
                if ($breaks[$i]['type'] === $type && $breaks[$i]['end'] === null) {
                    $breaks[$i]['end'] = $now;
                    break;
                }
            }
        }

        $record->update(['break_details' => $breaks]);

        return response()->json(['success' => true, 'data' => $record->fresh()]);
    }

    // ─── Employee: Today's record ─────────────────────────────────────────────

    public function today(): JsonResponse
    {
        $mobile = $this->authMobile();
        $today  = Carbon::today()->toDateString();

        $record = Attendance::where('employee_mobile', $mobile)->where('date', $today)->first();

        $staff = DeliStaff::where('mobile', $mobile)
            ->select('punch_in_time', 'punch_out_time', 'grace_minutes', 'approval_required')
            ->first();

        return response()->json([
            'success'  => true,
            'data'     => $record,
            'settings' => $staff,
        ]);
    }

    // ─── Employee: History ────────────────────────────────────────────────────

    public function myHistory(): JsonResponse
    {
        $mobile  = $this->authMobile();
        $perPage = (int) request()->query('per_page', 20);
        $page    = (int) request()->query('page', 1);

        $p = Attendance::where('employee_mobile', $mobile)
            ->orderByDesc('date')
            ->paginate($perPage, ['*'], 'page', $page);

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

    // ─── Admin: Pending count (for notification badge) ────────────────────────

    public function pendingCount(): JsonResponse
    {
        $approver = $this->approverStaff();
        if (!$approver) return response()->json(['success' => true, 'count' => 0]);

        $role = strtolower($approver->role ?? '');

        if ($role === 'admin') {
            return response()->json(['success' => true, 'count' => Attendance::where('status', 'pending')->count()]);
        }

        // Any incharge sees pending records of everyone in their chain below them.
        $mobiles = $this->getDescendantMobiles($approver->mobile);
        $count = empty($mobiles) ? 0 : Attendance::where('status', 'pending')->whereIn('employee_mobile', $mobiles)->count();

        return response()->json(['success' => true, 'count' => $count]);
    }

    // ─── Admin: Pending list (notification screen) ────────────────────────────

    public function pendingList(): JsonResponse
    {
        $approver = $this->approverStaff();
        if (!$approver) return response()->json(['success' => false, 'message' => 'Unauthorized'], 403);

        $role = strtolower($approver->role ?? '');

        $query = Attendance::with('employee:mobile,name,role')->where('status', 'pending');

        if ($role !== 'admin') {
            // Any incharge sees pending records of everyone in their chain below them.
            $mobiles = $this->getDescendantMobiles($approver->mobile);
            if (empty($mobiles)) {
                return response()->json(['success' => true, 'data' => [], 'meta' => ['current_page' => 1, 'last_page' => 1, 'per_page' => 50, 'total' => 0]]);
            }

            $query->whereIn('employee_mobile', $mobiles);
        }

        $perPage = (int) request()->query('per_page', 50);
        $page    = (int) request()->query('page', 1);

        $p = $query->orderByDesc('date')->paginate($perPage, ['*'], 'page', $page);

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

    // ─── Admin: Employee attendance ───────────────────────────────────────────

    public function adminEmployeeAttendance(string $employeeMobile): JsonResponse
    {
        // Calendar mode: month=YYYY-MM returns every record in that month (no pagination).
        $month = request()->query('month');
        if ($month) {
            try {
                $start = Carbon::createFromFormat('Y-m', $month)->startOfMonth();
            } catch (\Throwable $e) {
                return response()->json(['success' => false, 'message' => 'Invalid month'], 422);
            }
            $end = (clone $start)->endOfMonth();

            $records = Attendance::where('employee_mobile', $employeeMobile)
                ->whereBetween('date', [$start->toDateString(), $end->toDateString()])
                ->orderBy('date')
                ->get();

            return response()->json(['success' => true, 'data' => $records]);
        }

        $perPage = (int) request()->query('per_page', 20);
        $page    = (int) request()->query('page', 1);

        $p = Attendance::where('employee_mobile', $employeeMobile)
            ->orderByDesc('date')
            ->paginate($perPage, ['*'], 'page', $page);

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

    // ─── Admin: Approve ───────────────────────────────────────────────────────

    public function approve(string $id): JsonResponse
    {
        $record = Attendance::find((int) $id);
        if (!$record) {
            return response()->json(['success' => false, 'message' => 'Record not found'], 404);
        }

        if (!$this->authorizeApproval($record)) {
            return response()->json(['success' => false, 'message' => 'You are not authorized to approve this record'], 403);
        }

        $record->update([
            'status'      => 'approved',
            'approved_by' => $this->authMobile(),
            'approved_at' => Carbon::now(),
            'admin_notes' => request()->input('admin_notes'),
        ]);

        return response()->json(['success' => true, 'data' => $record->fresh()]);
    }

    // ─── Admin: Reject ────────────────────────────────────────────────────────

    public function reject(string $id): JsonResponse
    {
        $record = Attendance::find((int) $id);
        if (!$record) {
            return response()->json(['success' => false, 'message' => 'Record not found'], 404);
        }

        if (!$this->authorizeApproval($record)) {
            return response()->json(['success' => false, 'message' => 'You are not authorized to reject this record'], 403);
        }

        $record->update([
            'status'      => 'rejected',
            'admin_notes' => request()->input('admin_notes'),
        ]);

        return response()->json(['success' => true, 'data' => $record->fresh()]);
    }

    // ─── Admin: Get shift settings ────────────────────────────────────────────

    public function getSettings(string $employeeMobile): JsonResponse
    {
        $staff = DeliStaff::where('mobile', $employeeMobile)
            ->select('mobile', 'name', 'punch_in_time', 'punch_out_time', 'grace_minutes', 'approval_required')
            ->first();

        if (!$staff) {
            return response()->json(['success' => false, 'message' => 'Employee not found'], 404);
        }

        return response()->json(['success' => true, 'data' => $staff]);
    }

    // ─── Admin: Update shift settings ─────────────────────────────────────────

    public function updateSettings(Request $request, string $employeeMobile): JsonResponse
    {
        $request->validate([
            'punch_in_time'     => 'required|date_format:H:i',
            'punch_out_time'    => 'required|date_format:H:i',
            'grace_minutes'     => 'required|integer|min:0|max:120',
            'approval_required' => 'sometimes|boolean',
        ]);

        $staff = DeliStaff::where('mobile', $employeeMobile)->first();
        if (!$staff) {
            return response()->json(['success' => false, 'message' => 'Employee not found'], 404);
        }

        $staff->update([
            'punch_in_time'     => $request->input('punch_in_time') . ':00',
            'punch_out_time'    => $request->input('punch_out_time') . ':00',
            'grace_minutes'     => $request->input('grace_minutes'),
            'approval_required' => $request->input('approval_required', true),
        ]);

        return response()->json(['success' => true, 'data' => $staff->only([
            'mobile', 'name', 'punch_in_time', 'punch_out_time', 'grace_minutes', 'approval_required'
        ])]);
    }
}

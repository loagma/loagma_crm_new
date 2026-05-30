<?php

namespace App\Http\Controllers;

use App\Models\AreaAssign;
use App\Models\Attendance;
use App\Models\DeliStaff;
use App\Models\InchargeAssign;
use Carbon\Carbon;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Str;

class AttendanceController extends Controller
{
    // ─── Helpers ─────────────────────────────────────────────────────────────

    private function authMobile(): string
    {
        return auth('api')->userOrFail()->mobile;
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

    // Returns the area IDs assigned to a staff member.
    // employee_id in area_assign_crm is the mobile number stored as int.
    private function getAreaIds(string $mobile): array
    {
        $assign = AreaAssign::where('employee_id', (int) $mobile)->first();
        return $assign ? array_map('intval', $assign->area_ids ?? []) : [];
    }

    // Returns mobile strings of incharges explicitly assigned to this head_incharge.
    private function getAssignedInchargeMobiles(string $headInchargeMobile): array
    {
        $assign = InchargeAssign::where('head_incharge_id', (int) $headInchargeMobile)->first();
        if (!$assign || empty($assign->incharge_ids)) return [];
        // incharge_ids are mobile numbers stored as integers
        return array_map('strval', $assign->incharge_ids);
    }

    // Returns the role-aware approver staff, or null if not found.
    private function approverStaff(): ?DeliStaff
    {
        return DeliStaff::where('mobile', $this->authMobile())->first();
    }

    // True if the approver has authority to approve/reject the given attendance record.
    private function authorizeApproval(Attendance $record): bool
    {
        $approver = $this->approverStaff();
        if (!$approver) return false;

        $approverRole = strtolower($approver->role ?? '');
        if ($approverRole === 'admin') return true;

        $employee = DeliStaff::where('mobile', $record->employee_mobile)->first();
        if (!$employee) return false;

        $employeeRole = strtolower($employee->role ?? '');

        $roleAllowed = match ($approverRole) {
            'head_incharge' => $employeeRole === 'incharge',
            'incharge'      => $employeeRole === 'salesman',
            default         => false,
        };
        if (!$roleAllowed) return false;

        // head_incharge authority is defined by incharge_assign_crm, not areas
        if ($approverRole === 'head_incharge') {
            $assignedMobiles = $this->getAssignedInchargeMobiles($approver->mobile);
            return in_array($employee->mobile, $assignedMobiles);
        }

        // incharge → salesman: authority defined by shared area assignments
        $approverAreas = $this->getAreaIds($approver->mobile);
        if (empty($approverAreas)) return false;

        $employeeAreas = $this->getAreaIds($employee->mobile);
        return !empty(array_intersect($approverAreas, $employeeAreas));
    }

    // Returns mobile numbers of employees (of $targetRole) visible to $approver for approval.
    private function overlappingMobiles(DeliStaff $approver, string $targetRole): array
    {
        $approverRole = strtolower($approver->role ?? '');

        // head_incharge sees only their explicitly assigned incharges
        if ($approverRole === 'head_incharge') {
            return $this->getAssignedInchargeMobiles($approver->mobile);
        }

        // incharge sees salesmen in overlapping areas
        $approverAreas = $this->getAreaIds($approver->mobile);
        if (empty($approverAreas)) return [];

        return DeliStaff::where('role', $targetRole)
            ->get(['mobile'])
            ->filter(fn($s) => !empty(array_intersect($approverAreas, $this->getAreaIds($s->mobile))))
            ->pluck('mobile')
            ->toArray();
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

        $staff  = DeliStaff::where('mobile', $mobile)->first();
        $isLate = $this->isLate($staff);

        // Only accept photo/location for on-time punch-ins
        $data = [
            'employee_mobile'   => $mobile,
            'date'              => $today,
            'punch_in_time'     => Carbon::now(),
            'is_late'           => $isLate,
            'late_reason'       => $isLate ? $request->input('late_reason') : null,
            'punch_in_photo'    => $isLate ? null : $request->input('punch_in_photo'),
            'punch_in_location' => $isLate ? null : $request->input('punch_in_location'),
            'status'            => $isLate ? 'pending' : 'on_time',
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

        $staff      = DeliStaff::where('mobile', $mobile)->first();
        $isEarlyOut = $this->isEarlyOut($staff);

        $workMinutes  = (int) $request->input('total_work_minutes', 0);
        $breakMinutes = (int) $request->input('total_break_minutes', 0);

        $status = $record->status;
        if ($isEarlyOut && $status === 'on_time') {
            $status = 'pending';
        }

        $record->update([
            'punch_out_time'      => Carbon::now(),
            'punch_out_photo'     => $isEarlyOut ? null : $request->input('punch_out_photo'),
            'punch_out_location'  => $isEarlyOut ? null : $request->input('punch_out_location'),
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
            ->select('punch_in_time', 'punch_out_time', 'grace_minutes')
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

        $targetRole = match ($role) {
            'head_incharge' => 'incharge',
            'incharge'      => 'salesman',
            default         => null,
        };

        if ($targetRole === null) return response()->json(['success' => true, 'count' => 0]);

        $mobiles = $this->overlappingMobiles($approver, $targetRole);
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
            $targetRole = match ($role) {
                'head_incharge' => 'incharge',
                'incharge'      => 'salesman',
                default         => null,
            };

            if ($targetRole === null) {
                return response()->json(['success' => true, 'data' => [], 'meta' => ['current_page' => 1, 'last_page' => 1, 'per_page' => 50, 'total' => 0]]);
            }

            $mobiles = $this->overlappingMobiles($approver, $targetRole);
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
            ->select('mobile', 'name', 'punch_in_time', 'punch_out_time', 'grace_minutes')
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
            'punch_in_time'  => 'required|date_format:H:i',
            'punch_out_time' => 'required|date_format:H:i',
            'grace_minutes'  => 'required|integer|min:0|max:120',
        ]);

        $staff = DeliStaff::where('mobile', $employeeMobile)->first();
        if (!$staff) {
            return response()->json(['success' => false, 'message' => 'Employee not found'], 404);
        }

        $staff->update([
            'punch_in_time'  => $request->input('punch_in_time') . ':00',
            'punch_out_time' => $request->input('punch_out_time') . ':00',
            'grace_minutes'  => $request->input('grace_minutes'),
        ]);

        return response()->json(['success' => true, 'data' => $staff->only([
            'mobile', 'name', 'punch_in_time', 'punch_out_time', 'grace_minutes'
        ])]);
    }
}

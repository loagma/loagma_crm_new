<?php

namespace App\Http\Controllers;

use App\Models\Attendance;
use App\Models\DeliStaff;
use Carbon\Carbon;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Tymon\JWTAuth\Facades\JWTAuth;

class AttendanceController extends Controller
{
    // ─── Helpers ─────────────────────────────────────────────────────────────

    private function authMobile(): string
    {
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

        $data = [
            'employee_mobile' => $mobile,
            'date'            => $today,
            'punch_in_time'   => Carbon::now(),
            'is_late'         => $isLate,
            'late_reason'     => $isLate ? $request->input('late_reason') : null,
            'status'          => $isLate ? 'pending' : 'on_time',
            'break_details'   => [],
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

        // If previously on_time but now early out, bump to pending
        $status = $record->status;
        if ($isEarlyOut && $status === 'on_time') {
            $status = 'pending';
        }

        $record->update([
            'punch_out_time'      => Carbon::now(),
            'is_early_out'        => $isEarlyOut,
            'early_out_reason'    => $isEarlyOut ? $request->input('early_out_reason') : null,
            'total_work_minutes'  => $workMinutes,
            'total_break_minutes' => $breakMinutes,
            'status'              => $status,
        ]);

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
            // End the most recent open break of this type
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

        // Also return the employee's shift settings
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

        $adminMobile = $this->authMobile();

        $record->update([
            'status'      => 'approved',
            'approved_by' => $adminMobile,
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

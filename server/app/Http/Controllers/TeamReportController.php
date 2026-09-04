<?php

namespace App\Http\Controllers;

use App\Models\ActionLog;
use App\Models\Attendance;
use App\Models\CallLog;
use App\Models\DeliStaff;
use App\Models\LeadsAccount;
use App\Models\LocationPing;
use App\Support\Hierarchy;
use Illuminate\Http\JsonResponse;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use Tymon\JWTAuth\Facades\JWTAuth;

/**
 * Read-only "Team Report" for seniors — a single day-scoped rollup of every
 * subordinate's activity: attendance punch in/out + route distance, completed
 * shop visits, and calls. No mutations, no approvals.
 *
 * Scoping mirrors TelecallerController::teamAgents / teamCallHistory and
 * AttendanceController::pendingList: admin sees every field-staff row
 * unscoped, everyone else sees only their own hierarchy subtree
 * (Hierarchy::subtreeForViewer). The route also carries a role: gate.
 *
 * Timezone: action_log_crm.check_out_at, call_log_crm.called_at and the
 * attendance_crm.date / location_pings_crm.date columns are all app-timezone
 * (Asia/Kolkata) — day bounds are built in that zone; a UTC boundary would
 * clip 5h30m off each end (same convention as teamAgents()).
 */
class TeamReportController extends Controller
{
    /** Guard against a range so wide the per-row attendance fetch gets silly. */
    private const MAX_RANGE_DAYS = 92;

    private function viewer(): DeliStaff
    {
        $mobile = (string) JWTAuth::parseToken()->authenticate()->mobile;
        $staff  = DeliStaff::where('mobile', $mobile)->first();
        abort_if(!$staff, 403, 'Unauthorized');
        return $staff;
    }

    /** [$fromCarbon, $toCarbon, $fromYmd, $toYmd] from ?from=&to= (default today). */
    private function range(): array
    {
        $data = request()->validate([
            'from' => 'nullable|date_format:Y-m-d',
            'to'   => 'nullable|date_format:Y-m-d',
        ]);

        $tz    = config('app.timezone');
        $today = Carbon::today($tz)->toDateString();

        $fromYmd = $data['from'] ?? $today;
        $toYmd   = $data['to']   ?? $fromYmd;
        if ($toYmd < $fromYmd) {
            [$fromYmd, $toYmd] = [$toYmd, $fromYmd];
        }

        $from = Carbon::createFromFormat('Y-m-d', $fromYmd, $tz)->startOfDay();
        $to   = Carbon::createFromFormat('Y-m-d', $toYmd, $tz)->endOfDay();

        // Clamp an absurd window rather than 422 — the client only ever sends
        // its own presets, but a hand-crafted range shouldn't hang the DB.
        if ($from->diffInDays($to) > self::MAX_RANGE_DAYS) {
            $from = (clone $to)->subDays(self::MAX_RANGE_DAYS)->startOfDay();
            $fromYmd = $from->toDateString();
        }

        return [$from, $to, $fromYmd, $toYmd];
    }

    // ── Roster ───────────────────────────────────────────────────────────────

    public function roster(): JsonResponse
    {
        $viewer = $this->viewer();
        $isAdmin = strtolower(trim($viewer->role ?? '')) === 'admin';
        [$from, $to, $fromYmd, $toYmd] = $this->range();

        $scope = Hierarchy::subtreeForViewer($viewer); // null = admin/unscoped

        $rosterQ = DeliStaff::query()
            ->whereRaw("LOWER(TRIM(role)) IN ('salesman', 'telecaller')");

        if ($scope !== null) {
            if (empty($scope)) {
                return $this->emptyRoster($viewer, $fromYmd, $toYmd, $isAdmin);
            }
            $rosterQ->whereIn('mobile', $scope);
        }

        if (!request()->boolean('include_locked')) {
            $rosterQ->where(fn ($q) => $q->whereNull('is_locked')->orWhere('is_locked', 0));
        }

        $roster = $rosterQ->orderBy('name')->get(['mobile', 'name', 'role', 'city', 'is_locked']);
        if ($roster->isEmpty()) {
            return $this->emptyRoster($viewer, $fromYmd, $toYmd, $isAdmin);
        }

        $mobiles           = $roster->pluck('mobile')->map(fn ($m) => (string) $m)->all();
        $telecallerMobiles = $roster->filter(fn ($s) => strtolower(trim($s->role ?? '')) === 'telecaller')
            ->pluck('mobile')->map(fn ($m) => (string) $m)->all();

        $todayYmd = Carbon::today(config('app.timezone'))->toDateString();

        // ── visits (completed check-outs) ──
        $visitAgg = ActionLog::whereIn('employee_mobile', $mobiles)
            ->whereRaw('COALESCE(check_out_at, created_at) BETWEEN ? AND ?', [$from, $to])
            ->groupBy('employee_mobile')
            ->selectRaw('employee_mobile,
                COUNT(*) AS c,
                COALESCE(SUM(duration_seconds), 0) AS dur,
                COALESCE(SUM(payment_collected), 0) AS pay')
            ->get()->keyBy('employee_mobile');

        $visitOutcomes = ActionLog::whereIn('employee_mobile', $mobiles)
            ->whereRaw('COALESCE(check_out_at, created_at) BETWEEN ? AND ?', [$from, $to])
            ->whereNotNull('outcome_slug')->where('outcome_slug', '<>', '')
            ->groupBy('employee_mobile', 'outcome_slug')
            ->selectRaw('employee_mobile, outcome_slug, COUNT(*) AS c')
            ->get()
            ->groupBy('employee_mobile');

        // ── calls (telecallers only) ──
        $callAgg = collect();
        if (!empty($telecallerMobiles)) {
            $callAgg = CallLog::whereIn('employee_mobile', $telecallerMobiles)
                ->whereBetween('called_at', [$from, $to])
                ->groupBy('employee_mobile')
                ->selectRaw("employee_mobile,
                    COUNT(*) AS c,
                    SUM(CASE WHEN call_outcome = 'answered' THEN 1 ELSE 0 END) AS connected,
                    COALESCE(SUM(duration_seconds), 0) AS talk,
                    SUM(CASE WHEN recording_url IS NOT NULL AND recording_url <> '' THEN 1 ELSE 0 END) AS rec")
                ->get()->keyBy('employee_mobile');
        }

        // ── attendance (per-row, reduced in PHP → aggregate + latest-day snapshot) ──
        $attRows = Attendance::whereIn('employee_mobile', $mobiles)
            ->whereBetween('date', [$fromYmd, $toYmd])
            ->orderByDesc('date')
            ->get(['employee_mobile', 'date', 'status', 'punch_in_time', 'punch_out_time',
                   'is_late', 'is_early_out', 'total_work_minutes', 'total_break_minutes',
                   'total_distance_km', 'was_interrupted', 'auto_closed'])
            ->groupBy('employee_mobile');

        // ── has_route ──
        $routeMobiles = LocationPing::whereIn('employee_mobile', $mobiles)
            ->whereBetween('date', [$fromYmd, $toYmd])
            ->distinct()->pluck('employee_mobile')
            ->map(fn ($m) => (string) $m)->flip();

        $rangeDays = $from->copy()->startOfDay()->diffInDays($to->copy()->startOfDay()) + 1;
        $isSingleDay = $fromYmd === $toYmd;

        $employees = $roster->map(function (DeliStaff $s) use (
            $visitAgg, $visitOutcomes, $callAgg, $attRows, $routeMobiles,
            $todayYmd, $rangeDays
        ) {
            $mob  = (string) $s->mobile;
            $role = strtolower(trim($s->role ?? ''));

            $v = $visitAgg->get($mob);
            $visits = [
                'count'             => (int) ($v->c ?? 0),
                'duration_seconds'  => (int) ($v->dur ?? 0),
                'payment_collected' => (float) ($v->pay ?? 0),
                'outcomes'          => ($visitOutcomes->get($mob) ?? collect())
                    ->mapWithKeys(fn ($r) => [$r->outcome_slug => (int) $r->c])->all(),
            ];

            $calls = null;
            if ($role === 'telecaller') {
                $c = $callAgg->get($mob);
                $calls = [
                    'count'             => (int) ($c->c ?? 0),
                    'connected'         => (int) ($c->connected ?? 0),
                    'talk_time_seconds' => (int) ($c->talk ?? 0),
                    'recordings'        => (int) ($c->rec ?? 0),
                ];
            }

            $rows = $attRows->get($mob);
            $attendance = null;
            if ($rows && $rows->isNotEmpty()) {
                $latest = $rows->first(); // already date-desc
                $attendance = [
                    'days_present'      => $rows->count(),
                    'days_in_range'     => $rangeDays,
                    'work_minutes'      => (int) $rows->sum('total_work_minutes'),
                    'break_minutes'     => (int) $rows->sum('total_break_minutes'),
                    'distance_km'       => round((float) $rows->sum('total_distance_km'), 2),
                    'late_count'        => $rows->where('is_late', true)->count(),
                    'early_out_count'   => $rows->where('is_early_out', true)->count(),
                    'latest'            => [
                        'date'            => optional($latest->date)->toDateString(),
                        'status'          => $latest->status,
                        'punch_in_time'   => optional($latest->punch_in_time)->toIso8601String(),
                        'punch_out_time'  => optional($latest->punch_out_time)->toIso8601String(),
                        'is_late'         => (bool) $latest->is_late,
                        'was_interrupted' => (bool) $latest->was_interrupted,
                        'auto_closed'     => (bool) $latest->auto_closed,
                        'on_duty'         => $latest->punch_out_time === null
                            && optional($latest->date)->toDateString() === $todayYmd,
                    ],
                ];
            }

            return [
                'mobile'     => $mob,
                'name'       => $s->name ?: $mob,
                'role'       => $role,
                'city'       => $s->city,
                'is_locked'  => (bool) $s->is_locked,
                'attendance' => $attendance,
                'visits'     => $visits,
                'calls'      => $calls,
                'has_route'  => $routeMobiles->has($mob),
            ];
        })->values();

        $rosterHasSalesman   = $roster->contains(fn ($s) => strtolower(trim($s->role ?? '')) === 'salesman');
        $rosterHasTelecaller = !empty($telecallerMobiles);

        return response()->json([
            'success' => true,
            'data' => [
                'range' => [
                    'from'          => $fromYmd,
                    'to'            => $toYmd,
                    'is_single_day' => $isSingleDay,
                    'is_today'      => $isSingleDay && $fromYmd === $todayYmd,
                ],
                'scope' => [
                    'is_admin'  => $isAdmin,
                    'team_size' => $roster->count(),
                ],
                'capabilities' => [
                    'show_calls' => $rosterHasTelecaller,
                    'show_route' => $rosterHasSalesman && $viewer->role !== 'teleadmin',
                ],
                'totals' => [
                    'employees' => $employees->count(),
                    'present'   => $employees->filter(fn ($e) => $e['attendance'] !== null)->count(),
                    'on_duty'   => $employees->filter(fn ($e) => data_get($e, 'attendance.latest.on_duty', false))->count(),
                    'visits'    => (int) $employees->sum(fn ($e) => data_get($e, 'visits.count', 0)),
                    'calls'     => (int) $employees->sum(fn ($e) => data_get($e, 'calls.count', 0)),
                    'payment_collected' => round((float) $employees->sum(fn ($e) => data_get($e, 'visits.payment_collected', 0)), 2),
                    'distance_km'       => round((float) $employees->sum(fn ($e) => data_get($e, 'attendance.distance_km', 0)), 2),
                ],
                'employees' => $employees,
            ],
        ]);
    }

    private function emptyRoster(DeliStaff $viewer, string $fromYmd, string $toYmd, bool $isAdmin): JsonResponse
    {
        $todayYmd = Carbon::today(config('app.timezone'))->toDateString();
        return response()->json([
            'success' => true,
            'data' => [
                'range'   => ['from' => $fromYmd, 'to' => $toYmd,
                              'is_single_day' => $fromYmd === $toYmd,
                              'is_today' => $fromYmd === $toYmd && $fromYmd === $todayYmd],
                'scope'   => ['is_admin' => $isAdmin, 'team_size' => 0],
                'capabilities' => ['show_calls' => false, 'show_route' => false],
                'totals'  => ['employees' => 0, 'present' => 0, 'on_duty' => 0,
                              'visits' => 0, 'calls' => 0, 'payment_collected' => 0, 'distance_km' => 0],
                'employees' => [],
            ],
        ]);
    }

    // ── One employee's day(s) ────────────────────────────────────────────────

    public function employee(string $employeeMobile): JsonResponse
    {
        $viewer = $this->viewer();
        $isAdmin = strtolower(trim($viewer->role ?? '')) === 'admin';

        if (!$isAdmin) {
            $allowed = Hierarchy::descendantMobilesFast((string) $viewer->mobile);
            if (!in_array((string) $employeeMobile, $allowed, true)) {
                return response()->json(['success' => false, 'message' => 'That employee is not in your team'], 403);
            }
        }

        $target = DeliStaff::where('mobile', $employeeMobile)->first(['mobile', 'name', 'role', 'city']);
        if (!$target) {
            return response()->json(['success' => false, 'message' => 'Employee not found'], 404);
        }

        [$from, $to, $fromYmd, $toYmd] = $this->range();

        // ── attendance rows (one per day, full shape for AttendanceDayCard) ──
        $attendance = Attendance::where('employee_mobile', $employeeMobile)
            ->whereBetween('date', [$fromYmd, $toYmd])
            ->orderByDesc('date')
            ->get();

        $routeDays = LocationPing::where('employee_mobile', $employeeMobile)
            ->whereBetween('date', [$fromYmd, $toYmd])
            ->distinct()->pluck('date')
            ->map(fn ($d) => Carbon::parse($d)->toDateString())->flip();

        $attendance = $attendance->map(function (Attendance $a) use ($routeDays) {
            $row = $a->toArray();
            $row['has_route'] = $routeDays->has(optional($a->date)->toDateString());
            return $row;
        })->values();

        // ── visits ──
        $visitRows = ActionLog::where('employee_mobile', $employeeMobile)
            ->whereRaw('COALESCE(check_out_at, created_at) BETWEEN ? AND ?', [$from, $to])
            ->orderByDesc('check_out_at')->orderByDesc('created_at')
            ->limit(200)->get();
        $accounts = $this->enrichAccounts($visitRows->concat(
            CallLog::where('employee_mobile', $employeeMobile)
                ->whereBetween('called_at', [$from, $to])
                ->orderByDesc('called_at')->limit(200)->get()
        ));

        $visits = $visitRows->map(fn (ActionLog $r) => [
            'id'                 => $r->id,
            'role'               => $r->role,
            'account_id'         => $r->account_id,
            'account_type'       => $r->account_type,
            'account_name'       => $accounts[$r->account_id]['name'] ?? null,
            'account_phone'      => $accounts[$r->account_id]['phone'] ?? null,
            'account_area'       => $accounts[$r->account_id]['area'] ?? null,
            'check_in_at'        => optional($r->check_in_at)->toIso8601String(),
            'check_out_at'       => optional($r->check_out_at)->toIso8601String(),
            'duration_seconds'   => $r->duration_seconds,
            'check_in_lat'       => $r->check_in_lat,
            'check_in_lng'       => $r->check_in_lng,
            'check_out_lat'      => $r->check_out_lat,
            'check_out_lng'      => $r->check_out_lng,
            'status'             => $r->status,
            'outcome_slug'       => $r->outcome_slug,
            'outcome_name'       => $r->outcome_name,
            'call_outcome'       => $r->call_outcome,
            'call_status'        => $r->call_status,
            'order_no'           => $r->order_no,
            'general_notes'      => $r->general_notes,
            'conversation_notes' => $r->conversation_notes,
            'discussion_points'  => $r->discussion_points,
            'market_note'        => $r->market_note,
            'notes_related_to'   => $r->notes_related_to,
            'payment_collected'  => $r->payment_collected,
            'payment_mode'       => $r->payment_mode,
            'follow_up_date'     => optional($r->follow_up_date)->toDateString(),
            'follow_up_note'     => $r->follow_up_note,
            'images'             => $r->images ?? [],
            'created_at'         => optional($r->created_at)->toIso8601String(),
        ])->values();

        // ── calls ──
        $callRows = CallLog::where('employee_mobile', $employeeMobile)
            ->whereBetween('called_at', [$from, $to])
            ->orderByDesc('called_at')->limit(200)->get();

        $calls = $callRows->map(fn (CallLog $l) => [
            'id'               => $l->id,
            'account_id'       => $l->account_id,
            'account_type'     => $l->account_type,
            'account_name'     => $accounts[$l->account_id]['name'] ?? null,
            'account_phone'    => $accounts[$l->account_id]['phone'] ?? null,
            'outcome'          => $l->call_outcome,
            'notes'            => $l->notes,
            'called_at'        => optional($l->called_at)->toIso8601String(),
            'source'           => $l->source,
            'direction'        => $l->direction,
            'duration_seconds' => $l->duration_seconds,
            'has_recording'    => !empty($l->recording_url),
        ])->values();

        // ── timeline (light, merged, newest first) ──
        $timeline = collect();
        foreach ($attendance as $a) {
            if (!empty($a['punch_in_time'])) {
                $timeline->push(['kind' => 'punch_in', 'at' => $a['punch_in_time'], 'label' => 'Punched in']);
            }
            if (!empty($a['punch_out_time'])) {
                $timeline->push(['kind' => 'punch_out', 'at' => $a['punch_out_time'], 'label' => 'Punched out']);
            }
        }
        foreach ($visits as $v) {
            $timeline->push([
                'kind'  => 'visit',
                'at'    => $v['check_out_at'] ?? $v['check_in_at'] ?? $v['created_at'],
                'label' => trim(($v['account_name'] ?? 'Visit') . ' · ' . ($v['outcome_name'] ?: $v['outcome_slug'] ?: 'visit')),
                'ref'   => $v['id'],
            ]);
        }
        foreach ($calls as $c) {
            $timeline->push([
                'kind'  => 'call',
                'at'    => $c['called_at'],
                'label' => trim(($c['account_name'] ?? 'Call') . ' · ' . ($c['outcome'] ?: 'call')),
                'ref'   => $c['id'],
            ]);
        }
        $timeline = $timeline->filter(fn ($t) => !empty($t['at']))
            ->sortByDesc('at')->values();

        return response()->json([
            'success' => true,
            'data' => [
                'employee' => [
                    'mobile' => (string) $target->mobile,
                    'name'   => $target->name ?: (string) $target->mobile,
                    'role'   => strtolower(trim($target->role ?? '')),
                    'city'   => $target->city,
                ],
                'range'      => ['from' => $fromYmd, 'to' => $toYmd, 'is_single_day' => $fromYmd === $toYmd],
                'attendance' => $attendance,
                'visits'     => $visits,
                'calls'      => $calls,
                'timeline'   => $timeline,
            ],
        ]);
    }

    /**
     * account_id => {name, phone, area} for a mixed collection of ActionLog /
     * CallLog rows. Same two sources as TelecallerController::enrich(): leads in
     * LeadsAccount_crm, customers in the legacy `user` table keyed by userid.
     */
    private function enrichAccounts($rows): array
    {
        $leadIds = $rows->where('account_type', 'lead')->pluck('account_id')->filter()->unique()->values()->all();
        $custIds = $rows->where('account_type', 'customer')->pluck('account_id')->filter()->unique()->values()->all();

        $map = [];

        if (!empty($leadIds)) {
            foreach (LeadsAccount::whereIn('id', $leadIds)
                ->get(['id', 'businessName', 'personName', 'contactNumber', 'area']) as $l) {
                $map[(string) $l->id] = [
                    'name'  => $l->businessName ?: $l->personName,
                    'phone' => $l->contactNumber,
                    'area'  => $l->area,
                ];
            }
        }

        if (!empty($custIds)) {
            foreach (DB::table('user')->whereIn('userid', $custIds)
                ->get(['userid', 'name', 'shop_name', 'contactno', 'city']) as $c) {
                $map[(string) $c->userid] = [
                    'name'  => $c->shop_name ?: $c->name,
                    'phone' => $c->contactno,
                    'area'  => $c->city,
                ];
            }
        }

        return $map;
    }
}

<?php

namespace App\Http\Controllers;

use App\Models\Attendance;
use App\Models\DeliStaff;
use App\Models\LocationPing;
use App\Support\RouteDistance;
use App\Support\RouteSnapper;
use Carbon\Carbon;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Tymon\JWTAuth\Facades\JWTAuth;

/**
 * TIMEZONE CONVENTION (applies to all tracking + attendance code; see
 * docs/tracking-testing-guide.md §Timezone):
 *
 *  - DB datetime columns store naive Asia/Kolkata (config('app.timezone'))
 *    wall-clock. The DB session timezone is UTC (`SYSTEM`), so DB-side time
 *    functions (NOW(), CURRENT_TIMESTAMP defaults) must NEVER be used against
 *    these columns — build times in PHP.
 *  - Every timestamp arriving from a client (ping recorded_at, ?since=) is
 *    UTC ISO-8601 with Z; normalize with
 *    Carbon::parse(...)->setTimezone(config('app.timezone')) BEFORE any store
 *    or comparison.
 *  - Outbound: Laravel's default serializeDate converts datetime casts to
 *    UTC-Z; Flutter must DateTime.parse(...) (never substring) and .toLocal()
 *    for display. Date-only columns use the 'date:Y-m-d' cast — the default
 *    UTC-Z serialization would shift IST dates to the previous day.
 */
class TrackingController extends Controller
{
    private const MAX_ACCURACY_METERS = 50;
    private const MAX_SPEED_KMH = 150;
    // Same threshold the distance gap-exclusion uses — keep them in lockstep.
    private const INTERRUPTED_GAP_MINUTES = RouteDistance::GAP_MINUTES;

    // ─── Helpers ─────────────────────────────────────────────────────────────

    private function authMobile(): string
    {
        // Same proven pattern as AttendanceController::authMobile() — the
        // default guard is web/session, so auth() resolves to null here.
        return JWTAuth::parseToken()->authenticate()->mobile;
    }

    // ─── Employee: Batch ping ingest ──────────────────────────────────────────

    public function ping(Request $request): JsonResponse
    {
        $mobile = $this->authMobile();

        $validated = $request->validate([
            'pings'               => 'required|array|min:1',
            'pings.*.lat'         => 'required|numeric|between:-90,90',
            'pings.*.lng'         => 'required|numeric|between:-180,180',
            'pings.*.recorded_at' => 'required|date',
            'pings.*.accuracy'    => 'nullable|numeric',
            'pings.*.speed'       => 'nullable|numeric',
            'pings.*.heading'     => 'nullable|numeric|between:0,360',
            'pings.*.battery'     => 'nullable|integer|min:0|max:100',
            'pings.*.is_mock'     => 'nullable|boolean',
        ]);

        $today = Carbon::today()->toDateString();

        // Used for the opportunistic prune below: only sweep old rows once,
        // on the first ping of a new day, instead of on every single request.
        $isFirstPingToday = !LocationPing::where('employee_mobile', $mobile)
            ->where('date', $today)
            ->exists();

        // Anchor for teleport-jump detection: the most recent ping already on
        // record. Advanced as we walk the batch so each ping is checked
        // against the one immediately before it, not just the pre-batch ping.
        $anchor = LocationPing::where('employee_mobile', $mobile)
            ->orderByDesc('recorded_at')
            ->first();
        $anchorLat = $anchor?->lat;
        $anchorLng = $anchor?->lng;
        $anchorAt  = $anchor ? Carbon::parse($anchor->recorded_at) : null;

        $rows = [];
        foreach (collect($validated['pings'])->sortBy('recorded_at') as $p) {
            $accuracy = $p['accuracy'] ?? null;
            if ($accuracy !== null && $accuracy > self::MAX_ACCURACY_METERS) {
                continue; // too imprecise — drop
            }

            // Client sends UTC; store in app timezone so these columns read
            // consistently with every other datetime in attendance_crm.
            $recordedAt = Carbon::parse($p['recorded_at'])->setTimezone(config('app.timezone'));

            if ($anchorAt) {
                $seconds = abs($recordedAt->diffInSeconds($anchorAt));
                if ($seconds > 0) {
                    $km = RouteDistance::haversineKm($anchorLat, $anchorLng, (float) $p['lat'], (float) $p['lng']);
                    $kmh = $km / ($seconds / 3600);
                    if ($kmh > self::MAX_SPEED_KMH) {
                        continue; // teleport jump — drop
                    }
                }
            }

            $rows[] = [
                'employee_mobile' => $mobile,
                'date'            => $recordedAt->toDateString(),
                'lat'             => $p['lat'],
                'lng'             => $p['lng'],
                'accuracy'        => $accuracy,
                'speed'           => $p['speed'] ?? null,
                'heading'         => $p['heading'] ?? null,
                'battery'         => $p['battery'] ?? null,
                'is_mock'         => $p['is_mock'] ?? false,
                'recorded_at'     => $recordedAt,
            ];

            $anchorLat = (float) $p['lat'];
            $anchorLng = (float) $p['lng'];
            $anchorAt  = $recordedAt;
        }

        if (empty($rows)) {
            return response()->json(['success' => true, 'data' => ['saved' => 0]]);
        }

        LocationPing::insert($rows);

        $latestAt = collect($rows)->max(fn ($r) => $r['recorded_at']);

        $attendance = Attendance::where('employee_mobile', $mobile)->where('date', $today)->first();
        if ($attendance) {
            $prevPingAt = $attendance->last_ping_at
                ? Carbon::parse($attendance->last_ping_at)
                : null;

            // Forward-only gap check and monotonic last_ping_at: a delayed
            // offline backlog can arrive AFTER newer live points — it must
            // neither flag a false interruption nor move last_ping_at back.
            $wasInterrupted = $attendance->was_interrupted;
            if ($prevPingAt && $latestAt->greaterThan($prevPingAt)) {
                $gapMinutes = $prevPingAt->diffInMinutes($latestAt);
                if ($gapMinutes > self::INTERRUPTED_GAP_MINUTES) {
                    $wasInterrupted = true;
                }
            }

            $attendance->update([
                'last_ping_at'    => $prevPingAt && $prevPingAt->greaterThan($latestAt)
                    ? $prevPingAt
                    : $latestAt,
                'was_interrupted' => $wasInterrupted,
            ]);
        }

        if ($isFirstPingToday) {
            $cutoff = Carbon::today()->subDays(config('tracking.retention_days'))->toDateString();
            LocationPing::where('employee_mobile', $mobile)
                ->where('date', '<', $cutoff)
                ->delete();
        }

        return response()->json(['success' => true, 'data' => ['saved' => count($rows)]]);
    }

    // ─── Admin: Live on-duty salesmen ─────────────────────────────────────────

    public function live(): JsonResponse
    {
        $this->autoCloseStaleShifts();

        $today = Carbon::today()->toDateString();

        $open = Attendance::with('employee:mobile,name,role')
            ->where('date', $today)
            ->whereNotNull('punch_in_time')
            ->whereNull('punch_out_time')
            ->get();

        $data = $open->map(function (Attendance $a) use ($today) {
            // TODO(scale): one pings query per on-duty salesman. Fine at the
            // current fleet size; aggregate/cache when the list grows.
            $pings = LocationPing::where('employee_mobile', $a->employee_mobile)
                ->where('date', $today)
                ->orderBy('recorded_at')
                ->get(['lat', 'lng', 'battery', 'is_mock', 'recorded_at']);

            $last  = $pings->last();
            $stats = RouteDistance::stats($pings);

            return [
                'employee_mobile' => $a->employee_mobile,
                'name'            => $a->employee->name ?? null,
                'punch_in_time'   => $a->punch_in_time,
                'start'           => $a->punch_in_location, // {lat, lng} captured at punch-in
                'last_ping_at'    => $a->last_ping_at,
                'was_interrupted' => $a->was_interrupted,
                'lat'             => $last?->lat,
                'lng'             => $last?->lng,
                'battery'         => $last?->battery,
                'is_mock'         => (bool) ($last?->is_mock),
                'distance_km'     => $stats['distance_km'],
                'has_gaps'        => $stats['has_gaps'],
            ];
        })->values();

        return response()->json(['success' => true, 'data' => $data]);
    }

    // ─── Admin: Roster for a past date ────────────────────────────────────────
    // Historical analog of live(): everyone who was on duty on a given date,
    // with their on-duty window and distance. Feeds the date-first history
    // browser (calendar button on the live-salesmen screen). One-shot — the
    // client must NOT poll this.

    public function roster(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'date' => 'required|date_format:Y-m-d',
        ]);
        $date = $validated['date'];

        $records = Attendance::with('employee:mobile,name,role')
            ->where('date', $date)
            ->whereNotNull('punch_in_time')
            ->get();

        $data = $records->map(function (Attendance $a) use ($date) {
            $isClosed = (bool) $a->punch_out_time;

            // Prefer the frozen distance; otherwise compute from that day's
            // pings and — like route() — freeze it once the shift is closed so
            // later loads skip the ping query.
            // TODO(scale): one pings query per not-yet-frozen salesman. Fine at
            // the current fleet size; aggregate/cache when the list grows.
            $distanceKm = $a->total_distance_km;
            $hasGaps    = (bool) $a->was_interrupted;
            if ($distanceKm === null) {
                $pings = LocationPing::where('employee_mobile', $a->employee_mobile)
                    ->where('date', $date)
                    ->orderBy('recorded_at')
                    ->get(['lat', 'lng', 'recorded_at']);
                $stats      = RouteDistance::stats($pings);
                $distanceKm = $stats['distance_km'];
                $hasGaps    = $stats['has_gaps'] || $hasGaps;
                if ($isClosed && $pings->isNotEmpty()) {
                    $a->update(['total_distance_km' => $distanceKm]);
                }
            }

            return [
                'employee_mobile' => $a->employee_mobile,
                'name'            => $a->employee->name ?? null,
                'punch_in_time'   => $a->punch_in_time,
                'punch_out_time'  => $a->punch_out_time,
                'was_interrupted' => (bool) $a->was_interrupted,
                'auto_closed'     => (bool) $a->auto_closed,
                'distance_km'     => $distanceKm,
                'has_gaps'        => $hasGaps,
            ];
        })
        ->sortBy(fn ($r) => strtolower((string) ($r['name'] ?? '')))
        ->values();

        return response()->json(['success' => true, 'data' => $data]);
    }

    // ─── Admin: Live route (delta polling) ───────────────────────────────────
    // First call (no ?since=) returns today's full trail for the salesman;
    // subsequent calls pass ?since=<last recorded_at> and get only new points,
    // so the map appends instead of redrawing.

    public function liveRoute(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'mobile' => 'required|string|max:20',
            'since'  => 'nullable|date',
        ]);

        $today  = Carbon::today()->toDateString();
        $mobile = $validated['mobile'];

        // Full day's trail in one query: the distance total always spans the
        // whole day, while the returned points honor ?since= (delta polling).
        // accuracy + speed feed the admin map polish: the accuracy circle and
        // the moving/stationary rotation rule for the vehicle marker.
        $all = LocationPing::where('employee_mobile', $mobile)
            ->where('date', $today)
            ->orderBy('recorded_at')
            ->get(['lat', 'lng', 'heading', 'speed', 'accuracy', 'battery', 'is_mock', 'recorded_at']);

        $stats = RouteDistance::stats($all);

        $points = $all;
        if (!empty($validated['since'])) {
            // Client echoes back the UTC-serialized recorded_at; the column
            // stores app-timezone wall-clock time, so normalize before comparing.
            $since  = Carbon::parse($validated['since'])->setTimezone(config('app.timezone'));
            $points = $all->filter(fn ($p) => $p->recorded_at->greaterThan($since))->values();
        }

        $attendance = Attendance::where('employee_mobile', $mobile)
            ->where('date', $today)
            ->first();

        return response()->json([
            'success' => true,
            'data'    => [
                'points'       => $points,
                'is_active'    => (bool) ($attendance && $attendance->punch_in_time && !$attendance->punch_out_time),
                'start'        => $attendance?->punch_in_location,
                'last_ping_at' => $attendance?->last_ping_at,
                'distance_km'  => $stats['distance_km'],
                'has_gaps'     => $stats['has_gaps'],
            ],
        ]);
    }

    // ─── Admin: Historical route for one day (Phase 5) ────────────────────────

    public function route(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'mobile' => 'required|string|max:20',
            'date'   => 'required|date_format:Y-m-d',
        ]);

        $mobile = $validated['mobile'];
        $date   = $validated['date'];

        $points = LocationPing::where('employee_mobile', $mobile)
            ->where('date', $date)
            ->orderBy('recorded_at')
            ->get(['lat', 'lng', 'heading', 'battery', 'is_mock', 'recorded_at']);

        $attendance = Attendance::where('employee_mobile', $mobile)
            ->where('date', $date)
            ->first();

        $stats    = RouteDistance::stats($points);
        $isClosed = (bool) ($attendance && $attendance->punch_out_time);

        // Lazy fill: freeze the distance onto the attendance row once, but only
        // after the shift is closed — storing mid-shift would freeze a partial.
        if ($attendance && $isClosed && $attendance->total_distance_km === null) {
            $attendance->update(['total_distance_km' => $stats['distance_km']]);
        }

        // Road-snapping (display only, CLOSED days only — a live route keeps
        // growing, so snapping it would freeze a partial). Successes are
        // cached on the attendance row so each day is snapped at most once;
        // failures fall back to raw and retry on a later view.
        $snappedSegments = null;
        if ($attendance && $isClosed && $points->isNotEmpty()) {
            $snappedSegments = $attendance->route_snapped;
            if ($snappedSegments === null && config('tracking.osrm_url')) {
                $snappedSegments = RouteSnapper::snap($points);
                if ($snappedSegments !== null) {
                    $attendance->update(['route_snapped' => $snappedSegments]);
                }
            }
        }

        return response()->json([
            'success' => true,
            'data'    => [
                'points'            => $points,
                'start'             => $attendance?->punch_in_location,
                'end'               => $attendance?->punch_out_location,
                'punch_in_time'     => $attendance?->punch_in_time,
                'punch_out_time'    => $attendance?->punch_out_time,
                'was_interrupted'   => (bool) ($attendance?->was_interrupted),
                'auto_closed'       => (bool) ($attendance?->auto_closed),
                'total_distance_km' => $attendance?->total_distance_km ?? $stats['distance_km'],
                'has_gaps'          => $stats['has_gaps'],
                'is_active'         => (bool) ($attendance && $attendance->punch_in_time && !$attendance->punch_out_time),
                'snapped'           => $snappedSegments !== null,
                'snapped_segments'  => $snappedSegments,
            ],
        ]);
    }

    // Close-on-read: any punched-in-never-punched-out row from a previous day,
    // or one whose tracking went silent for longer than the auto-close window,
    // is closed as "forgot to punch out". Runs on every live() call so the
    // fleet list never shows ghosts — no cron needed.
    private function autoCloseStaleShifts(): void
    {
        $today  = Carbon::today()->toDateString();
        $cutoff = Carbon::now()->subHours(config('tracking.autoclose_hours'));

        $stale = Attendance::whereNotNull('punch_in_time')
            ->whereNull('punch_out_time')
            ->where(function ($q) use ($today, $cutoff) {
                $q->where('date', '<', $today)
                  ->orWhere(function ($q2) use ($cutoff) {
                      $q2->whereNotNull('last_ping_at')->where('last_ping_at', '<', $cutoff);
                  })
                  ->orWhere(function ($q3) use ($cutoff) {
                      $q3->whereNull('last_ping_at')->where('punch_in_time', '<', $cutoff);
                  });
            })
            ->get();

        foreach ($stale as $record) {
            $closeAt = $record->last_ping_at;

            if (!$closeAt) {
                // Never pinged: fall back to that day's shift end, clamped so we
                // never set a punch-out before the punch-in itself.
                $staff    = DeliStaff::where('mobile', $record->employee_mobile)->first();
                $shiftEnd = Carbon::parse($record->getRawOriginal('date'))
                    ->setTimeFromTimeString($staff->punch_out_time ?? '18:00:00');
                $closeAt  = $shiftEnd->greaterThan($record->punch_in_time)
                    ? $shiftEnd
                    : $record->punch_in_time;
            }

            $record->update([
                'punch_out_time'  => $closeAt,
                'auto_closed'     => true,
                // Tracking that was alive and then went silent is an interruption;
                // a shift that never pinged keeps its existing flag.
                'was_interrupted' => $record->last_ping_at ? true : $record->was_interrupted,
            ]);
        }
    }
}

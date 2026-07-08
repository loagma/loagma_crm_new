<?php

namespace App\Http\Controllers;

use App\Models\Attendance;
use App\Models\DeliStaff;
use App\Models\LocationPing;
use Carbon\Carbon;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Tymon\JWTAuth\Facades\JWTAuth;

class TrackingController extends Controller
{
    private const MAX_ACCURACY_METERS = 50;
    private const MAX_SPEED_KMH = 150;
    private const INTERRUPTED_GAP_MINUTES = 5;

    // ─── Helpers ─────────────────────────────────────────────────────────────

    private function authMobile(): string
    {
        // Same proven pattern as AttendanceController::authMobile() — the
        // default guard is web/session, so auth() resolves to null here.
        return JWTAuth::parseToken()->authenticate()->mobile;
    }

    private function haversineKm(float $lat1, float $lng1, float $lat2, float $lng2): float
    {
        $earthRadiusKm = 6371;
        $dLat = deg2rad($lat2 - $lat1);
        $dLng = deg2rad($lng2 - $lng1);
        $a = sin($dLat / 2) ** 2
            + cos(deg2rad($lat1)) * cos(deg2rad($lat2)) * sin($dLng / 2) ** 2;
        return $earthRadiusKm * 2 * atan2(sqrt($a), sqrt(1 - $a));
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
                    $km = $this->haversineKm($anchorLat, $anchorLng, (float) $p['lat'], (float) $p['lng']);
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
            $wasInterrupted = $attendance->was_interrupted;
            if ($attendance->last_ping_at) {
                $gapMinutes = Carbon::parse($attendance->last_ping_at)->diffInMinutes($latestAt);
                if ($gapMinutes > self::INTERRUPTED_GAP_MINUTES) {
                    $wasInterrupted = true;
                }
            }
            $attendance->update([
                'last_ping_at'    => $latestAt,
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

        $data = $open->map(function (Attendance $a) {
            $ping = LocationPing::where('employee_mobile', $a->employee_mobile)
                ->orderByDesc('recorded_at')
                ->first();

            return [
                'employee_mobile' => $a->employee_mobile,
                'name'            => $a->employee->name ?? null,
                'punch_in_time'   => $a->punch_in_time,
                'start'           => $a->punch_in_location, // {lat, lng} captured at punch-in
                'last_ping_at'    => $a->last_ping_at,
                'was_interrupted' => $a->was_interrupted,
                'lat'             => $ping?->lat,
                'lng'             => $ping?->lng,
                'battery'         => $ping?->battery,
                'is_mock'         => (bool) ($ping?->is_mock),
            ];
        })->values();

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

        $query = LocationPing::where('employee_mobile', $mobile)
            ->where('date', $today)
            ->orderBy('recorded_at');

        if (!empty($validated['since'])) {
            $query->where('recorded_at', '>', Carbon::parse($validated['since']));
        }

        $points = $query->get(['lat', 'lng', 'heading', 'battery', 'is_mock', 'recorded_at']);

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

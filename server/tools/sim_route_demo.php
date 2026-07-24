<?php
/**
 * Simulated-route demo driver (DEV ONLY — refuses to run in production).
 *
 * Seeds a road-true mock route (via the OSRM demo /route API) for the test
 * salesman so the admin live/history map screens can be demoed without a
 * walker: past trail with one >5-min gap, live-fed points, punch-out, and a
 * mandatory teardown.
 *
 * RULE (docs/tracking-testing-guide.md): every injected ping sets is_mock=1
 * AND `teardown` MUST run in the same session — no unmarked sim data.
 *
 * Usage:  C:\Users\Dell\php82\php.exe server\tools\sim_route_demo.php <mode>
 *   seed            attendance row + past trail on Jabalpur roads,
 *                   including one >5-min tracking gap (dash demo)
 *   feed [n] [s]    insert n more LIVE pings, one every s seconds
 *                   (default n=all remaining, s=8) — watch the map glide
 *   close           punch out → screen flips to ENDED, history+snap enabled
 *   status          row counts + latest ping
 *   token           mint an admin JWT for curl checks
 *   teardown        DELETE all is_mock pings for the account + the demo
 *                   attendance row. Idempotent — safe to run twice or after
 *                   a partial seed. ALWAYS run before ending the session.
 */

const MOBILE   = '9000400001';           // current test salesman (OTP 5555)
const DEMO_TAG = 'MAP_POLISH_DEMO';

require dirname(__DIR__) . '/vendor/autoload.php';
$app = require dirname(__DIR__) . '/bootstrap/app.php';
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();

if (app()->environment('production')) {
    fwrite(STDERR, "REFUSING: APP_ENV=production — this script seeds fake tracking data and must never run against a production environment.\n");
    exit(1);
}

$mode = $argv[1] ?? 'status';

function stateFile(): string
{
    return storage_path('app/sim_route_demo_state.json');
}

function nowIst(): Carbon\Carbon
{
    return Carbon\Carbon::now(config('app.timezone'));
}

function bearingDeg(array $a, array $b): float
{
    $lat1 = deg2rad($a[0]); $lat2 = deg2rad($b[0]);
    $dLng = deg2rad($b[1] - $a[1]);
    $y = sin($dLng) * cos($lat2);
    $x = cos($lat1) * sin($lat2) - sin($lat1) * cos($lat2) * cos($dLng);
    return fmod(rad2deg(atan2($y, $x)) + 360, 360);
}

function insertPing(array $pt, Carbon\Carbon $at, float $heading, int $battery): void
{
    App\Models\LocationPing::insert([[
        'employee_mobile' => MOBILE,
        'date'            => $at->toDateString(),
        'lat'             => $pt[0],
        'lng'             => $pt[1],
        'accuracy'        => rand(6, 28),      // some >=15 → accuracy circle visible
        'speed'           => round(5.0 + rand(0, 20) / 10, 1), // ~18-25 km/h
        'heading'         => round($heading, 1),
        'battery'         => $battery,
        'is_mock'         => 1,                // THE RULE
        'recorded_at'     => $at->format('Y-m-d H:i:s'), // naive IST wall-clock
    ]]);
}

switch ($mode) {
    case 'seed':
        $existing = App\Models\Attendance::where('employee_mobile', MOBILE)
            ->where('date', nowIst()->toDateString())->first();
        if ($existing && $existing->admin_notes !== DEMO_TAG) {
            fwrite(STDERR, "ABORT: real attendance row exists for " . MOBILE . " today — not touching it.\n");
            exit(1);
        }
        if ($existing) {
            fwrite(STDERR, "Demo row already seeded — run teardown first to reseed.\n");
            exit(1);
        }

        // Real road geometry: the test account's field area (Jabalpur) →
        // ~3 km across town, via the OSRM demo /route API.
        echo "Fetching road path from OSRM…\n";
        $path = null;
        try {
            $http = Illuminate\Support\Facades\Http::connectTimeout(3)->timeout(6);
            if ($ca = config('tracking.osrm_ca')) {
                $http = $http->withOptions(['verify' => $ca]);
            }
            $res = $http->get(
                'https://router.project-osrm.org/route/v1/driving/79.8996,23.2170;79.9333,23.1957',
                ['overview' => 'full', 'geometries' => 'geojson']
            );
            if ($res->ok() && $res->json('code') === 'Ok') {
                $path = array_map(
                    fn ($c) => [(float) $c[1], (float) $c[0]],
                    $res->json('routes.0.geometry.coordinates')
                );
            }
        } catch (Throwable) {
        }
        if (!$path) {
            fwrite(STDERR, "OSRM demo unreachable — cannot build a road-true path. Try again later.\n");
            exit(1);
        }

        // Resample to ~80 m spacing → one ping per 15 s ≈ 19 km/h.
        $pings = [$path[0]];
        $acc = 0.0;
        for ($i = 1; $i < count($path); $i++) {
            $acc += App\Support\RouteDistance::haversineKm(
                $path[$i - 1][0], $path[$i - 1][1], $path[$i][0], $path[$i][1]
            ) * 1000;
            if ($acc >= 80) {
                $pings[] = $path[$i];
                $acc = 0.0;
            }
        }
        $total = count($pings);
        if ($total < 20) {
            fwrite(STDERR, "Path too short ({$total} samples) — unexpected.\n");
            exit(1);
        }

        // 60% seeded as the past trail (with one >5-min gap in the middle:
        // 8 road points dropped + ~6 minutes skipped), 40% kept for `feed`.
        $seedCount = (int) floor($total * 0.6);
        $gapAt     = (int) floor($seedCount / 2);
        $seed      = array_merge(
            array_slice($pings, 0, $gapAt),
            array_slice($pings, $gapAt + 8, $seedCount - $gapAt - 8)
        );
        $live = array_slice($pings, $seedCount);

        $t = nowIst()->subSeconds(15 * count($seed) + 360 + 120);
        $battery = 92;
        App\Models\Attendance::create([
            'employee_mobile'   => MOBILE,
            'date'              => nowIst()->toDateString(),
            'punch_in_time'     => $t->copy()->subMinutes(2),
            'punch_in_location' => ['lat' => $seed[0][0], 'lng' => $seed[0][1]],
            'status'            => 'approved',
            'admin_notes'       => DEMO_TAG,
            'was_interrupted'   => true, // the seeded gap
        ]);

        foreach ($seed as $i => $pt) {
            $t = $t->copy()->addSeconds($i === $gapAt ? 375 : 15); // the gap
            $heading = $i + 1 < count($seed) ? bearingDeg($pt, $seed[$i + 1]) : bearingDeg($seed[$i - 1], $pt);
            if ($i % 12 === 0 && $battery > 40) $battery--;
            insertPing($pt, $t, $heading, $battery);
        }
        App\Models\Attendance::where('employee_mobile', MOBILE)
            ->where('date', nowIst()->toDateString())
            ->update(['last_ping_at' => $t->format('Y-m-d H:i:s')]);

        file_put_contents(stateFile(), json_encode(['live' => $live, 'battery' => $battery]));
        echo 'Seeded ' . count($seed) . " past pings (1 gap) + attendance row. "
            . count($live) . " live points staged for `feed`.\n";
        break;

    case 'feed':
        $state = json_decode((string) @file_get_contents(stateFile()), true);
        if (!$state || empty($state['live'])) {
            fwrite(STDERR, "Nothing staged — run seed first.\n");
            exit(1);
        }
        // Guard against feeding after a teardown left a stale state file.
        $demoRow = App\Models\Attendance::where('employee_mobile', MOBILE)
            ->where('date', nowIst()->toDateString())
            ->where('admin_notes', DEMO_TAG)->exists();
        if (!$demoRow) {
            fwrite(STDERR, "No demo attendance row for today — run seed first.\n");
            exit(1);
        }
        $n     = isset($argv[2]) ? (int) $argv[2] : count($state['live']);
        $sleep = isset($argv[3]) ? max(1, (int) $argv[3]) : 8;
        $battery = $state['battery'];

        for ($i = 0; $i < $n && !empty($state['live']); $i++) {
            $pt = array_shift($state['live']);
            $heading = !empty($state['live']) ? bearingDeg($pt, $state['live'][0]) : 0.0;
            if ($i % 12 === 0 && $battery > 40) $battery--;
            $at = nowIst();
            insertPing($pt, $at, $heading, $battery);
            App\Models\Attendance::where('employee_mobile', MOBILE)
                ->where('date', $at->toDateString())
                ->update(['last_ping_at' => $at->format('Y-m-d H:i:s')]);
            $state['battery'] = $battery;
            file_put_contents(stateFile(), json_encode($state));
            echo 'fed ' . $pt[0] . ',' . $pt[1] . ' (' . count($state['live']) . " left)\n";
            if ($i < $n - 1 && !empty($state['live'])) sleep($sleep);
        }
        break;

    case 'close':
        $a = App\Models\Attendance::where('employee_mobile', MOBILE)
            ->where('date', nowIst()->toDateString())
            ->where('admin_notes', DEMO_TAG)->first();
        if (!$a) {
            fwrite(STDERR, "No demo attendance row to close.\n");
            exit(1);
        }
        $last = App\Models\LocationPing::where('employee_mobile', MOBILE)
            ->where('is_mock', 1)->orderByDesc('recorded_at')->first();
        $a->update([
            'punch_out_time'     => nowIst(),
            'punch_out_location' => $last ? ['lat' => $last->lat, 'lng' => $last->lng] : null,
        ]);
        echo "Punched out — live screen will flip to ENDED; history is now snappable.\n";
        break;

    case 'status':
        echo 'mock pings: ' . App\Models\LocationPing::where('employee_mobile', MOBILE)->where('is_mock', 1)->count() . PHP_EOL;
        echo 'real pings today: ' . App\Models\LocationPing::where('employee_mobile', MOBILE)->where('is_mock', 0)->where('date', nowIst()->toDateString())->count() . PHP_EOL;
        $a = App\Models\Attendance::where('employee_mobile', MOBILE)->where('date', nowIst()->toDateString())->first();
        echo 'attendance today: ' . ($a ? ('in=' . $a->punch_in_time . ' out=' . $a->punch_out_time . ' notes=' . $a->admin_notes) : 'none') . PHP_EOL;
        break;

    case 'token':
        $admin = App\Models\DeliStaff::where('role', 'admin')->first();
        if (!$admin) {
            fwrite(STDERR, "No admin account found.\n");
            exit(1);
        }
        echo Tymon\JWTAuth\Facades\JWTAuth::fromUser($admin) . PHP_EOL;
        break;

    case 'teardown':
        // Idempotent by construction: zero-row deletes and a missing state
        // file are all fine — safe after a partial seed or a second run.
        $pings = App\Models\LocationPing::where('employee_mobile', MOBILE)->where('is_mock', 1)->delete();
        $rows = App\Models\Attendance::where('employee_mobile', MOBILE)
            ->where('admin_notes', DEMO_TAG)->delete();
        @unlink(stateFile());
        $strays = App\Models\LocationPing::where('is_mock', 1)->count();
        echo "Deleted {$pings} mock pings, {$rows} demo attendance row(s). "
            . "is_mock rows left in DB (any account): {$strays}\n";
        break;

    default:
        fwrite(STDERR, "Unknown mode '{$mode}'. Modes: seed feed close status token teardown\n");
        exit(1);
}

<?php
/**
 * End-to-end check of the telecaller daily allocation, run through the real
 * HTTP kernel (routes, JWT, controllers, CallLog hook) against the live DB —
 * inside ONE transaction that is ALWAYS rolled back. Nothing persists.
 *
 *   php tools/allocation_dryrun.php [telecaller_mobile] [days]
 *   php tools/allocation_dryrun.php 9000000070 4
 *
 * Simulated flow (clock faked from 2026-10-01): create a plan on
 * all-but-last-2 pincodes for a From–To range of [days] days → Day 1 list →
 * up to 60 calls with mixed outcomes + 1 manual skip → Day 2 merges the last
 * 2 pincodes and extends the To date by one day → every following day all
 * allocated customers get called → the plan completes by the To date.
 * Prints PASS/FAIL per check and exits 1 on any failure.
 */
chdir(dirname(__DIR__));
require 'vendor/autoload.php';
$app = require 'bootstrap/app.php';
$kernel = $app->make(Illuminate\Contracts\Http\Kernel::class);
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();

use App\Models\DeliStaff;
use App\Support\GeoSequencer;
use App\Support\TelecallerScope;
use Illuminate\Http\Request;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use Tymon\JWTAuth\Facades\JWTAuth;

$MOBILE = $argv[1] ?? '9000000070';
$DAYS   = max(2, (int) ($argv[2] ?? 4));
$START  = '2026-10-01';
$END    = Carbon::parse($START)->addDays($DAYS - 1)->toDateString();
$failed = 0;

function check(string $label, bool $ok, string $detail = ''): void
{
    global $failed;
    if (!$ok) $failed++;
    echo ($ok ? '  PASS ' : '  FAIL ') . $label . ($detail !== '' ? "  ($detail)" : '') . "\n";
}

function call(string $method, string $uri, array $params = []): array
{
    global $kernel, $MOBILE;
    $tok = JWTAuth::fromUser(DeliStaff::where('mobile', $MOBILE)->firstOrFail());
    $req = Request::create('/api' . $uri, $method, [], [], [], [
        'HTTP_AUTHORIZATION' => "Bearer $tok", 'HTTP_ACCEPT' => 'application/json', 'CONTENT_TYPE' => 'application/json',
    ], $params ? json_encode($params) : null);
    app()->instance('request', $req);
    JWTAuth::setRequest($req)->setToken($tok);
    auth()->forgetGuards();
    $res = $kernel->handle($req);
    if ($res->getStatusCode() >= 300) {
        echo "  !! $method $uri -> {$res->getStatusCode()} " . substr($res->getContent(), 0, 300) . "\n";
    }
    return json_decode($res->getContent(), true) ?? [];
}

function perPincode(array $rows): array
{
    $o = [];
    foreach ($rows as $r) $o[$r['pincode']] = ($o[$r['pincode']] ?? 0) + 1;
    return $o;
}

function fmt(array $a): string
{
    return implode(' + ', array_map(fn ($k, $v) => "$k:$v", array_keys($a), $a));
}

function pendingCount(): int
{
    global $MOBILE;
    return DB::table('tc_allocation_item_crm')->where('employee_mobile', $MOBILE)->where('status', 'pending')->count();
}

$counts = fn () => [
    'plans'     => DB::table('tc_allocation_plan_crm')->count(),
    'items'     => DB::table('tc_allocation_item_crm')->count(),
    'geo'       => DB::table('pincode_geo_crm')->count(),
    'call_logs' => DB::table('call_log_crm')->count(),
];
$before = $counts();

if (DB::table('tc_allocation_plan_crm')->where('employee_mobile', $MOBILE)->where('status', 'active')->exists()) {
    echo "Telecaller $MOBILE already has an ACTIVE plan — pick another telecaller for a clean dry run.\n";
    exit(1);
}

DB::beginTransaction();
try {
    [, $pins] = TelecallerScope::areaScope($MOBILE);
    sort($pins);
    echo "Telecaller $MOBILE, From $START To $END ($DAYS days)\n";
    echo "Assigned pincodes (numeric order): " . implode(', ', $pins) . "\n";
    if (count($pins) < 3) {
        echo "Needs at least 3 assigned pincodes for the merge step.\n";
        exit(1);
    }
    $first = array_slice($pins, 0, -2);
    $later = array_slice($pins, -2);

    Carbon::setTestNow(Carbon::parse("$START 10:00"));

    echo "\n[1] No plan yet\n";
    $r = call('GET', '/telecaller/allocation');
    check('GET /telecaller/allocation returns null', ($r['success'] ?? false) === true && array_key_exists('data', $r) && $r['data'] === null);
    $bad = call('POST', '/telecaller/allocation', ['pincodes' => $first, 'start_date' => $START, 'end_date' => '2026-09-30']);
    check('To date before From date is rejected', ($bad['success'] ?? null) !== true && isset($bad['errors']['end_date']));

    echo "\n[2] Create plan on " . count($first) . " pincodes, $START .. $END\n";
    $p = call('POST', '/telecaller/allocation', ['pincodes' => $first, 'start_date' => $START, 'end_date' => $END])['data'] ?? [];
    check('plan created', !empty($p['plan_id']));
    echo "  sequence: " . implode(' → ', $p['pincode_sequence'] ?? []) . "   queue: " . ($p['total'] ?? 0)
        . "   per day now: " . ($p['daily_capacity'] ?? '?') . "\n";
    $geo = DB::table('pincode_geo_crm')->whereIn('pincode', $p['pincode_sequence'] ?? [])->get()->keyBy('pincode');
    $prev = null;
    $unlocated = 0;
    foreach ($p['pincode_sequence'] ?? [] as $pc) {
        $g = $geo[$pc] ?? null;
        if (!$g) $unlocated++;
        $d = ($prev && $g) ? sprintf('  %.1f km from previous', GeoSequencer::km([$prev->lat, $prev->lng], [$g->lat, $g->lng])) : '';
        echo sprintf("    %s  %s%s\n", $pc, $g ? sprintf('(%.4f, %.4f) %s', $g->lat, $g->lng, $g->source) : '(NO LOCATION — sequenced last)', $d);
        $prev = $g ?: $prev;
    }
    check('every selected pincode has a location', $unlocated === 0, "$unlocated unlocated");
    $queue = (int) ($p['total'] ?? 0);
    check("progress shows $DAYS total days, day 1", ($p['total_days'] ?? 0) === $DAYS && ($p['day'] ?? 0) === 1);

    // ── Day 1 ──
    echo "\n[Day 1] $START\n";
    $t = call('GET', '/telecaller/allocation/today')['data'];
    echo "  today: {$t['total']}  = " . fmt(perPincode($t['customers'])) . "\n";
    check("day 1 size = ceil($queue / $DAYS days)", $t['total'] === (int) ceil($queue / $DAYS), "{$t['total']}");
    $again = call('GET', '/telecaller/allocation/today')['data'];
    check('second fetch same day returns the same list', array_column($again['customers'], 'item_id') === array_column($t['customers'], 'item_id'));

    $work = min(60, max(0, $t['total'] - 2));
    $outcomes = ['answered', 'busy', 'no_answer', 'switch_off', 'callback', 'invalid'];
    foreach (array_slice($t['customers'], 0, $work) as $i => $c) {
        call('POST', '/call-logs', ['account_id' => (string) $c['account_id'], 'account_type' => $c['account_type'], 'call_outcome' => $outcomes[$i % 6]]);
    }
    call('PATCH', '/telecaller/allocation/items/' . $t['customers'][$work]['item_id'], ['status' => 'skipped']);
    $st = DB::table('tc_allocation_item_crm')->where('employee_mobile', $MOBILE)->where('allocated_date', $START)
        ->select('status', DB::raw('count(*) n'))->groupBy('status')->pluck('n', 'status')->all();
    echo "  after $work logged calls + 1 manual skip: " . json_encode($st) . "\n";
    $expCallback = intdiv($work, 6) + ($work % 6 > 4 ? 1 : 0);
    $expInvalid = intdiv($work, 6);
    check('call log hook: callback outcome → callback', ($st['callback'] ?? 0) === $expCallback);
    check('call log hook: invalid outcome + manual skip → skipped', ($st['skipped'] ?? 0) === $expInvalid + 1);
    check('call log hook: answered/busy/no_answer/switch_off → completed', ($st['completed'] ?? 0) === $work - $expCallback - $expInvalid);
    $unworked = array_column(array_slice($t['customers'], $work + 1), 'item_id');

    // ── Day 2: merge + extend the To date by one day ──
    Carbon::setTestNow(Carbon::parse("$START 10:00")->addDay());
    $END = Carbon::parse($END)->addDay()->toDateString();
    $DAYS++;
    echo "\n[Day 2] " . Carbon::today()->toDateString() . "  merge " . implode(', ', $later) . ", To date → $END\n";
    $p = call('POST', '/telecaller/allocation', ['pincodes' => $later, 'end_date' => $END])['data'];
    echo "  merged sequence: " . implode(' → ', $p['pincode_sequence']) . "   queue: {$p['total']}\n";
    check('merge keeps one plan', DB::table('tc_allocation_plan_crm')->where('employee_mobile', $MOBILE)->count() === 1);
    check('merge keeps From date, takes new To date', ($p['start_date'] ?? '') === $START && ($p['end_date'] ?? '') === $END);
    $openBefore = pendingCount() + count($unworked);
    $t = call('GET', '/telecaller/allocation/today')['data'];
    echo "  today: {$t['total']}  = " . fmt(perPincode($t['customers'])) . "\n";
    $ids = array_column($t['customers'], 'item_id');
    check('day 1 unworked customers come first on day 2', array_slice($ids, 0, count($unworked)) === $unworked, count($unworked) . ' carried');
    $left = $DAYS - 1;
    check("day 2 size = ceil($openBefore remaining / $left days left)", $t['total'] === (int) ceil($openBefore / $left), "{$t['total']}");

    // ── Remaining days: everyone allocated gets called ──
    $seen = [];
    $dupes = 0;
    $day = 2;
    while (true) {
        foreach ($t['customers'] as $c) {
            if (isset($seen[$c['item_id']])) $dupes++;
            $seen[$c['item_id']] = true;
        }
        DB::table('tc_allocation_item_crm')->whereIn('id', $ids)->where('status', 'assigned')->update(['status' => 'completed']);
        $day++;
        $date = Carbon::parse("$START 10:00")->addDays($day - 1);
        Carbon::setTestNow($date);
        $openBefore = pendingCount();
        $t = call('GET', '/telecaller/allocation/today')['data'];
        $ids = array_column($t['customers'], 'item_id');
        if ($t['total'] === 0) {
            echo "[Day $day] {$date->toDateString()} nothing left, plan_status={$t['plan_status']}\n";
            check('every customer was handed out by the To date', $date->toDateString() > $END, "To date $END");
            break;
        }
        echo "[Day $day] {$date->toDateString()} today: {$t['total']}  = " . fmt(perPincode($t['customers'])) . "\n";
        $daysLeft = $DAYS - $day + 1;
        check("day $day size = ceil($openBefore / $daysLeft days left)", $t['total'] === (int) ceil($openBefore / $daysLeft));
        if ($day > 60) { check('finishes within 60 days', false); break; }
    }
    check('no customer handed out twice (after day 1)', $dupes === 0, "$dupes");
    check('plan marked completed', ($t['plan_status'] ?? '') === 'completed');
    $open = DB::table('tc_allocation_item_crm')->where('employee_mobile', $MOBILE)->whereIn('status', ['pending', 'assigned', 'in_progress'])->count();
    check('no customer left pending', $open === 0, "$open");
    $dash = call('GET', '/telecaller/dashboard')['data']['daily_target'] ?? null;
    check('dashboard daily_target falls back to 60 with no active plan', $dash === 60, json_encode($dash));
} finally {
    DB::rollBack();
    Carbon::setTestNow();
    $after = $counts();
    echo "\nROLLED BACK — row counts before " . json_encode($before) . " after " . json_encode($after) . "\n";
    check('nothing persisted', $before === $after);
    echo $failed === 0 ? "\nALL CHECKS PASSED\n" : "\n$failed CHECK(S) FAILED\n";
    exit($failed === 0 ? 0 : 1);
}

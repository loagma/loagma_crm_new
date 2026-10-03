<?php
/**
 * End-to-end check of the telecaller Daily Plan, run through the real HTTP
 * kernel (routes, JWT, controllers, CallLog hook) against the live DB —
 * inside ONE transaction that is ALWAYS rolled back. Nothing persists.
 *
 *   php tools/allocation_dryrun.php [telecaller_mobile] [days]
 *   php tools/allocation_dryrun.php 9000000070 4
 *
 * Simulated flow (clock faked from 2026-10-01), fixed-date model:
 *  - create a plan on all-but-last-2 pincodes over [days] days → every account
 *    gets a fixed date, split evenly in geographic order;
 *  - Day 1: up to 60 calls with mixed outcomes + 1 manual skip, rest unworked;
 *  - Day 2: today's list is exactly Day 2's accounts (no carry-forward); Day 1's
 *    unworked accounts show as "missed"; they are reassigned to Day 3;
 *  - merge the last 2 pincodes → their accounts come in unscheduled; they are
 *    given the last day's date;
 *  - auto-distribute: 30 selected accounts are spread over just two chosen
 *    weekdays of the remaining range in even consecutive blocks (called
 *    accounts skipped, unknown ids counted, an empty weekday match rejected);
 *  - every remaining day all of that day's accounts get called → plan completes;
 *  - "N days" mode: no To date — the first N dates on the chosen weekdays from
 *    the start date (Mon+Fri, N=8 → 4 Mondays + 4 Fridays);
 *  - with no active plan the beat-plan fallback honours the weekdays and N too.
 * Prints PASS/FAIL per check and exits 1 on any failure.
 */
chdir(dirname(__DIR__));
require 'vendor/autoload.php';
$app = require 'bootstrap/app.php';
$kernel = $app->make(Illuminate\Contracts\Http\Kernel::class);
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();

use App\Models\DeliStaff;
use App\Support\DailyAllocator;
use App\Support\GeoSequencer;
use App\Support\TelecallerScope;
use Illuminate\Http\Request;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use Tymon\JWTAuth\Facades\JWTAuth;

$MOBILE = $argv[1] ?? '9000000070';
$DAYS   = max(3, (int) ($argv[2] ?? 4));
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
        echo "  .. $method $uri -> {$res->getStatusCode()} " . substr($res->getContent(), 0, 200) . "\n";
    }
    return json_decode($res->getContent(), true) ?? [];
}

function setDay(string $ymd): void
{
    Carbon::setTestNow(Carbon::parse("$ymd 10:00"));
}

function fmt(array $a): string
{
    return implode(' + ', array_map(fn ($k, $v) => "$k:$v", array_keys($a), $a));
}

function itemsOn(string $ymd): array
{
    global $MOBILE;
    return DB::table('tc_allocation_item_crm')->where('employee_mobile', $MOBILE)->where('allocated_date', $ymd)
        ->orderBy('pincode_rank')->orderBy('account_rank')->pluck('id')->all();
}

$counts = fn () => [
    'plans'     => DB::table('tc_allocation_plan_crm')->count(),
    'items'     => DB::table('tc_allocation_item_crm')->count(),
    'geo'       => DB::table('pincode_geo_crm')->count(),
    'call_logs' => DB::table('call_log_crm')->count(),
    'beat'      => DB::table('beat_plan_crm')->count(),
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
    $dates = [];
    for ($i = 0; $i < $DAYS; $i++) $dates[] = Carbon::parse($START)->addDays($i)->toDateString();

    setDay($START);

    echo "\n[1] No plan yet\n";
    $r = call('GET', '/telecaller/allocation');
    check('GET /telecaller/allocation returns null', ($r['success'] ?? false) === true && array_key_exists('data', $r) && $r['data'] === null);
    $bad = call('POST', '/telecaller/allocation', ['pincodes' => $first, 'start_date' => $START, 'end_date' => '2026-09-30']);
    check('To date before From date is rejected', isset($bad['errors']['end_date']));

    echo "\n[2] Create plan on " . count($first) . " pincodes, $START .. $END\n";
    $p = call('POST', '/telecaller/allocation', ['pincodes' => $first, 'start_date' => $START, 'end_date' => $END])['data'] ?? [];
    check('plan created', !empty($p['plan_id']));
    $queue = (int) ($p['total'] ?? 0);
    echo "  sequence: " . implode(' → ', $p['pincode_sequence'] ?? []) . "   accounts: $queue\n";
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

    $perDate = array_count_values(array_column($p['schedule'] ?? [], 'date'));
    ksort($perDate);
    echo "  fixed dates: " . fmt($perDate) . "\n";
    check('every account got a fixed date', count($p['schedule'] ?? []) === $queue && ($p['unscheduled'] ?? -1) === 0);
    check('split is even over the range', $perDate === DailyAllocator::split($queue, $START, $END));

    // ── Day 1 ──
    echo "\n[Day 1] $START\n";
    $t = call('GET', '/telecaller/allocation/today')['data'];
    check('today = the accounts dated day 1', array_column($t['customers'], 'item_id') === itemsOn($START), "{$t['total']}");
    $again = call('GET', '/telecaller/allocation/today')['data'];
    check('second fetch same day returns the same list', array_column($again['customers'], 'item_id') === array_column($t['customers'], 'item_id'));
    $dash = call('GET', '/telecaller/dashboard')['data']['daily_target'] ?? null;
    check("dashboard daily_target = today's count", $dash === $t['total'], json_encode($dash));

    $work = min(60, max(0, $t['total'] - 3));
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
    $unworked = array_slice($t['customers'], $work + 1);

    // ── Day 2: no carry-forward; missed shown; reassign missed to day 3 ──
    setDay($dates[1]);
    echo "\n[Day 2] {$dates[1]}\n";
    $t = call('GET', '/telecaller/allocation/today')['data'];
    check('today = only day 2\'s own accounts (nothing carried over)', array_column($t['customers'], 'item_id') === itemsOn($dates[1]) && $t['total'] === $perDate[$dates[1]], "{$t['total']}");
    $p = call('GET', '/telecaller/allocation')['data'];
    check('day 1 unworked accounts show as missed', $p['missed'] === count($unworked), "{$p['missed']} missed");
    $day1Dates = array_unique(array_map(fn ($c) => $p['schedule'][$c['account_id']]['date'] ?? '', $unworked));
    check('missed accounts keep their day 1 date', $day1Dates === [$START]);

    $pastDate = call('POST', '/telecaller/allocation/reassign', ['account_ids' => array_column($unworked, 'account_id'), 'date' => $START]);
    check('reassigning to a past date is rejected', isset($pastDate['errors']['date']));
    $re = call('POST', '/telecaller/allocation/reassign', ['account_ids' => array_column($unworked, 'account_id'), 'date' => $dates[2]]);
    check('missed accounts reassigned to day 3', ($re['updated'] ?? 0) === count($unworked), ($re['updated'] ?? 0) . ' updated');
    check('missed count back to 0', ($re['data']['missed'] ?? -1) === 0);
    $doneIds = DB::table('tc_allocation_item_crm')->where('employee_mobile', $MOBILE)->where('status', 'completed')->pluck('account_id')->all();
    $noop = call('POST', '/telecaller/allocation/reassign', ['account_ids' => array_slice($doneIds, 0, 3), 'date' => $dates[2]]);
    check('already-called accounts cannot be rescheduled', ($noop['updated'] ?? -1) === 0);

    // ── Merge the last 2 pincodes: unscheduled, then dated by the telecaller ──
    $p = call('POST', '/telecaller/allocation', ['pincodes' => $later, 'end_date' => $END])['data'];
    $added = $p['total'] - $queue;
    echo "  merged " . implode(', ', $later) . ": +$added accounts, sequence " . implode(' → ', $p['pincode_sequence']) . "\n";
    check('merge keeps one plan and the same dates range', DB::table('tc_allocation_plan_crm')->where('employee_mobile', $MOBILE)->count() === 1
        && $p['start_date'] === $START && $p['end_date'] === $END);
    check('merged accounts come in unscheduled', $p['unscheduled'] === $added && $added > 0, "$added unscheduled");
    $perDateAfter = array_count_values(array_column($p['schedule'], 'date'));
    check('existing accounts keep their dates (nothing re-divided)', ($perDateAfter[$dates[3]] ?? 0) === ($perDate[$dates[3]] ?? 0));
    $newIds = DB::table('tc_allocation_item_crm')->where('employee_mobile', $MOBILE)->whereNull('allocated_date')->pluck('account_id')->all();
    $re = call('POST', '/telecaller/allocation/reassign', ['account_ids' => $newIds, 'date' => $END]);
    check('unscheduled accounts given a date', ($re['updated'] ?? 0) === $added && ($re['data']['unscheduled'] ?? -1) === 0);

    // ── Auto-distribute over chosen weekdays (Day 2, clock = {$dates[1]}) ──
    echo "\n[Auto-distribute] weekdays of " . $dates[1] . " and " . $dates[3] . " only, range " . $dates[1] . " .. $END\n";
    $wd = fn (string $ymd) => Carbon::parse($ymd)->format('D');
    $chosen = array_values(array_unique([$wd($dates[1]), $wd($dates[3])]));
    $ids30 = DB::table('tc_allocation_item_crm')->where('employee_mobile', $MOBILE)->where('status', 'assigned')
        ->where('allocated_date', '>=', $dates[1])->orderBy('pincode_rank')->orderBy('account_rank')
        ->limit(30)->pluck('account_id')->all();
    $calledIds = DB::table('tc_allocation_item_crm')->where('employee_mobile', $MOBILE)->where('status', 'completed')
        ->limit(2)->pluck('account_id')->all();
    $payload = ['account_ids' => array_merge($ids30, $calledIds, ['no-such-account']), 'start_date' => $dates[1], 'end_date' => $END, 'weekdays' => $chosen];
    $r = call('POST', '/telecaller/allocation/distribute', $payload);
    check('distribute succeeds', ($r['success'] ?? false) === true, $r['message'] ?? '');
    check('30 moved, called accounts skipped, unknown id counted',
        ($r['updated'] ?? 0) === 30 && ($r['skipped_done'] ?? 0) === count($calledIds) && ($r['not_in_plan'] ?? 0) === 1,
        json_encode([$r['updated'] ?? null, $r['skipped_done'] ?? null, $r['not_in_plan'] ?? null]));
    $got = DB::table('tc_allocation_item_crm')->where('employee_mobile', $MOBILE)->whereIn('account_id', $ids30)
        ->get(['account_id', 'allocated_date'])->pluck('allocated_date', 'account_id');
    $usedDates = array_values(array_unique($got->values()->all()));
    sort($usedDates);
    $okDays = array_values(array_filter(DailyAllocator::datesInRange($dates[1], $END, $chosen)));
    echo "  used dates: " . implode(', ', $usedDates) . "  (allowed: " . implode(', ', $okDays) . ")\n";
    check('only the chosen weekdays are used', $usedDates === $okDays, json_encode($chosen));
    check('the unchosen day got none of them', !in_array($dates[2], $usedDates, true));
    $expected = DailyAllocator::blocksOver(30, $okDays);
    $actual = array_map(fn ($id) => substr((string) $got[$id], 0, 10), $ids30);
    check('even consecutive blocks in selection order', $actual === $expected);
    $none = call('POST', '/telecaller/allocation/distribute', ['account_ids' => $ids30, 'start_date' => $dates[1], 'end_date' => $dates[1], 'weekdays' => [$wd($dates[2])]]);
    check('no matching weekday in the range is rejected', isset($none['errors']['weekdays']));
    $badDay = call('POST', '/telecaller/allocation/distribute', ['account_ids' => $ids30, 'start_date' => $dates[1], 'end_date' => $END, 'weekdays' => ['Funday']]);
    check('invalid weekday name is rejected', isset($badDay['errors']['weekdays.0']) || isset($badDay['errors']['weekdays']));

    // "N days" mode: first N dates on the chosen weekdays counted from today (no To date)
    $ids10 = array_slice($ids30, 0, 10);
    $nd = call('POST', '/telecaller/allocation/distribute', ['account_ids' => $ids10, 'start_date' => $dates[1], 'days' => 2, 'weekdays' => $chosen]);
    check('N-days mode succeeds', ($nd['success'] ?? false) === true, $nd['message'] ?? '');
    $ndDates = array_keys($nd['dates'] ?? []);
    sort($ndDates);
    check('N = 2 gives the first 2 matching days, 5 customers each', $ndDates === $okDays && array_values($nd['dates'] ?? []) === [5, 5], json_encode($nd['dates'] ?? []));
    $noEnd = call('POST', '/telecaller/allocation/distribute', ['account_ids' => $ids10, 'start_date' => $dates[1], 'weekdays' => $chosen]);
    check('neither To date nor N is rejected', isset($noEnd['errors']['end_date']) || isset($noEnd['errors']['days']));
    $zero = call('POST', '/telecaller/allocation/distribute', ['account_ids' => $ids10, 'start_date' => $dates[1], 'days' => 0, 'weekdays' => $chosen]);
    check('N = 0 is rejected', isset($zero['errors']['days']));

    // ── Day 2 onward: call everyone dated each day ──
    foreach (array_slice($dates, 1) as $i => $d) {
        setDay($d);
        $t = call('GET', '/telecaller/allocation/today')['data'];
        $expected = itemsOn($d);
        $label = "[Day " . ($i + 2) . "] $d";
        echo "$label today: {$t['total']}\n";
        check("$label list = accounts dated $d", array_column($t['customers'], 'item_id') === $expected);
        DB::table('tc_allocation_item_crm')->whereIn('id', $expected)->whereIn('status', ['assigned', 'in_progress'])->update(['status' => 'completed']);
    }
    setDay(Carbon::parse($END)->addDay()->toDateString());
    $t = call('GET', '/telecaller/allocation/today')['data'];
    check('plan marked completed once everyone is called', ($t['plan_status'] ?? '') === 'completed', $t['plan_status'] ?? '');
    $open = DB::table('tc_allocation_item_crm')->where('employee_mobile', $MOBILE)->whereIn('status', ['pending', 'assigned', 'in_progress'])->count();
    check('no customer left open', $open === 0, "$open");
    $dash = call('GET', '/telecaller/dashboard')['data']['daily_target'] ?? null;
    check('dashboard daily_target falls back to 60 with no active plan', $dash === 60, json_encode($dash));

    // ── No active plan → beat-plan fallback honours the weekdays ──
    setDay('2026-10-12'); // a Monday
    echo "\n[Beat-plan fallback] no active plan, weekdays Tue+Thu, 2026-10-12 .. 2026-10-25\n";
    $some = DB::table('tc_allocation_item_crm')->where('employee_mobile', $MOBILE)->orderBy('id')->limit(12)->get(['account_id', 'account_type']);
    $r = call('POST', '/beat-plan/auto-distribute', [
        'account_ids' => $some->pluck('account_id')->all(),
        'account_types' => $some->pluck('account_type')->all(),
        'start_date' => '2026-10-12', 'end_date' => '2026-10-25', 'weekdays' => ['Tue', 'Thu'],
    ]);
    check('beat-plan auto-distribute succeeds', ($r['success'] ?? false) === true, $r['message'] ?? ($r['error'] ?? ''));
    $days = array_column(array_filter($r['preview'] ?? [], fn ($x) => $x['count'] > 0), 'date');
    $weekdaysUsed = array_values(array_unique(array_map(fn ($d) => Carbon::parse($d)->format('D'), $days)));
    sort($weekdaysUsed);
    check('only Tue/Thu dates used', $weekdaysUsed === ['Thu', 'Tue'], implode(',', $days));
    check('12 accounts over 4 matching days = 3 each', array_values(array_unique(array_column($r['preview'] ?? [], 'count'))) === [3]);
    $bp = call('POST', '/beat-plan/auto-distribute', [
        'account_ids' => ['x'], 'account_types' => ['lead'], 'start_date' => '2026-10-12', 'end_date' => '2026-10-13', 'weekdays' => ['Sat'],
    ]);
    $nb = call('POST', '/beat-plan/auto-distribute', [
        'account_ids' => $some->pluck('account_id')->all(),
        'account_types' => $some->pluck('account_type')->all(),
        'start_date' => '2026-10-12', 'days' => 8, 'weekdays' => ['Tue', 'Thu'],
    ]);
    $nbDays = array_column(array_filter($nb['preview'] ?? [], fn ($x) => $x['count'] > 0), 'date');
    $nbNames = array_count_values(array_map(fn ($d) => Carbon::parse($d)->format('D'), $nbDays));
    ksort($nbNames);
    check('beat-plan N-days: 8 days on Tue+Thu = 4 Tue + 4 Thu', ($nb['success'] ?? false) === true && $nbNames === ['Thu' => 4, 'Tue' => 4], json_encode($nbNames));
    $cn = call('POST', '/beat-plan/auto-distribute', [
        'account_ids' => $some->pluck('account_id')->all(),
        'account_types' => $some->pluck('account_type')->all(),
        'start_date' => '2026-10-03', 'days' => 8, 'weekdays' => ['Mon', 'Fri'],
    ]);
    $cnDays = array_column(array_filter($cn['preview'] ?? [], fn ($x) => $x['count'] > 0), 'date');
    check('From 3 Oct, N = 8, Mon+Fri = 4 Mon + 4 Fri over 5 Oct .. 30 Oct',
        $cnDays === ['2026-10-05', '2026-10-09', '2026-10-12', '2026-10-16', '2026-10-19', '2026-10-23', '2026-10-26', '2026-10-30'], implode(',', $cnDays));
    check('beat-plan with no matching weekday is a 422', ($bp['success'] ?? null) === false && str_contains($bp['error'] ?? '', 'falls between'));
} finally {
    DB::rollBack();
    Carbon::setTestNow();
    $after = $counts();
    echo "\nROLLED BACK — row counts before " . json_encode($before) . " after " . json_encode($after) . "\n";
    check('nothing persisted', $before === $after);
    echo $failed === 0 ? "\nALL CHECKS PASSED\n" : "\n$failed CHECK(S) FAILED\n";
    exit($failed === 0 ? 0 : 1);
}

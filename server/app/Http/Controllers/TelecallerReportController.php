<?php

namespace App\Http\Controllers;

use App\Models\ActionLog;
use App\Models\BeatPlan;
use App\Models\CallLog;
use App\Models\DeliStaff;
use App\Models\LeadsAccount;
use App\Support\Hierarchy;
use Illuminate\Http\JsonResponse;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use Tymon\JWTAuth\Facades\JWTAuth;

/**
 * Per-customer daily report for a telecaller — "who was on my/their route
 * today, how many times were they called (answered vs not, normal vs cloud),
 * and did it end in an order" — with a drill-in for one customer's full call
 * + order detail. Powers the new "Team Report" / "Self Report" screens
 * (distinct from TeamReportController's attendance/visit/call rollup).
 */
class TelecallerReportController extends Controller
{
    // "This Month" is the widest built-in filter; cap a hand-crafted range at
    // the same width rather than 422 it — the per-day firingAccounts() loop
    // below would otherwise get silly for an open-ended range.
    private const MAX_RANGE_DAYS = 31;

    private function viewer(): DeliStaff
    {
        $mobile = (string) JWTAuth::parseToken()->authenticate()->mobile;
        $staff  = DeliStaff::where('mobile', $mobile)->first();
        abort_if(!$staff, 403, 'Unauthorized');
        return $staff;
    }

    // Self for a telecaller (the ?telecaller_id= query param is ignored —
    // never let a telecaller pass someone else's id); a senior must pass
    // ?telecaller_id= and it must be admin (unrestricted) or inside their
    // own hierarchy subtree.
    private function resolveTelecallerId(DeliStaff $viewer): string
    {
        $role = strtolower(trim($viewer->role ?? ''));
        if (\in_array($role, ['telecaller', 'salesman'], true)) {
            return (string) $viewer->mobile;
        }

        $target = (string) request()->query('telecaller_id', '');
        abort_if($target === '', 422, 'telecaller_id is required');

        // Viewing your own report is always allowed, whatever the role —
        // covers a non-telecaller senior opening "Self Report" (harmless:
        // they simply have no beat-plan rows, an empty report rather than
        // an error).
        if ($target === (string) $viewer->mobile) {
            return $target;
        }

        if ($role !== 'admin') {
            $subtree = Hierarchy::subtreeForViewer($viewer) ?? [];
            abort_if(!\in_array($target, $subtree, true), 403, 'That telecaller is not in your team');
        }

        return $target;
    }

    // [$fromCarbon, $toCarbon] from ?from=&to= (Y-m-d, inclusive). ?date= is
    // accepted as a single-day shorthand for back-compat. Missing both means
    // today. A same-day range (Today/Yesterday) is just from === to.
    private function range(): array
    {
        $tz    = config('app.timezone');
        $today = Carbon::today($tz)->toDateString();

        $fromYmd = request()->query('from') ?? request()->query('date') ?? $today;
        $toYmd   = request()->query('to')   ?? $fromYmd;
        if ($toYmd < $fromYmd) {
            [$fromYmd, $toYmd] = [$toYmd, $fromYmd];
        }

        $from = Carbon::createFromFormat('Y-m-d', $fromYmd, $tz)->startOfDay();
        $to   = Carbon::createFromFormat('Y-m-d', $toYmd, $tz)->endOfDay();

        if ($from->diffInDays($to) > self::MAX_RANGE_DAYS) {
            $from = (clone $to)->subDays(self::MAX_RANGE_DAYS)->startOfDay();
        }

        return [$from, $to];
    }

    // Accounts firing on ANY day within [$from, $to] per the beat plan — same
    // day-firing rule BeatPlanController::today() uses for "my worklist right
    // now", walked one day at a time and unioned so a week/month filter shows
    // every account that was ever due, not just the ones due on the last day.
    private function firingAccounts(string $telecallerId, Carbon $from, Carbon $to): \Illuminate\Support\Collection
    {
        $seen   = [];
        $result = collect();
        for ($day = $from->copy()->startOfDay(); $day->lte($to); $day->addDay()) {
            $query = BeatPlan::where('salesman_id', $telecallerId)->where('is_active', true);
            BeatPlanController::dayFiringQuery($query, $day);
            foreach ($query->get(['account_id', 'account_type']) as $a) {
                $key = $a->account_type . ':' . $a->account_id;
                if (!isset($seen[$key])) {
                    $seen[$key] = true;
                    $result->push($a);
                }
            }
        }
        return $result;
    }

    // Orders placed by any of $customerUserIds within [$start, $end]. Leads
    // can't place orders (orders.buyer_userid points at `user.userid`, which
    // only exists once an account has converted), so callers only pass
    // customer-type account ids here. `orders` has no created_at — creation
    // time is the unix-epoch `start_time` column — same pattern as
    // BeatPlanController::productiveAccountIdsInRange().
    private function ordersInRange(array $customerUserIds, Carbon $start, Carbon $end): \Illuminate\Support\Collection
    {
        if (empty($customerUserIds)) {
            return collect();
        }
        return DB::table('orders')
            ->whereIn('buyer_userid', $customerUserIds)
            ->whereBetween('start_time', [$start->timestamp, $end->timestamp])
            ->get();
    }

    private function formatOrder(object $o): array
    {
        return [
            'order_id'       => (string) $o->order_id,
            'order_total'    => (float) $o->order_total,
            'items_count'    => DB::table('orders_item')->where('order_id', $o->order_id)->count(),
            'payment_status' => $o->payment_status,
            'order_state'    => $o->order_state,
            'order_datetime' => $o->short_datetime,
        ];
    }

    private function accountMap(array $leadIds, array $custIds): array
    {
        $map = [];
        if (!empty($leadIds)) {
            foreach (LeadsAccount::whereIn('id', $leadIds)->get(['id', 'businessName', 'personName', 'contactNumber']) as $l) {
                $map[(string) $l->id] = [
                    'name'  => $l->businessName ?: $l->personName,
                    'phone' => $l->contactNumber,
                ];
            }
        }
        if (!empty($custIds)) {
            foreach (DB::table('user')->whereIn('userid', $custIds)->get(['userid', 'name', 'shop_name', 'contactno']) as $c) {
                $map[(string) $c->userid] = [
                    'name'  => $c->shop_name ?: $c->name,
                    'phone' => $c->contactno,
                ];
            }
        }
        return $map;
    }

    // ── GET /api/telecaller-report/summary?from=&to=&telecaller_id= ────────────
    public function summary(): JsonResponse
    {
        $viewer       = $this->viewer();
        $telecallerId = $this->resolveTelecallerId($viewer);
        [$start, $end] = $this->range();

        $accounts = $this->firingAccounts($telecallerId, $start, $end);
        if ($accounts->isEmpty()) {
            return response()->json(['success' => true, 'data' => [
                'telecaller_id' => $telecallerId,
                'from' => $start->toDateString(), 'to' => $end->toDateString(),
                'rows' => [],
            ]]);
        }

        $leadIds    = $accounts->where('account_type', 'lead')->pluck('account_id')->unique()->values()->all();
        $custIds    = $accounts->where('account_type', 'customer')->pluck('account_id')->unique()->values()->all();
        $accMap     = $this->accountMap($leadIds, $custIds);
        $accountIds = $accounts->pluck('account_id')->unique()->values()->all();

        $callsByAccount = CallLog::where('employee_mobile', $telecallerId)
            ->whereIn('account_id', $accountIds)
            ->whereBetween('called_at', [$start, $end])
            ->get(['account_id', 'call_outcome'])
            ->groupBy('account_id');

        // Grouped, not keyBy — a customer can have more than one visit in the
        // window (e.g. a callback re-visit), and keyBy silently keeps only
        // the last row fetched, which could be the visit *without* the
        // checkout/order while an earlier one in the same window had it.
        // "visited"/"order_given" must reflect ANY visit, not whichever one
        // happened to win that arbitrary pick.
        $visitsByAccount = ActionLog::where('employee_mobile', $telecallerId)
            ->whereIn('account_id', $accountIds)
            ->whereBetween('check_in_at', [$start, $end])
            ->orderBy('check_in_at')
            ->get(['account_id', 'order_no', 'check_in_at', 'check_out_at', 'outcome_name', 'call_outcome', 'payment_collected'])
            ->groupBy('account_id');

        // order_no on the visit only ever gets set by the SALESMAN checkout
        // flow ('required_if:outcome_slug,placed_order') — a telecaller's
        // checkout has no such field, so a telecaller convincing a customer
        // to order is only visible in the `orders` table itself, not on
        // their ActionLog row. Check both so neither flow is blind to it.
        $ordersByCustomer = $this->ordersInRange($custIds, $start, $end)->groupBy('buyer_userid');

        $rows = $accounts->map(function ($a) use ($accMap, $callsByAccount, $visitsByAccount, $ordersByCustomer) {
            $id        = (string) $a->account_id;
            $accCalls  = $callsByAccount->get($id, collect());
            $answered  = $accCalls->where('call_outcome', 'answered')->count();
            $accVisits = $visitsByAccount->get($id, collect());

            return [
                'account_id'   => $id,
                'account_type' => $a->account_type,
                'name'         => $accMap[$id]['name']  ?? 'Unknown',
                'phone'        => $accMap[$id]['phone'] ?? '',
                'calls_total'  => $accCalls->count(),
                'answered'     => $answered,
                'not_answered' => $accCalls->count() - $answered,
                'order_given'  => $accVisits->contains(fn ($v) => !empty($v->order_no)) || $ordersByCustomer->has($id),
                'visited'      => $accVisits->contains(fn ($v) => !empty($v->check_out_at)),
                // Salesman-oriented columns (a telecaller row just gets 0 / null).
                'visits_count' => $accVisits->count(),
                'last_stage'   => optional($accVisits->last())->outcome_name,
                'payment_collected' => (float) $accVisits->sum('payment_collected'),
            ];
        })->values();

        return response()->json(['success' => true, 'data' => [
            'telecaller_id' => $telecallerId,
            'from' => $start->toDateString(), 'to' => $end->toDateString(),
            'rows' => $rows,
        ]]);
    }

    // ── GET /api/telecaller-report/customer?from=&to=&telecaller_id=&account_id=&account_type= ─
    public function customerDetail(): JsonResponse
    {
        $viewer       = $this->viewer();
        $telecallerId = $this->resolveTelecallerId($viewer);
        [$start, $end] = $this->range();
        $accountId    = (string) request()->query('account_id', '');
        $accountType  = (string) request()->query('account_type', 'lead');
        abort_if($accountId === '', 422, 'account_id is required');

        // Every visit in the window, oldest first — a single-day filter
        // naturally yields at most one, a week/month filter can yield several.
        $visits = ActionLog::where('employee_mobile', $telecallerId)
            ->where('account_id', $accountId)
            ->whereBetween('check_in_at', [$start, $end])
            ->orderBy('check_in_at')
            ->get();

        $calls = CallLog::where('employee_mobile', $telecallerId)
            ->where('account_id', $accountId)
            ->whereBetween('called_at', [$start, $end])
            ->orderBy('called_at')
            ->get();

        $mapCall = fn (CallLog $c) => [
            'id'               => $c->id,
            'outcome'          => $c->call_outcome,
            'notes'            => $c->notes,
            'called_at'        => optional($c->called_at)->toIso8601String(),
            'duration_seconds' => $c->duration_seconds,
            'recording_url'    => $c->recording_url,
            'direction'        => $c->direction,
        ];

        // Cloud calls are the ones Knowlarity itself logged (source =
        // 'knowlarity'); everything else was hand-logged by the telecaller
        // after dialing normally.
        $normalCalls = $calls->where('source', '!=', 'knowlarity')->map($mapCall)->values();
        $cloudCalls  = $calls->where('source', '=', 'knowlarity')->map($mapCall)->values();

        $orderNos = $visits->pluck('order_no')->filter()->unique()->values();
        $ordersByNo = [];
        if ($orderNos->isNotEmpty()) {
            foreach (DB::table('orders')->whereIn('order_id', $orderNos)->get() as $o) {
                $ordersByNo[(string) $o->order_id] = $this->formatOrder($o);
            }
        }

        // Orders placed by this customer in the window, independent of any
        // visit's order_no — see the comment in summary() on why a
        // telecaller-driven order only shows up here, not on the ActionLog
        // row. Leads have no buyer_userid to look up, so this is empty for them.
        $orders = $accountType === 'customer'
            ? $this->ordersInRange([$accountId], $start, $end)->map(fn ($o) => $this->formatOrder($o))->values()
            : collect();

        $visitRows = $visits->map(function (ActionLog $v) use ($ordersByNo) {
            // duration_seconds is client-supplied at checkout and can be
            // missing/stale; check_in_at/check_out_at are the authoritative
            // source, so derive from them whenever both are present instead
            // of trusting a possibly-absent stored value.
            $duration = $v->duration_seconds;
            if ($v->check_in_at && $v->check_out_at) {
                $duration = $v->check_in_at->diffInSeconds($v->check_out_at);
            }

            return [
                'check_in_at'        => optional($v->check_in_at)->toIso8601String(),
                'check_out_at'       => optional($v->check_out_at)->toIso8601String(),
                'duration_seconds'   => $duration,
                'call_outcome'       => $v->call_outcome,
                'outcome_name'       => $v->outcome_name,
                'payment_collected'  => $v->payment_collected !== null ? (float) $v->payment_collected : null,
                'payment_mode'       => $v->payment_mode,
                'market_note'        => $v->market_note,
                'conversation_notes' => $v->conversation_notes,
                'general_notes'      => $v->general_notes,
                'order'              => !empty($v->order_no) ? ($ordersByNo[(string) $v->order_no] ?? null) : null,
            ];
        })->values();

        return response()->json(['success' => true, 'data' => [
            'account_id'   => $accountId,
            'account_type' => $accountType,
            'from' => $start->toDateString(), 'to' => $end->toDateString(),
            'visits'       => $visitRows,
            'orders'       => $orders,
            'normal_calls' => $normalCalls,
            'cloud_calls'  => $cloudCalls,
        ]]);
    }
}

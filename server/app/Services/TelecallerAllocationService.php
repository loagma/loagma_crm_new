<?php

namespace App\Services;

use App\Models\CallLog;
use App\Models\CustomerAssign;
use App\Models\LeadsAccount;
use App\Models\PincodeGeo;
use App\Models\TcAllocationItem;
use App\Models\TcAllocationPlan;
use App\Models\TelecallerLabel;
use App\Support\DailyAllocator;
use App\Support\GeoSequencer;
use App\Support\PincodeGeocoder;
use App\Support\TelecallerScope;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;

/**
 * Geographic, date-range calling plan for telecallers.
 *
 * Two independent rules combine into the plan:
 *  - geography (GeoSequencer): the order of pincodes — and of accounts inside
 *    each — from each pincode's own location (pincode numbers are only
 *    identifiers; customer coordinates are never used);
 *  - days (DailyAllocator::split): when the plan is created, the ordered
 *    accounts are split once over the From–To range and every account keeps
 *    that fixed date (tc_allocation_item_crm.allocated_date).
 *
 * Nothing is re-divided or carried forward automatically. An account whose
 * date passed without a call is "missed" (status still assigned/in_progress,
 * date < today) and the telecaller reassigns it to a date of their choice.
 * Accounts added later (new pincodes merged in, new customers in the plan's
 * pincodes) come in unscheduled (status pending, no date) for the telecaller
 * to date the same way.
 */
class TelecallerAllocationService
{
    public const EXCLUDED_LABELS = ['do_not_call', 'wrong_number'];

    // Accounts still owed a call: unscheduled (pending) or dated but not called.
    private const OPEN = ['pending', 'assigned', 'in_progress'];

    // Dated and not yet called — "missed" once the date has passed.
    private const DUE = ['assigned', 'in_progress'];

    public function activePlan(string $mobile): ?TcAllocationPlan
    {
        return TcAllocationPlan::where('employee_mobile', $mobile)->where('status', 'active')->first();
    }

    /**
     * Create the telecaller's plan for $startDate..$endDate — every account
     * gets a fixed date, split evenly in geographic order — or merge newly
     * selected pincodes into the active plan: their accounts are added
     * unscheduled (the telecaller dates them), existing accounts keep their
     * dates, and the plan's To date is updated (nothing is re-divided).
     */
    public function createOrMerge(string $mobile, array $pincodes, string $startDate, string $endDate): TcAllocationPlan
    {
        $pincodes = $this->normalisePincodes($pincodes);

        // Look up any pincode not yet located before taking the plan lock —
        // the geocoder is rate-limited (~1s per new pincode).
        $active = $this->activePlan($mobile);
        $this->ensurePincodeGeo($active
            ? $this->normalisePincodes(array_merge($active->selected_pincodes ?? [], $pincodes))
            : $pincodes);

        return DB::transaction(function () use ($mobile, $pincodes, $startDate, $endDate) {
            $plan = TcAllocationPlan::where('employee_mobile', $mobile)
                ->where('status', 'active')->lockForUpdate()->first();

            $union = $plan
                ? $this->normalisePincodes(array_merge($plan->selected_pincodes ?? [], $pincodes))
                : $pincodes;

            $candidates = $this->candidates($mobile, $union);
            if (empty($candidates)) {
                throw ValidationException::withMessages([
                    'pincodes' => 'No callable customers or leads found in the selected pincodes.',
                ]);
            }

            if ($plan) {
                $sequence = $this->mergedSequence($plan, $union);
                $plan->update([
                    'selected_pincodes' => $union,
                    'pincode_sequence'  => $sequence,
                    'end_date'          => $endDate,
                ]);
                // New accounts come in unscheduled; existing ones only get re-ranked.
                $this->upsertQueue($plan, $this->rankAccounts($candidates, $sequence));
                return $plan->fresh();
            }

            $sequence = $this->sequenceFor($union)['sequence'];
            $rows = $this->rankAccounts($candidates, $sequence);
            $dates = DailyAllocator::datesFor(count($rows), $startDate, $endDate);
            foreach ($rows as $i => &$row) {
                $row['status'] = 'assigned';
                $row['allocated_date'] = $dates[$i];
            }
            unset($row);

            $plan = TcAllocationPlan::create([
                'employee_mobile'   => $mobile,
                'selected_pincodes' => $union,
                'pincode_sequence'  => $sequence,
                // Informational: accounts per day when the plan was made.
                'daily_capacity'    => (int) ceil(count($rows) / DailyAllocator::daysInclusive($startDate, $endDate)),
                'start_date'        => $startDate,
                'end_date'          => $endDate,
                'status'            => 'active',
            ]);
            $this->upsertQueue($plan, $rows);

            return $plan->fresh();
        });
    }

    /**
     * Today's list: the accounts dated today, in plan order. Returns
     * [plan|null, items[]]. Also queues accounts that newly appeared in the
     * plan's pincodes (unscheduled) and skips accounts labelled do-not-call.
     */
    public function today(string $mobile): array
    {
        $today = Carbon::today()->toDateString();

        $plan = DB::transaction(function () use ($mobile) {
            $plan = TcAllocationPlan::where('employee_mobile', $mobile)
                ->where('status', 'active')->lockForUpdate()->first();
            if ($plan) {
                $this->queueNewAccounts($plan);
                $this->skipLabelled($plan);
                $this->completeIfDone($plan);
            }
            return $plan?->fresh();
        });

        // Completed/cancelled plans still show what was dated today.
        $plan ??= TcAllocationPlan::where('employee_mobile', $mobile)->latest('id')->first();
        if (!$plan) {
            return [null, []];
        }

        $items = TcAllocationItem::where('plan_id', $plan->id)
            ->where('allocated_date', $today)
            ->orderBy('pincode_rank')->orderBy('account_rank')
            ->get();

        return [$plan, $this->enrich($items)];
    }

    /** Plan progress + every account's date/status for the Allotted Customer screen. */
    public function progress(string $mobile): ?array
    {
        $plan = $this->activePlan($mobile);
        if (!$plan) {
            return null;
        }

        $today = Carbon::today()->toDateString();
        $start = $plan->start_date->toDateString();
        $end = $plan->end_date->toDateString();

        $items = TcAllocationItem::where('plan_id', $plan->id)
            ->orderBy('pincode_rank')->orderBy('account_rank')
            ->get(['account_id', 'pincode', 'status', 'allocated_date']);

        $schedule = [];
        $byStatus = [];
        $missed = 0;
        $unscheduled = 0;
        $todayCount = 0;
        $remaining = [];
        foreach ($items as $it) {
            $date = $it->allocated_date?->toDateString();
            $byStatus[$it->status] = ($byStatus[$it->status] ?? 0) + 1;
            if ($date === null) {
                $unscheduled += $it->status === 'pending' ? 1 : 0;
            } else {
                $schedule[$it->account_id] = ['date' => $date, 'status' => $it->status];
                $todayCount += $date === $today ? 1 : 0;
                $missed += ($date < $today && in_array($it->status, self::DUE, true)) ? 1 : 0;
            }
            if (in_array($it->status, self::OPEN, true)) {
                $remaining[$it->pincode] = ($remaining[$it->pincode] ?? 0) + 1;
            }
        }

        $total = $items->count();
        $open = (int) collect(self::OPEN)->sum(fn ($s) => $byStatus[$s] ?? 0);

        return [
            'plan_id'           => $plan->id,
            'today'             => $today,
            'start_date'        => $start,
            'end_date'          => $end,
            'total_days'        => DailyAllocator::daysInclusive($start, $end),
            // Day N of the range (0 before it starts; can exceed total_days after the To date).
            'day'               => $today < $start ? 0 : DailyAllocator::daysInclusive($start, $today),
            'days_left'         => $today > $end ? 0 : DailyAllocator::daysInclusive(max($today, $start), $end),
            'daily_capacity'    => $plan->daily_capacity,
            'today_count'       => $todayCount,
            'selected_pincodes' => $plan->selected_pincodes,
            'pincode_sequence'  => $plan->pincode_sequence,
            'total'             => $total,
            'done'              => $total - $open,
            'pending'           => $open,
            'missed'            => $missed,
            'unscheduled'       => $unscheduled,
            'status_counts'     => $byStatus,
            'remaining_by_pincode' => collect($remaining)
                ->map(fn ($n, $p) => ['pincode' => (string) $p, 'remaining' => $n])->values(),
            // account_id => {date: Y-m-d, status} for every dated account.
            'schedule'          => $schedule,
            'created_at'        => $plan->created_at,
        ];
    }

    /**
     * Set the date of the given accounts in the telecaller's active plan —
     * used for missed accounts (date passed, not called), unscheduled ones
     * (added later) and to move any not-yet-called account. Called, callback
     * and done accounts are left alone. A date past the plan's To date
     * extends the To date. Returns how many accounts were updated.
     */
    public function reassign(string $mobile, array $accountIds, string $date): int
    {
        return DB::transaction(function () use ($mobile, $accountIds, $date) {
            $plan = TcAllocationPlan::where('employee_mobile', $mobile)
                ->where('status', 'active')->lockForUpdate()->first();
            if (!$plan) {
                return 0;
            }

            $updated = 0;
            foreach (array_chunk(array_values(array_unique(array_map('strval', $accountIds))), 500) as $chunk) {
                $updated += TcAllocationItem::where('plan_id', $plan->id)
                    ->whereIn('account_id', $chunk)
                    ->whereIn('status', ['pending', 'assigned', 'in_progress', 'skipped'])
                    ->update(['status' => 'assigned', 'allocated_date' => $date, 'completed_at' => null]);
            }
            if ($date > $plan->end_date->toDateString()) {
                $plan->update(['end_date' => $date]);
            }
            return $updated;
        });
    }

    /**
     * Auto-distribute the given accounts (in the given order) over $dates —
     * the chosen weekdays of a From–To range, or the first N matching days
     * from a start date (see DailyAllocator::datesInRange / datesByCount): the
     * dates are filled in consecutive even blocks, so accounts that were
     * selected together (typically a pincode at a time) stay on the same or
     * neighbouring days. Only open or skipped accounts of the active plan
     * move; called accounts are left alone. A date past the plan's To date
     * extends it.
     *
     * @param string[] $accountIds in selection order
     * @param string[] $dates      Y-m-d, the days that receive accounts
     * @return array{updated: int, skipped_done: int, not_in_plan: int, dates: array<string, int>}|null
     *         null when there is no active plan
     * @throws ValidationException when there are no dates
     */
    public function distribute(string $mobile, array $accountIds, array $dates): ?array
    {
        $dates = array_values(array_unique($dates));
        sort($dates);
        if (empty($dates)) {
            throw ValidationException::withMessages([
                'weekdays' => 'None of the selected days falls between these dates.',
            ]);
        }

        return DB::transaction(function () use ($mobile, $accountIds, $dates) {
            $plan = TcAllocationPlan::where('employee_mobile', $mobile)
                ->where('status', 'active')->lockForUpdate()->first();
            if (!$plan) {
                return null;
            }

            $ids = array_values(array_unique(array_map('strval', $accountIds)));
            $inPlan = [];
            foreach (array_chunk($ids, 500) as $chunk) {
                foreach (TcAllocationItem::where('plan_id', $plan->id)->whereIn('account_id', $chunk)
                    ->get(['account_id', 'status']) as $it) {
                    $inPlan[$it->account_id] = $it->status;
                }
            }

            // Selection order is kept; only accounts that can still be called get a date.
            $movable = array_values(array_filter($ids, fn ($id) => isset($inPlan[$id])
                && in_array($inPlan[$id], ['pending', 'assigned', 'in_progress', 'skipped'], true)));
            $positions = DailyAllocator::blocksOver(count($movable), $dates);

            $byDate = [];
            foreach ($movable as $i => $accountId) {
                $byDate[$positions[$i]][] = $accountId;
            }
            foreach ($byDate as $date => $group) {
                foreach (array_chunk($group, 500) as $chunk) {
                    TcAllocationItem::where('plan_id', $plan->id)
                        ->whereIn('account_id', $chunk)
                        ->update(['status' => 'assigned', 'allocated_date' => $date, 'completed_at' => null]);
                }
            }

            if ($byDate && ($lastUsed = max(array_keys($byDate))) > $plan->end_date->toDateString()) {
                $plan->update(['end_date' => $lastUsed]);
            }

            return [
                'updated'      => count($movable),
                'skipped_done' => count(array_filter($ids, fn ($id) => isset($inPlan[$id]) && !in_array($id, $movable, true))),
                'not_in_plan'  => count(array_filter($ids, fn ($id) => !isset($inPlan[$id]))),
                'dates'        => array_map('count', $byDate),
            ];
        });
    }

    public function cancel(string $mobile): bool
    {
        return TcAllocationPlan::where('employee_mobile', $mobile)
            ->where('status', 'active')->update(['status' => 'cancelled']) > 0;
    }

    /**
     * Reflect a logged call on the matching account in the active plan,
     * whatever its date (a missed account called later counts too).
     * Called from CallLog's saved event, so manual logs, action-log calls and
     * Knowlarity calls (created as 'pending', resolved by the webhook) all count.
     */
    public function recordCallOutcome(CallLog $log): void
    {
        $outcome = $log->call_outcome;
        if (!$log->account_id || !$log->employee_mobile || !$outcome || $outcome === 'pending') {
            return;
        }

        $status = match ($outcome) {
            'callback' => 'callback',
            // A Knowlarity 'invalid' can be a provider-side rejection (unverified
            // agent, expired number), not a bad customer number — don't drop the
            // account for that.
            'invalid'  => $log->source === 'knowlarity' ? null : 'skipped',
            // answered, complaint, busy, no_answer, switch_off: the attempt is
            // logged, so the account is done.
            default    => 'completed',
        };
        if ($status === null) {
            return;
        }

        $planId = TcAllocationPlan::where('employee_mobile', (string) $log->employee_mobile)
            ->where('status', 'active')->value('id');
        if (!$planId) {
            return;
        }

        TcAllocationItem::where('plan_id', $planId)
            ->where('account_id', (string) $log->account_id)
            ->whereIn('status', self::OPEN)
            ->update([
                'status'       => $status,
                'call_log_id'  => $log->id,
                'completed_at' => now(),
            ]);
    }

    // ── Upkeep ───────────────────────────────────────────────────────────────────

    private function completeIfDone(TcAllocationPlan $plan): void
    {
        if (!TcAllocationItem::where('plan_id', $plan->id)->whereIn('status', self::OPEN)->exists()) {
            $plan->update(['status' => 'completed']);
        }
    }

    /** Accounts that appeared in the plan's pincodes since it was built — added unscheduled. */
    private function queueNewAccounts(TcAllocationPlan $plan): void
    {
        $candidates = $this->candidates($plan->employee_mobile, $plan->selected_pincodes ?? []);
        $known = TcAllocationItem::where('plan_id', $plan->id)->pluck('account_id')->flip();
        $new = array_values(array_filter($candidates, fn ($c) => !isset($known[$c['account_id']])));
        if (empty($new)) {
            return;
        }

        $sequence = $plan->pincode_sequence ?? [];
        $pinRank = array_flip($sequence);
        $maxRank = TcAllocationItem::where('plan_id', $plan->id)
            ->select('pincode', DB::raw('MAX(account_rank) as m'))
            ->groupBy('pincode')->pluck('m', 'pincode');

        $rows = [];
        foreach (collect($new)->groupBy('pincode') as $pincode => $group) {
            $next = (int) ($maxRank[$pincode] ?? 0);
            foreach (self::orderWithinPincode($group->all()) as $c) {
                $rows[] = [
                    'account_id'   => $c['account_id'],
                    'account_type' => $c['account_type'],
                    'pincode'      => (string) $pincode,
                    'pincode_rank' => ($pinRank[$pincode] ?? count($sequence)) + 1,
                    'account_rank' => ++$next,
                ];
            }
        }
        $this->upsertQueue($plan, $rows);
    }

    private function skipLabelled(TcAllocationPlan $plan): void
    {
        $labelled = TelecallerLabel::where('employee_mobile', $plan->employee_mobile)
            ->whereIn('label', self::EXCLUDED_LABELS)->pluck('account_id')->all();
        foreach (array_chunk($labelled, 500) as $chunk) {
            TcAllocationItem::where('plan_id', $plan->id)
                ->whereIn('status', self::OPEN)
                ->whereIn('account_id', $chunk)
                ->update(['status' => 'skipped']);
        }
    }

    // ── Queue building ───────────────────────────────────────────────────────────

    /**
     * Assign (pincode_rank, account_rank) to every candidate: pincodes follow
     * the geographic sequence; an account belongs to a pincode purely by its
     * pincode field, and inside a pincode accounts keep a fixed order.
     */
    private function rankAccounts(array $candidates, array $sequence): array
    {
        $byPin = collect($candidates)->groupBy('pincode');

        $rows = [];
        foreach ($sequence as $i => $pincode) {
            $group = $byPin->get($pincode);
            if (!$group) {
                continue;
            }
            foreach (self::orderWithinPincode($group->all()) as $j => $c) {
                $rows[] = [
                    'account_id'   => $c['account_id'],
                    'account_type' => $c['account_type'],
                    'pincode'      => (string) $pincode,
                    'pincode_rank' => $i + 1,
                    'account_rank' => $j + 1,
                ];
            }
        }
        return $rows;
    }

    /** Stable order inside a pincode: customers first, then leads, each by id. */
    private static function orderWithinPincode(array $accounts): array
    {
        usort($accounts, fn ($a, $b) => [$a['account_type'] === 'lead', $a['account_id']] <=> [$b['account_type'] === 'lead', $b['account_id']]);
        return array_values($accounts);
    }

    /**
     * Insert new rows (unscheduled `pending` unless the row carries its own
     * status/date); for rows already in the plan only the position
     * (pincode + ranks) changes — status, date and history are kept.
     */
    private function upsertQueue(TcAllocationPlan $plan, array $rows): void
    {
        $now = now();
        $values = array_map(fn ($r) => $r + [
            'plan_id'         => $plan->id,
            'employee_mobile' => $plan->employee_mobile,
            'status'          => 'pending',
            'allocated_date'  => null,
            'created_at'      => $now,
            'updated_at'      => $now,
        ], $rows);

        foreach (array_chunk($values, 500) as $chunk) {
            TcAllocationItem::upsert(
                $chunk,
                ['plan_id', 'account_id'],
                ['pincode', 'pincode_rank', 'account_rank', 'updated_at']
            );
        }
    }

    // ── Candidates & coordinates ─────────────────────────────────────────────────

    /**
     * Callable accounts in the selected pincodes, limited to this telecaller's
     * scope: leads in their areas, `user` customers in their area pincodes, and
     * customers directly assigned to them (customer_assign_crm). Accounts the
     * telecaller labelled do_not_call / wrong_number are excluded.
     *
     * @return array<array{account_id: string, account_type: string, pincode: string}>
     */
    private function candidates(string $mobile, array $pincodes): array
    {
        if (empty($pincodes)) {
            return [];
        }
        [$areaIds, $areaPins] = TelecallerScope::areaScope($mobile);
        $areaPinSet = array_flip($areaPins);
        $excluded = TelecallerLabel::where('employee_mobile', $mobile)
            ->whereIn('label', self::EXCLUDED_LABELS)->pluck('account_id')->flip();

        $out = [];

        if (!empty($areaIds) || !empty($areaPins)) {
            $leads = LeadsAccount::query()
                ->whereIn('pincode', $pincodes)
                ->where(function ($s) use ($areaIds, $areaPins) {
                    if (!empty($areaIds)) {
                        $s->whereIn('areaId', $areaIds);
                    }
                    if (!empty($areaPins)) {
                        $s->orWhereIn('pincode', $areaPins);
                    }
                })
                ->get(['id', 'pincode']);
            foreach ($leads as $l) {
                $out[(string) $l->id] = [
                    'account_id'   => (string) $l->id,
                    'account_type' => 'lead',
                    'pincode'      => trim((string) $l->pincode),
                ];
            }
        }

        $areaSelected = array_values(array_filter($pincodes, fn ($p) => isset($areaPinSet[$p])));
        $assignedIds = CustomerAssign::where('employee_mobile', $mobile)->pluck('customer_userid')->all();

        $users = collect();
        if (!empty($areaSelected)) {
            $users = $users->concat(DB::table('user')->whereIn('pincode', $areaSelected)
                ->get(['userid', 'pincode']));
        }
        foreach (array_chunk($assignedIds, 1000) as $chunk) {
            $users = $users->concat(DB::table('user')->whereIn('userid', $chunk)->whereIn('pincode', $pincodes)
                ->get(['userid', 'pincode']));
        }

        foreach ($users->unique('userid') as $u) {
            $id = (string) $u->userid;
            $out[$id] = [
                'account_id'   => $id,
                'account_type' => 'customer',
                'pincode'      => trim((string) $u->pincode),
            ];
        }

        return array_values(array_filter($out, fn ($c) => !isset($excluded[$c['account_id']])));
    }

    /**
     * Make sure every pincode has a location in pincode_geo_crm. A pincode is
     * placed by its own location (looked up once via PincodeGeocoder and
     * cached as source = 'geocoded'), never by the coordinates of customers in
     * it. Rows already present — geocoded or admin 'manual' — are left alone.
     * Pincodes the geocoder can't find stay unlocated (sequenced last) until
     * an admin sets them via PUT /pincode-geo/{pincode}.
     *
     * @return string[] pincodes that are still unlocated
     */
    public function ensurePincodeGeo(array $pincodes, bool $write = true): array
    {
        $pincodes = $this->normalisePincodes($pincodes);
        if (empty($pincodes)) {
            return [];
        }
        $known = PincodeGeo::whereIn('pincode', $pincodes)->pluck('pincode')->map(fn ($p) => (string) $p)->flip();
        $missing = array_values(array_filter($pincodes, fn ($p) => !isset($known[$p])));
        if (empty($missing)) {
            return [];
        }

        $found = PincodeGeocoder::lookupMany($missing);
        if ($write && !empty($found)) {
            $now = now();
            $rows = [];
            foreach ($found as $pincode => [$lat, $lng]) {
                $rows[] = [
                    'pincode'      => (string) $pincode,
                    'lat'          => $lat,
                    'lng'          => $lng,
                    'source'       => 'geocoded',
                    'created_at'   => $now,
                    'updated_at'   => $now,
                ];
            }
            PincodeGeo::upsert($rows, ['pincode'], ['lat', 'lng', 'source', 'updated_at']);
        }

        return array_values(array_filter($missing, fn ($p) => !isset($found[$p])));
    }

    /** @return array{sequence: string[], clusters: string[][], unlocated: string[]} */
    public function sequenceFor(array $pincodes, ?array $from = null): array
    {
        $geo = PincodeGeo::whereIn('pincode', $pincodes)->get()->keyBy('pincode');
        $points = [];
        foreach ($pincodes as $p) {
            $points[$p] = isset($geo[$p]) ? [$geo[$p]->lat, $geo[$p]->lng] : null;
        }
        return GeoSequencer::sequence($points, (float) config('telecaller.allocation_cluster_km', 5.0), $from);
    }

    /**
     * Sequence for a merge into a plan that is already under way: the part of
     * the walk already started (up to the last pincode with any account handed
     * out) stays fixed, and every untouched pincode — old or newly selected —
     * is re-sequenced onward from where the walk currently stands. This keeps
     * "finish what's pending before moving further" instead of jumping back to
     * a new pincode that happens to sit behind the current position.
     */
    private function mergedSequence(TcAllocationPlan $plan, array $union): array
    {
        $old = array_map('strval', $plan->pincode_sequence ?? []);
        $started = TcAllocationItem::where('plan_id', $plan->id)
            ->where(fn ($q) => $q->where('status', '!=', 'pending')->orWhereNotNull('allocated_date'))
            ->distinct()->pluck('pincode')->map(fn ($p) => (string) $p)->flip();

        $lastStarted = -1;
        foreach ($old as $i => $p) {
            if (isset($started[$p])) {
                $lastStarted = $i;
            }
        }
        if ($lastStarted < 0) {
            return $this->sequenceFor($union)['sequence'];
        }

        $prefix = array_slice($old, 0, $lastStarted + 1);
        $rest = array_values(array_diff($union, $prefix));
        if (empty($rest)) {
            return $prefix;
        }

        $here = null;
        $geo = PincodeGeo::whereIn('pincode', $prefix)->get()->keyBy('pincode');
        foreach (array_reverse($prefix) as $p) {
            if (isset($geo[$p])) {
                $here = [$geo[$p]->lat, $geo[$p]->lng];
                break;
            }
        }
        return array_merge($prefix, $this->sequenceFor($rest, $here)['sequence']);
    }

    /** Display fields for today's items (works for accounts outside the worklist too). */
    private function enrich($items): array
    {
        $leadIds = $items->where('account_type', 'lead')->pluck('account_id')->all();
        $custIds = $items->where('account_type', 'customer')->pluck('account_id')->all();

        $leads = empty($leadIds) ? collect() : LeadsAccount::whereIn('id', $leadIds)
            ->get(['id', 'businessName', 'personName', 'contactNumber', 'area', 'city', 'pincode', 'customerStage', 'address', 'latitude', 'longitude'])
            ->keyBy(fn ($l) => (string) $l->id);
        $custs = empty($custIds) ? collect() : DB::table('user')->whereIn('userid', $custIds)
            ->get(['userid', 'name', 'shop_name', 'contactno', 'city', 'pincode', 'address', 'shop_address', 'latitude', 'longitude'])
            ->keyBy(fn ($c) => (string) $c->userid);

        $rows = [];
        foreach ($items as $it) {
            $base = [
                'item_id'           => $it->id,
                'account_id'        => $it->account_id,
                'account_type'      => $it->account_type,
                'allocation_status' => $it->status,
                'pincode'           => $it->pincode,
            ];
            if ($it->account_type === 'lead' && ($l = $leads->get($it->account_id))) {
                $rows[] = $base + [
                    'name'          => $l->businessName ?: $l->personName,
                    'business_name' => $l->businessName,
                    'person_name'   => $l->personName,
                    'phone'         => $l->contactNumber,
                    'area'          => $l->area,
                    'city'          => $l->city,
                    'stage'         => $l->customerStage ?: 'lead',
                    'address'       => $l->address,
                    'latitude'      => $l->latitude,
                    'longitude'     => $l->longitude,
                ];
            } elseif ($it->account_type === 'customer' && ($c = $custs->get($it->account_id))) {
                $rows[] = $base + [
                    'name'          => $c->shop_name ?: $c->name,
                    'business_name' => $c->shop_name,
                    'person_name'   => $c->name,
                    'phone'         => $c->contactno,
                    'area'          => $c->city,
                    'city'          => $c->city,
                    'stage'         => 'customer',
                    'address'       => trim((string) $c->address) !== '' ? $c->address : ($c->shop_address ?: ''),
                    // Display only (map link) — never used for allocation.
                    'latitude'      => $c->latitude,
                    'longitude'     => $c->longitude,
                ];
            }
        }
        return $rows;
    }

    // ── Helpers ──────────────────────────────────────────────────────────────────

    private function normalisePincodes(array $pincodes): array
    {
        $out = [];
        foreach ($pincodes as $p) {
            $p = trim((string) $p);
            if ($p !== '') {
                $out[$p] = true;
            }
        }
        return array_map('strval', array_keys($out));
    }

}

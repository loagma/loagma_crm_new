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
 * Geographic, capacity-based daily calling allocation for telecallers.
 *
 * Two independent rules combine into the daily list:
 *  - geography (GeoSequencer): which pincode — and which account inside it —
 *    comes next, from each pincode's own location (pincode numbers are only
 *    identifiers; customer coordinates are never used);
 *  - capacity (DailyAllocator): how many accounts today, with no per-pincode
 *    quota, so a half-finished pincode carries forward into the next day.
 *
 * The queue is tc_allocation_item_crm ordered by (pincode_rank, account_rank);
 * "where we stopped" is simply the lowest-ranked pending row. Today's list is
 * built lazily on the first request of each IST day, so a day the telecaller
 * doesn't work consumes nothing.
 */
class TelecallerAllocationService
{
    public const EXCLUDED_LABELS = ['do_not_call', 'wrong_number'];

    // Accounts still owed a call in this plan (pending + handed out but unworked).
    private const OPEN = ['pending', 'assigned', 'in_progress'];

    public function activePlan(string $mobile): ?TcAllocationPlan
    {
        return TcAllocationPlan::where('employee_mobile', $mobile)->where('status', 'active')->first();
    }

    /**
     * Create the telecaller's plan, or merge newly selected pincodes into the
     * active one: the sequence is recomputed over the union, open accounts are
     * re-ranked, new accounts are queued, completed history is untouched.
     * The (possibly new) capacity applies from the next daily allocation.
     */
    public function createOrMerge(string $mobile, array $pincodes, int $capacity): TcAllocationPlan
    {
        $pincodes = $this->normalisePincodes($pincodes);

        // Look up any pincode not yet located before taking the plan lock —
        // the geocoder is rate-limited (~1s per new pincode).
        $active = $this->activePlan($mobile);
        $this->ensurePincodeGeo($active
            ? $this->normalisePincodes(array_merge($active->selected_pincodes ?? [], $pincodes))
            : $pincodes);

        return DB::transaction(function () use ($mobile, $pincodes, $capacity) {
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

            $sequence = $plan ? $this->mergedSequence($plan, $union) : $this->sequenceFor($union)['sequence'];

            if ($plan) {
                $plan->update([
                    'selected_pincodes' => $union,
                    'pincode_sequence'  => $sequence,
                    'daily_capacity'    => $capacity,
                ]);
            } else {
                $plan = TcAllocationPlan::create([
                    'employee_mobile'   => $mobile,
                    'selected_pincodes' => $union,
                    'pincode_sequence'  => $sequence,
                    'daily_capacity'    => $capacity,
                    'status'            => 'active',
                ]);
            }

            $this->upsertQueue($plan, $this->rankAccounts($candidates, $sequence));

            return $plan->fresh();
        });
    }

    /**
     * Today's allocated accounts, allocating them first if this is the first
     * request of the IST day. Returns [plan|null, items[]].
     */
    public function today(string $mobile): array
    {
        $today = Carbon::today()->toDateString();

        $plan = DB::transaction(function () use ($mobile, $today) {
            $plan = TcAllocationPlan::where('employee_mobile', $mobile)
                ->where('status', 'active')->lockForUpdate()->first();
            if (!$plan) {
                return null;
            }

            $alreadyToday = TcAllocationItem::where('plan_id', $plan->id)
                ->where('allocated_date', $today)->exists();
            if (!$alreadyToday) {
                $this->allocateDay($plan, $today);
            }
            return $plan->fresh();
        });

        if (!$plan) {
            // Completed/cancelled plans still show what was handed out today.
            $plan = TcAllocationPlan::where('employee_mobile', $mobile)->latest('id')->first();
        }
        if (!$plan) {
            return [null, []];
        }

        $items = TcAllocationItem::where('plan_id', $plan->id)
            ->where('allocated_date', $today)
            ->orderBy('pincode_rank')->orderBy('account_rank')
            ->get();

        return [$plan, $this->enrich($items)];
    }

    /** Plan progress for the Allotted Customer screen. */
    public function progress(string $mobile): ?array
    {
        $plan = $this->activePlan($mobile);
        if (!$plan) {
            return null;
        }

        $byStatus = TcAllocationItem::where('plan_id', $plan->id)
            ->select('status', DB::raw('COUNT(*) as n'))->groupBy('status')->pluck('n', 'status');
        $days = TcAllocationItem::where('plan_id', $plan->id)
            ->whereNotNull('allocated_date')->distinct()->count('allocated_date');
        $remaining = TcAllocationItem::where('plan_id', $plan->id)
            ->whereIn('status', self::OPEN)
            ->select('pincode', DB::raw('COUNT(*) as n'), DB::raw('MIN(pincode_rank) as r'))
            ->groupBy('pincode')->orderBy('r')->get()
            ->map(fn ($r) => ['pincode' => $r->pincode, 'remaining' => (int) $r->n])->values();

        $total = (int) $byStatus->sum();
        $open = (int) collect(self::OPEN)->sum(fn ($s) => $byStatus[$s] ?? 0);

        return [
            'plan_id'           => $plan->id,
            'daily_capacity'    => $plan->daily_capacity,
            'selected_pincodes' => $plan->selected_pincodes,
            'pincode_sequence'  => $plan->pincode_sequence,
            'day'               => $days,
            'total'             => $total,
            'done'              => $total - $open,
            'pending'           => $open,
            'status_counts'     => $byStatus,
            'remaining_by_pincode' => $remaining,
            'estimated_days_left'  => $plan->daily_capacity > 0 ? (int) ceil($open / $plan->daily_capacity) : null,
            'created_at'        => $plan->created_at,
        ];
    }

    public function cancel(string $mobile): bool
    {
        return TcAllocationPlan::where('employee_mobile', $mobile)
            ->where('status', 'active')->update(['status' => 'cancelled']) > 0;
    }

    /**
     * Reflect a logged call on the matching account in today's allocation.
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
            // logged, so the account is done for this cycle.
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
            ->whereIn('status', ['assigned', 'in_progress'])
            ->update([
                'status'       => $status,
                'call_log_id'  => $log->id,
                'completed_at' => now(),
            ]);
    }

    // ── Daily allocation ─────────────────────────────────────────────────────────

    private function allocateDay(TcAllocationPlan $plan, string $today): void
    {
        // Carry forward: anything handed out on an earlier day but never worked
        // goes back to pending at its original rank, so it is served first.
        TcAllocationItem::where('plan_id', $plan->id)
            ->whereIn('status', ['assigned', 'in_progress'])
            ->where('allocated_date', '<', $today)
            ->update(['status' => 'pending', 'allocated_date' => null]);

        $this->queueNewAccounts($plan);
        $this->skipLabelled($plan);

        $pending = TcAllocationItem::where('plan_id', $plan->id)
            ->where('status', 'pending')
            ->orderBy('pincode_rank')->orderBy('account_rank')
            ->limit($plan->daily_capacity)
            ->pluck('id')->all();

        $ids = DailyAllocator::take($pending, $plan->daily_capacity);
        if (empty($ids)) {
            $plan->update(['status' => 'completed']);
            return;
        }

        foreach (array_chunk($ids, 500) as $chunk) {
            TcAllocationItem::whereIn('id', $chunk)
                ->update(['status' => 'assigned', 'allocated_date' => $today]);
        }
    }

    /** Accounts that appeared in the plan's pincodes since it was built. */
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
                ->where('status', 'pending')
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
     * Insert new queue rows as pending; for rows already in the plan only the
     * position (pincode + ranks) changes — status and history are kept.
     */
    private function upsertQueue(TcAllocationPlan $plan, array $rows): void
    {
        $now = now();
        $values = array_map(fn ($r) => $r + [
            'plan_id'         => $plan->id,
            'employee_mobile' => $plan->employee_mobile,
            'status'          => 'pending',
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
                    'sample_count' => 0,
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

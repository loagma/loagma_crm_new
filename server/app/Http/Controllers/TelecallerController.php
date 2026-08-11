<?php

namespace App\Http\Controllers;

use App\Jobs\ProcessKnowlarityCallCompleted;
use App\Models\Area;
use App\Models\AreaAssign;
use App\Models\CallLog;
use App\Models\DeliStaff;
use App\Models\InchargeAssign;
use App\Models\LeadsAccount;
use App\Models\TelecallerLabel;
use App\Services\KnowlarityService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Response;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use Tymon\JWTAuth\Facades\JWTAuth;

/**
 * Live data for the telecaller dashboard + agent modules. Every query is
 * scoped to the logged-in telecaller (JWT mobile) EXCEPT teamCallHistory()
 * and the hierarchy branch of callRecording(), which are the one place a
 * senior (teleadmin/incharge chain/admin) may view someone else's calls —
 * see the hierarchy helpers below, same pattern as ComplaintController.
 */
class TelecallerController extends Controller
{
    private const OUTCOMES = ['answered', 'busy', 'no_answer', 'switch_off', 'invalid', 'callback'];

    private function mobile(): string
    {
        return (string) JWTAuth::parseToken()->authenticate()->mobile;
    }

    // ── Hierarchy helpers (same pattern as AttendanceController/ComplaintController) ─

    // Returns mobile strings of the children directly assigned to this parent
    // incharge in incharge_assign_crm. Works at every level of the hierarchy
    // (head_incharge → zonal_incharge → area_incharge/teleadmin → telecaller)
    // since the table is generically keyed by the parent's mobile.
    private function getAssignedInchargeMobiles(string $parentMobile): array
    {
        $assign = InchargeAssign::where('head_incharge_id', (int) $parentMobile)->first();
        if (!$assign || empty($assign->incharge_ids)) return [];
        return array_map('strval', $assign->incharge_ids);
    }

    // Returns mobile strings of ALL descendants below this incharge, walking the
    // hierarchy recursively. Cycle-safe via the $visited set.
    private function getDescendantMobiles(string $parentMobile, array &$visited = []): array
    {
        if (isset($visited[$parentMobile])) return [];
        $visited[$parentMobile] = true;

        $descendants = [];
        foreach ($this->getAssignedInchargeMobiles($parentMobile) as $childMobile) {
            $descendants[] = $childMobile;
            $descendants = array_merge($descendants, $this->getDescendantMobiles($childMobile, $visited));
        }
        return array_values(array_unique($descendants));
    }

    // True if $viewerMobile may access $log: it's their own call, they're
    // admin, or the call's owner is somewhere in the viewer's own downward
    // hierarchy.
    private function canAccessCallLog(CallLog $log, string $viewerMobile): bool
    {
        if ((string) $log->employee_mobile === $viewerMobile) return true;

        $staff = DeliStaff::where('mobile', $viewerMobile)->first();
        if (!$staff) return false;
        if (strtolower($staff->role ?? '') === 'admin') return true;

        return \in_array((string) $log->employee_mobile, $this->getDescendantMobiles($viewerMobile), true);
    }

    /** [areaIds[], pincodes[]] assigned to this telecaller. */
    private function myAreaScope(string $mobile): array
    {
        $assign = AreaAssign::where('employee_id', (int) $mobile)->first();
        $areaIds = $assign ? array_values(array_filter(array_map('intval', $assign->area_ids ?? []))) : [];

        $pincodes = [];
        if (!empty($areaIds)) {
            foreach (Area::whereIn('id', $areaIds)->get() as $area) {
                foreach ((array) ($area->pincodes ?? []) as $p) {
                    $pincodes[] = (string) $p;
                }
            }
        }
        return [$areaIds, array_values(array_unique($pincodes))];
    }

    /** Query of leads in this telecaller's areas (areaId OR pincode). */
    private function myLeadsQuery(array $areaIds, array $pincodes)
    {
        $q = LeadsAccount::query();
        if (empty($areaIds) && empty($pincodes)) {
            return $q->whereRaw('1 = 0');
        }
        return $q->where(function ($s) use ($areaIds, $pincodes) {
            if (!empty($areaIds)) {
                $s->whereIn('areaId', $areaIds);
            }
            if (!empty($pincodes)) {
                $s->orWhereIn('pincode', $pincodes);
            }
        });
    }

    /** account_id => {name, phone, area, pincode, stage} for the given logs. */
    private function enrich($logs): array
    {
        $leadIds = $logs->where('account_type', 'lead')->pluck('account_id')->filter()->unique()->values()->all();
        $custIds = $logs->where('account_type', 'customer')->pluck('account_id')->filter()->unique()->values()->all();

        $map = [];
        if (!empty($leadIds)) {
            $leads = LeadsAccount::whereIn('id', $leadIds)
                ->get(['id', 'businessName', 'personName', 'contactNumber', 'area', 'pincode', 'customerStage']);
            foreach ($leads as $l) {
                $map[(string) $l->id] = [
                    'name'    => $l->businessName ?: $l->personName,
                    'phone'   => $l->contactNumber,
                    'area'    => $l->area,
                    'pincode' => $l->pincode,
                    'stage'   => $l->customerStage,
                ];
            }
        }
        if (!empty($custIds)) {
            $customers = DB::table('user')->whereIn('userid', $custIds)
                ->get(['userid', 'name', 'shop_name', 'contactno', 'city', 'pincode']);
            foreach ($customers as $c) {
                $map[(string) $c->userid] = [
                    'name'    => $c->shop_name ?: $c->name,
                    'phone'   => $c->contactno,
                    'area'    => $c->city,
                    'pincode' => $c->pincode,
                    'stage'   => 'customer',
                ];
            }
        }
        return $map;
    }

    // ── Dashboard ───────────────────────────────────────────────────────────────
    public function dashboard(): JsonResponse
    {
        $mobile   = $this->mobile();
        $todayStr = Carbon::today()->toDateString();

        $callsToday    = CallLog::where('employee_mobile', $mobile)->whereDate('called_at', $todayStr)->count();
        $answeredToday = CallLog::where('employee_mobile', $mobile)->whereDate('called_at', $todayStr)
            ->where('call_outcome', 'answered')->count();
        $connectRate   = $callsToday > 0 ? (int) round($answeredToday * 100 / $callsToday) : 0;

        // Outcome breakdown (today)
        $rawCounts = CallLog::where('employee_mobile', $mobile)->whereDate('called_at', $todayStr)
            ->select('call_outcome', DB::raw('count(*) as c'))->groupBy('call_outcome')->pluck('c', 'call_outcome');
        $outcomeCounts = [];
        foreach (self::OUTCOMES as $o) {
            $outcomeCounts[$o] = (int) ($rawCounts[$o] ?? 0);
        }

        // Last 7 days
        $weekDays = [];
        $weekCalls = [];
        for ($i = 6; $i >= 0; $i--) {
            $d = Carbon::today()->subDays($i);
            $weekDays[]  = $d->format('D');
            $weekCalls[] = CallLog::where('employee_mobile', $mobile)->whereDate('called_at', $d->toDateString())->count();
        }

        // Follow-ups
        $dueBase = CallLog::where('employee_mobile', $mobile)->whereNotNull('follow_up_date')->where('callback_done', false);
        $followUpsDue     = (clone $dueBase)->whereDate('follow_up_date', '<=', $todayStr)->count();
        $followUpsOverdue = (clone $dueBase)->whereDate('follow_up_date', '<', $todayStr)->count();

        // My leads (area scope) → conversions + funnel
        [$areaIds, $pincodes] = $this->myAreaScope($mobile);
        $conversions = (clone $this->myLeadsQuery($areaIds, $pincodes))->where('customerStage', 'customer')->count();
        $interested  = (clone $this->myLeadsQuery($areaIds, $pincodes))
            ->whereIn('customerStage', ['prospect', 'qualified', 'opportunity'])->count();

        $leadsCalled = CallLog::where('employee_mobile', $mobile)->where('account_type', 'lead')
            ->distinct('account_id')->count('account_id');
        $connected = CallLog::where('employee_mobile', $mobile)->where('account_type', 'lead')
            ->where('call_outcome', 'answered')->distinct('account_id')->count('account_id');

        return response()->json([
            'success' => true,
            'data'    => [
                'kpis' => [
                    'calls_today'       => $callsToday,
                    'connect_rate'      => $connectRate,
                    'conversions'       => $conversions,
                    'follow_ups_due'    => $followUpsDue,
                    'follow_ups_overdue' => $followUpsOverdue,
                ],
                'outcome_counts' => $outcomeCounts,
                'week'   => ['days' => $weekDays, 'calls' => $weekCalls],
                'funnel' => [
                    ['label' => 'Leads Called', 'value' => $leadsCalled],
                    ['label' => 'Connected', 'value' => $connected],
                    ['label' => 'Interested', 'value' => $interested],
                    ['label' => 'Customers', 'value' => $conversions],
                ],
                'daily_target' => 60,
            ],
        ]);
    }

    // ── Today's callbacks (due + overdue) ────────────────────────────────────────
    public function callbacks(): JsonResponse
    {
        $mobile   = $this->mobile();
        $todayStr = Carbon::today()->toDateString();

        $logs = CallLog::where('employee_mobile', $mobile)
            ->whereNotNull('follow_up_date')
            ->where('callback_done', false)
            ->orderBy('follow_up_date')
            ->get();

        $enriched = $this->enrich($logs);

        $data = $logs->map(function (CallLog $l) use ($enriched, $todayStr) {
            $acc = $enriched[$l->account_id] ?? [];
            $fu  = optional($l->follow_up_date)->toDateString();
            return [
                'id'             => $l->id,
                'account_id'     => $l->account_id,
                'account_type'   => $l->account_type,
                'name'           => $acc['name'] ?? 'Unknown',
                'phone'          => $acc['phone'] ?? '',
                'area'           => $acc['area'] ?? '',
                'stage'          => $acc['stage'] ?? '',
                'notes'          => $l->notes,
                'follow_up_date' => $fu,
                'overdue'        => $fu !== null && $fu < $todayStr,
            ];
        })->values();

        return response()->json(['success' => true, 'data' => $data]);
    }

    // ── Call history ─────────────────────────────────────────────────────────────
    public function callHistory(): JsonResponse
    {
        $mobile = $this->mobile();

        $logs = CallLog::where('employee_mobile', $mobile)->orderBy('called_at', 'desc')->limit(100)->get();
        $enriched = $this->enrich($logs);

        $data = $logs->map(function (CallLog $l) use ($enriched) {
            $acc = $enriched[$l->account_id] ?? [];
            $raw = $l->raw_payload ?? [];
            return [
                'id'               => $l->id,
                'account_id'       => $l->account_id,
                'account_type'     => $l->account_type,
                'name'             => $acc['name'] ?? 'Unknown',
                'phone'            => $acc['phone'] ?? '',
                'outcome'          => $l->call_outcome,
                'notes'            => $l->notes,
                'called_at'        => optional($l->called_at)->toIso8601String(),
                // Knowlarity-specific fields (null for manually-logged calls) - the
                // full provider call log content, not just the derived outcome.
                'source'           => $l->source,
                'direction'        => $l->direction,
                'duration_seconds' => $l->duration_seconds,
                'recording_url'    => $l->recording_url,
                'call_uuid'        => $l->knowlarity_call_id,
                'sr_number'        => $raw['knowlarity_number'] ?? null,
                'customer_number'  => $raw['customer_number'] ?? null,
            ];
        })->values();

        return response()->json(['success' => true, 'data' => $data]);
    }

    // ── Team call history (hierarchy-scoped) ──────────────────────────────────────
    // For admin + the telecaller-senior chain (teleadmin and everyone above it —
    // see the `role:` middleware on this route in routes/api.php). admin sees
    // every telecaller's calls; everyone else sees only their own descendants'
    // (via getDescendantMobiles), same shape/fields as callHistory() plus who
    // made the call, so this doubles as "my own team's recordings" for a
    // teleadmin and "any telecaller's" for admin — never a flat, unscoped dump.
    public function teamCallHistory(): JsonResponse
    {
        $mobile = $this->mobile();
        $staff  = DeliStaff::where('mobile', $mobile)->first();
        if (!$staff) {
            return response()->json(['success' => false, 'message' => 'Unauthorized'], 403);
        }

        $role         = strtolower($staff->role ?? '');
        $targetMobile = request()->query('mobile');

        if ($role === 'admin') {
            $query = CallLog::query();
            if ($targetMobile) {
                $query->where('employee_mobile', $targetMobile);
            }
        } else {
            $descendants = $this->getDescendantMobiles($mobile);
            if ($targetMobile) {
                if (!\in_array((string) $targetMobile, $descendants, true)) {
                    return response()->json(['success' => false, 'message' => 'That employee is not in your team'], 403);
                }
                $query = CallLog::where('employee_mobile', $targetMobile);
            } else {
                if (empty($descendants)) {
                    return response()->json(['success' => true, 'data' => []]);
                }
                $query = CallLog::whereIn('employee_mobile', $descendants);
            }
        }

        $logs = $query->orderBy('called_at', 'desc')->limit(300)->get();
        $enriched = $this->enrich($logs);

        $staffNames = DeliStaff::whereIn('mobile', $logs->pluck('employee_mobile')->filter()->unique()->values())
            ->pluck('name', 'mobile');

        $data = $logs->map(function (CallLog $l) use ($enriched, $staffNames) {
            $acc = $enriched[$l->account_id] ?? [];
            $raw = $l->raw_payload ?? [];
            return [
                'id'               => $l->id,
                'employee_mobile'  => $l->employee_mobile,
                'employee_name'    => $staffNames[$l->employee_mobile] ?? $l->employee_mobile,
                'account_id'       => $l->account_id,
                'account_type'     => $l->account_type,
                'name'             => $acc['name'] ?? 'Unknown',
                'phone'            => $acc['phone'] ?? '',
                'outcome'          => $l->call_outcome,
                'notes'            => $l->notes,
                'called_at'        => optional($l->called_at)->toIso8601String(),
                'source'           => $l->source,
                'direction'        => $l->direction,
                'duration_seconds' => $l->duration_seconds,
                'recording_url'    => $l->recording_url,
                'call_uuid'        => $l->knowlarity_call_id,
                'sr_number'        => $raw['knowlarity_number'] ?? null,
                'customer_number'  => $raw['customer_number'] ?? null,
            ];
        })->values();

        return response()->json(['success' => true, 'data' => $data]);
    }

    /**
     * Polled right after a cloud (Knowlarity) call is triggered, so the app
     * can show live SR/call-log data and detect the moment the completed
     * webhook lands (call_outcome flips from 'pending' to a real outcome).
     */
    public function callStatus(string $id, KnowlarityService $knowlarity): JsonResponse
    {
        $mobile = $this->mobile();

        $log = CallLog::where('employee_mobile', $mobile)->where('id', $id)->first();
        if (!$log) {
            return response()->json(['success' => false, 'message' => 'Not found'], 404);
        }

        // The completed-call webhook has never actually fired for C2C calls on
        // this Knowlarity account (see KnowlarityService::getCallLogs) - the
        // only other reconciliation path is the hourly `knowlarity:reconcile`
        // cron, which leaves the live call screen stuck on 'pending' for up to
        // an hour after a call already finished. Once a few seconds have
        // passed, pull the provider's live call log directly on every poll so
        // the app resolves within seconds instead of waiting on the cron.
        if ($log->call_outcome === 'pending' && $log->called_at && $log->called_at->diffInSeconds(now()) >= 8) {
            $window = $log->called_at->copy()->subMinute();
            $logs = $knowlarity->getCallLogs(
                $window->format('Y-m-d H:i:sP'),
                now()->format('Y-m-d H:i:sP'),
            );
            $entries = $logs['objects'] ?? $logs['data'] ?? [];
            foreach ($entries as $entry) {
                if (is_array($entry)) {
                    ProcessKnowlarityCallCompleted::apply($entry);
                }
            }
            $log->refresh();
        }

        $enriched = $this->enrich(collect([$log]));
        $acc = $enriched[$log->account_id] ?? [];
        $raw = $log->raw_payload ?? [];

        return response()->json([
            'success' => true,
            'data' => [
                'id'               => $log->id,
                'account_id'       => $log->account_id,
                'account_type'     => $log->account_type,
                'name'             => $acc['name'] ?? 'Unknown',
                'phone'            => $acc['phone'] ?? '',
                'outcome'          => $log->call_outcome,
                'notes'            => $log->notes,
                'called_at'        => optional($log->called_at)->toIso8601String(),
                'source'           => $log->source,
                'direction'        => $log->direction,
                'duration_seconds' => $log->duration_seconds,
                'recording_url'    => $log->recording_url,
                'call_uuid'        => $log->knowlarity_call_id,
                'sr_number'        => $raw['knowlarity_number'] ?? null,
                'customer_number'  => $raw['customer_number'] ?? null,
            ],
        ]);
    }

    /**
     * Streams a call recording's bytes through the CRM (authenticated with
     * Knowlarity's credentials server-side), since the raw recording URL 401s
     * for any client that can't attach the authorization/x-api-key headers -
     * which no browser <audio> element or mobile media player can do.
     *
     * Auth here also accepts a `?token=` query param (JWTAuth's default parser
     * chain already supports it, on top of the Authorization header) because
     * the "download" case opens this URL directly via the OS/browser, which
     * can't attach a custom header the way an authenticated fetch() can.
     *
     * `?download=1` switches Content-Disposition to attachment so the browser/
     * OS saves it as a file instead of the default inline (streamed, played
     * in place, never saved) behaviour.
     */
    public function callRecording(string $id, KnowlarityService $knowlarity): Response
    {
        $mobile = $this->mobile();

        // Not scoped to `employee_mobile` at the query level (unlike every other
        // method here) because this single endpoint now serves two callers: the
        // telecaller's own recordings AND a senior's view of their team's — see
        // canAccessCallLog(). Kept as 404 rather than 403 for a log that exists
        // but isn't accessible, so an unauthorized id can't be distinguished
        // from one that simply doesn't exist.
        $log = CallLog::where('id', $id)->first();
        if (!$log || !$log->recording_url || !$this->canAccessCallLog($log, $mobile)) {
            abort(404, 'Recording not found');
        }

        [$bytes, $contentType] = $knowlarity->fetchRecording($log->recording_url);
        if ($bytes === '') {
            abort(502, 'Could not fetch recording');
        }

        // Knowlarity serves recordings as generic binary/octet-stream; every
        // sample fetched so far is actually MP3, so normalise for players that
        // rely on the content type to pick a decoder.
        if (!$contentType || str_contains($contentType, 'octet-stream')) {
            $contentType = 'audio/mpeg';
        }

        $disposition = request()->boolean('download')
            ? "attachment; filename=\"call-recording-{$id}.mp3\""
            : 'inline';

        return response($bytes, 200, [
            'Content-Type'        => $contentType,
            'Content-Length'      => (string) strlen($bytes),
            'Content-Disposition' => $disposition,
        ]);
    }

    // ── Worklist (leads + customers with derived/custom labels) ──────────────────
    public function worklist(): JsonResponse
    {
        $mobile = $this->mobile();
        [$areaIds, $pincodes] = $this->myAreaScope($mobile);

        $leads = $this->myLeadsQuery($areaIds, $pincodes)
            ->get(['id', 'businessName', 'personName', 'contactNumber', 'area', 'city', 'pincode', 'customerStage', 'address', 'latitude', 'longitude']);

        $customers = empty($pincodes)
            ? collect()
            : DB::table('user')->whereIn('pincode', $pincodes)->get(['userid', 'name', 'shop_name', 'contactno', 'city', 'pincode', 'address', 'shop_address', 'latitude', 'longitude']);

        // `user_addresses` is the customer's saved address book (one row per
        // address, one marked is_default per user) — batch-fetched so a
        // customer's worklist card can list every saved address.
        $addressesByUser = $customers->isEmpty()
            ? collect()
            : DB::table('user_addresses')
                ->whereIn('user_id', $customers->pluck('userid'))
                ->orderByDesc('is_default')
                ->orderBy('id')
                ->get(['user_id', 'address', 'type', 'is_default', 'lat', 'lng'])
                ->groupBy('user_id');

        $todayStr    = Carbon::today()->toDateString();
        $labels      = TelecallerLabel::where('employee_mobile', $mobile)->get()->keyBy('account_id');
        $calledToday = CallLog::where('employee_mobile', $mobile)
            ->whereDate('called_at', $todayStr)->whereNotNull('account_id')->pluck('account_id')->flip();
        $openFollow  = CallLog::where('employee_mobile', $mobile)
            ->whereNotNull('follow_up_date')->where('callback_done', false)->whereNotNull('account_id')->pluck('account_id')->flip();

        // Last contact (max called_at) and next open follow-up (min follow_up_date) per account.
        $lastContact = CallLog::where('employee_mobile', $mobile)->whereNotNull('account_id')
            ->select('account_id', DB::raw('MAX(called_at) as last_at'))
            ->groupBy('account_id')->pluck('last_at', 'account_id');
        $nextFollow  = CallLog::where('employee_mobile', $mobile)
            ->whereNotNull('follow_up_date')->where('callback_done', false)->whereNotNull('account_id')
            ->select('account_id', DB::raw('MIN(follow_up_date) as next_at'))
            ->groupBy('account_id')->pluck('next_at', 'account_id');

        $deriveLabel = function (string $id) use ($labels, $calledToday, $openFollow): string {
            if (isset($labels[$id])) {
                return $labels[$id]->label;
            }
            if ($openFollow->has($id)) {
                return 'follow_up';
            }
            if ($calledToday->has($id)) {
                return 'called_today';
            }
            return 'not_called';
        };

        $lastOf = fn (string $id) => isset($lastContact[$id]) ? Carbon::parse($lastContact[$id])->toDateString() : null;
        $nextOf = fn (string $id) => isset($nextFollow[$id]) ? Carbon::parse($nextFollow[$id])->toDateString() : null;

        $rows = [];
        foreach ($leads as $l) {
            $id = (string) $l->id;
            $rows[] = [
                'account_id'     => $id,
                'account_type'   => 'lead',
                'name'           => $l->businessName ?: $l->personName,
                'business_name'  => $l->businessName,
                'person_name'    => $l->personName,
                'phone'          => $l->contactNumber,
                'area'           => $l->area,
                'city'           => $l->city,
                'pincode'        => $l->pincode,
                'stage'          => $l->customerStage ?: 'lead',
                'label'          => $deriveLabel($id),
                'last_contact'   => $lastOf($id),
                'next_follow_up' => $nextOf($id),
                'address'        => $l->address,
                'addresses'      => [],
                'latitude'       => $l->latitude,
                'longitude'      => $l->longitude,
            ];
        }
        foreach ($customers as $c) {
            $id = (string) $c->userid;

            // Address 1 is the account's own `user.address` column; Address
            // 2+ are the saved entries in `user_addresses` (default first).
            $savedAddresses = $addressesByUser->get($c->userid, collect());
            $addrs = collect();
            if (trim((string) $c->address) !== '') {
                $addrs->push([
                    'address'    => $c->address,
                    'type'       => 'Account',
                    'is_default' => $savedAddresses->isEmpty(),
                    'latitude'   => $c->latitude,
                    'longitude'  => $c->longitude,
                ]);
            }
            $addrs = $addrs->concat($savedAddresses->map(fn ($a) => [
                'address'    => $a->address,
                'type'       => $a->type,
                'is_default' => $a->is_default === '1',
                'latitude'   => $a->lat,
                'longitude'  => $a->lng,
            ]));
            // Drop duplicates (e.g. `user.address` matching a saved entry
            // verbatim) so the same text isn't listed twice.
            $addrs = $addrs->unique(fn ($a) => strtolower(trim((string) $a['address'])))->values();
            $primary = $addrs->first();

            $rows[] = [
                'account_id'     => $id,
                'account_type'   => 'customer',
                'name'           => $c->shop_name ?: $c->name,
                'business_name'  => $c->shop_name,
                'person_name'    => $c->name,
                'phone'          => $c->contactno,
                'area'           => $c->city,
                'city'           => $c->city,
                'pincode'        => $c->pincode,
                'stage'          => 'customer',
                'label'          => $deriveLabel($id),
                'last_contact'   => $lastOf($id),
                'next_follow_up' => $nextOf($id),
                'address'        => $primary['address'] ?? ($c->shop_address ?: ''),
                'addresses'      => $addrs,
                'latitude'       => $primary['latitude']  ?? $c->latitude,
                'longitude'      => $primary['longitude'] ?? $c->longitude,
            ];
        }

        return response()->json(['success' => true, 'data' => $rows]);
    }

    // ── Set a custom label (Quick Actions / Do-Not-Call) ─────────────────────────
    public function setLabel(): JsonResponse
    {
        $mobile = $this->mobile();

        $data = validator(request()->only(['account_id', 'account_type', 'label']), [
            'account_id'   => 'required|string|max:191',
            'account_type' => 'required|in:lead,customer',
            'label'        => 'required|string|max:50',
        ])->validate();

        $label = TelecallerLabel::updateOrCreate(
            ['employee_mobile' => $mobile, 'account_id' => $data['account_id']],
            ['account_type' => $data['account_type'], 'label' => $data['label']],
        );

        return response()->json(['success' => true, 'data' => $label]);
    }
}

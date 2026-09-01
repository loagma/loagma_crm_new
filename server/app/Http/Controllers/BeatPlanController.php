<?php

namespace App\Http\Controllers;

use App\Models\ActionLog;
use App\Models\BeatPlan;
use App\Models\BeatPlanFollowup;
use App\Models\LeadsAccount;
use Carbon\Carbon;
use Illuminate\Http\JsonResponse;
use Illuminate\Support\Facades\DB;
use Tymon\JWTAuth\Facades\JWTAuth;

class BeatPlanController extends Controller
{
    // App runs in UTC but users are in India — anchor "today"/week to IST so the
    // local calendar day matches what the salesman sees on their device.
    private const TZ = 'Asia/Kolkata';

    // ── Helpers ───────────────────────────────────────────────────────────────

    private function salesmanId(): string
    {
        // Default guard is `web`/session (auth() returns null for API requests),
        // so parse the JWT explicitly — same pattern as OtpAuthController::me().
        return (string) JWTAuth::parseToken()->authenticate()->mobile;
    }

    // `user_addresses` is the customer's saved address book (one row per
    // address, one marked is_default per user) — batch-fetched and grouped
    // by user_id so a customer account can list every saved address.
    private function addressesByUserIds(array $userIds): \Illuminate\Support\Collection
    {
        if (empty($userIds)) {
            return collect();
        }

        return \DB::table('user_addresses')
            ->whereIn('user_id', $userIds)
            ->orderByDesc('is_default')
            ->orderBy('id')
            ->get(['user_id', 'address', 'type', 'is_default', 'lat', 'lng'])
            ->groupBy('user_id');
    }

    // Address 1 is the account's own `user.address` column; Address 2+ are
    // the saved entries in `user_addresses` (default first).
    private function buildAddressList(object $user, \Illuminate\Support\Collection $savedAddresses): \Illuminate\Support\Collection
    {
        $list = collect();
        if (trim((string) ($user->address ?? '')) !== '') {
            $list->push([
                'address'    => $user->address,
                'type'       => 'Account',
                'is_default' => $savedAddresses->isEmpty(),
                'latitude'   => $user->latitude ?? null,
                'longitude'  => $user->longitude ?? null,
            ]);
        }

        $list = $list->concat($savedAddresses->map(fn ($a) => [
            'address'    => $a->address,
            'type'       => $a->type,
            'is_default' => $a->is_default === '1',
            'latitude'   => $a->lat,
            'longitude'  => $a->lng,
        ]));

        // Drop duplicates (e.g. `user.address` matching a saved entry
        // verbatim) so the same text isn't listed twice.
        return $list->unique(fn ($a) => strtolower(trim((string) $a['address'])))->values();
    }

    // Shared by today()/range() so the customer shape stays identical in both.
    // `businessName` falls back to the contact's own name: `user.shop_name` is
    // NULL for B2C accounts, which left the Create Sales Order form showing a
    // blank customer.
    private function customerAccountPayload(object $user, \Illuminate\Support\Collection $savedAddresses): array
    {
        $addrs   = $this->buildAddressList($user, $savedAddresses);
        $primary = $addrs->first();

        $shopName = trim((string) ($user->shop_name ?? ''));
        $person   = trim((string) ($user->name ?? ''));

        return [
            'id'            => $user->userid,
            'accountCode'   => (string) ($user->party_code ?? ''),
            'businessName'  => $shopName !== '' ? $shopName : $person,
            'personName'    => $person,
            'contactNumber' => $user->contactno ?? '',
            'address'       => $primary['address'] ?? ($user->shop_address ?? ''),
            'addresses'     => $addrs,
            'area'          => '',
            'pincode'       => $user->pincode ?? '',
            'city'          => $user->city ?? '',
            'state'         => $user->state ?? '',
            'gstNumber'     => $user->gst_no ?? '',
            'latitude'      => $primary['latitude']  ?? null,
            'longitude'     => $primary['longitude'] ?? null,
            // A real `user` account has no separate stage field — it's always
            // a converted customer, matching TelecallerController::worklist()'s
            // hardcoded 'customer' stage for the same table.
            'customerStage' => 'customer',
        ];
    }

    private function dayFiringQuery(\Illuminate\Database\Eloquent\Builder $q, Carbon $date): void
    {
        $dayName    = $date->shortDayName; // 'Mon', 'Tue', ...
        $dayOfMonth = $date->day;

        $q->where(function ($sub) use ($dayName, $dayOfMonth, $date) {
            // Weekly: today's short day name is in days JSON array, and alternate week logic (if set)
            $sub->where(function ($w) use ($dayName, $date) {
                $w->where('frequency', 'weekly')
                  ->whereJsonContains('days', $dayName)
                  ->where(function ($alt) use ($date) {
                      $alt->whereNull('week_anchor_date')
                          ->orWhereRaw(
                              'MOD(DATEDIFF(?, week_anchor_date), 14) < 7',
                              [$date->toDateString()]
                          );
                  });
            })
            // Monthly: month_date matches today's day-of-month
            ->orWhere(function ($m) use ($dayOfMonth) {
                $m->where('frequency', 'monthly')
                  ->where('month_date', $dayOfMonth);
            })
            // Specific Dates: today's date is in specific_dates JSON array
            ->orWhere(function ($s) use ($date) {
                $s->where('frequency', 'specific_dates')
                  ->whereJsonContains('specific_dates', $date->format('Y-m-d'));
            })
            // Appointment: appointment_date matches today's date
            ->orWhere(function ($a) use ($date) {
                $a->where('frequency', 'appointment')
                  ->whereDate('appointment_date', $date->toDateString());
            })
            // N Days: (today - start_date) days % interval_days === 0
            ->orWhere(function ($n) use ($date) {
                $n->where('frequency', 'n_days')
                  ->whereNotNull('start_date')
                  ->whereNotNull('interval_days')
                  ->whereRaw('interval_days > 0')
                  ->whereRaw('DATEDIFF(?, start_date) >= 0', [$date->toDateString()])
                  ->whereRaw('MOD(DATEDIFF(?, start_date), interval_days) = 0', [$date->toDateString()]);
            });
        });
    }

    // ── 1. Bulk assign ────────────────────────────────────────────────────────

    public function assign(): JsonResponse
    {
        try {
            $data = request()->validate([
                'account_ids'   => 'required|array|min:1',
                'account_ids.*' => 'required|string',
                'account_types' => 'required|array',
                'account_types.*' => 'required|string|in:lead,customer',
                'frequency'     => 'required|in:weekly,monthly,n_days,specific_dates,appointment',
                'days'          => 'required_if:frequency,weekly|nullable|array',
                'days.*'        => 'string|in:Mon,Tue,Wed,Thu,Fri,Sat,Sun',
                'month_date'    => 'required_if:frequency,monthly|nullable|integer|min:1|max:31',
                'specific_dates' => 'required_if:frequency,specific_dates|nullable|array',
                'specific_dates.*' => 'date_format:Y-m-d',
                'appointment_date' => 'required_if:frequency,appointment|nullable|date',
                'week_anchor_date' => 'nullable|date',
                'interval_days' => 'required_if:frequency,n_days|nullable|integer|min:1',
                'start_date'    => 'required_if:frequency,n_days|nullable|date',
                'salesman_id'   => 'nullable|string', // allow optional override for admin
            ]);

            // Use provided salesman_id or fall back to JWT authenticated user
            $salesman = $data['salesman_id'] ?? $this->salesmanId();

            $saved = [];
            foreach ($data['account_ids'] as $i => $accountId) {
                $accountType = $data['account_types'][$i] ?? 'lead';
                $plan = BeatPlan::updateOrCreate(
                    ['account_id' => $accountId, 'salesman_id' => $salesman],
                    [
                        'account_type'  => $accountType,
                        'frequency'     => $data['frequency'],
                        'days'          => $data['days']          ?? null,
                        'month_date'    => $data['month_date']    ?? null,
                        'specific_dates' => $data['specific_dates'] ?? null,
                        'appointment_date' => $data['appointment_date'] ?? null,
                        'week_anchor_date' => $data['week_anchor_date'] ?? null,
                        'interval_days' => $data['interval_days'] ?? null,
                        'start_date'    => $data['start_date']    ?? null,
                        'is_active'     => true,
                    ]
                );
                $saved[] = $plan->id;
            }

            return response()->json([
                'success' => true,
                'message' => count($saved) . ' account(s) assigned to beat plan',
                'ids'     => $saved,
            ]);
        } catch (\Tymon\JWTAuth\Exceptions\JWTException $e) {
            return response()->json([
                'success' => false,
                'error'   => 'Authentication failed: ' . $e->getMessage(),
            ], 401);
        } catch (\Exception $e) {
            \Log::error('Beat plan assign error', ['exception' => $e]);
            return response()->json([
                'success' => false,
                'error'   => $e->getMessage(),
            ], 500);
        }
    }

    // ── 2. Today's beat plan ──────────────────────────────────────────────────

    public function today(): JsonResponse
    {
        try {
            $salesman = $this->salesmanId();
            $today    = Carbon::today(self::TZ);

        $query = BeatPlan::where('salesman_id', $salesman)
            ->where('is_active', true);

        $this->dayFiringQuery($query, $today);

        $plans = $query->get();

        // Separate leads and customers
        $leadIds = $plans->where('account_type', 'lead')->pluck('account_id')->unique()->values()->toArray();
        $customerIds = $plans->where('account_type', 'customer')->pluck('account_id')->unique()->values()->toArray();

        $leads = !empty($leadIds)
            ? LeadsAccount::whereIn('id', $leadIds)->get()->keyBy('id')
            : collect();
        $customers = !empty($customerIds)
            ? \DB::table('user')->whereIn('userid', $customerIds)->get()->keyBy('userid')
            : collect();
        $addressesByUser = $this->addressesByUserIds($customerIds);

        // "Visited today" is now a checked-out action_log row (beat_plan_visit_crm
        // is gone) — keyed by account_id since the row need not carry a plan id.
        $visitedAccountIds = ActionLog::where('employee_mobile', $salesman)
            ->whereNotNull('check_out_at')
            ->whereBetween('check_out_at', [$today->copy()->startOfDay(), $today->copy()->endOfDay()])
            ->pluck('account_id')
            ->flip();

        // Follow-ups due/overdue as of today — surfaced as beat-plan entries.
        $followups = BeatPlanFollowup::where('staff_id', $salesman)
            ->where('done', false)
            ->whereDate('due_date', '<=', $today->toDateString())
            ->get()
            ->keyBy('account_id');

        $data = $plans->map(function (BeatPlan $plan) use ($visitedAccountIds, $followups, $leads, $customers, $addressesByUser) {
            $account = null;
            if ($plan->account_type === 'customer') {
                $user = $customers->get($plan->account_id);
                $account = $user
                    ? $this->customerAccountPayload($user, $addressesByUser->get($plan->account_id, collect()))
                    : null;
            } else {
                $lead = $leads->get($plan->account_id);
                $account = $lead ? [
                    'id'            => $lead->id,
                    'accountCode'   => $lead->accountCode,
                    'businessName'  => $lead->businessName,
                    'personName'    => $lead->personName,
                    'contactNumber' => $lead->contactNumber,
                    'address'       => $lead->address,
                    'area'          => $lead->area,
                    'pincode'       => $lead->pincode,
                    'latitude'      => $lead->latitude,
                    'longitude'     => $lead->longitude,
                    // Same stage source telecaller worklist uses, so the pill
                    // reads the same on both screens for the same lead.
                    'customerStage' => $lead->customerStage,
                ] : null;
            }

            return [
                'beat_plan_id'   => $plan->id,
                'frequency'      => $plan->frequency,
                'days'           => $plan->days,
                'month_date'     => $plan->month_date,
                'specific_dates' => $plan->specific_dates,
                'appointment_date' => $plan->appointment_date,
                'interval_days'  => $plan->interval_days,
                'visited_today'  => $visitedAccountIds->has($plan->account_id),
                'follow_up_due'  => $followups->has($plan->account_id),
                'account_type'   => $plan->account_type,
                'account'        => $account,
            ];
        })->filter(fn($r) => $r['account'] !== null)->values();

        // Follow-up accounts not already on today's plan — append as synthetic
        // "appointment" entries so they still show up on the day's list.
        $plannedIds  = $plans->pluck('account_id')->flip();
        $extraFollow = $followups->reject(fn ($f, $id) => $plannedIds->has($id));
        if ($extraFollow->isNotEmpty()) {
            $fLeadIds = $extraFollow->where('account_type', 'lead')->keys()->all();
            $fCustIds = $extraFollow->where('account_type', 'customer')->keys()->all();
            // account_type can be null on older follow-ups — probe both tables.
            $fUnknown = $extraFollow->whereNull('account_type')->keys()->all();
            $fLeadIds = array_values(array_unique([...$fLeadIds, ...$fUnknown]));
            $fCustIds = array_values(array_unique([...$fCustIds, ...$fUnknown]));

            $fLeads = !empty($fLeadIds) ? LeadsAccount::whereIn('id', $fLeadIds)->get()->keyBy('id') : collect();
            $fCust  = !empty($fCustIds) ? DB::table('user')->whereIn('userid', $fCustIds)->get()->keyBy('userid') : collect();
            $fAddr  = $this->addressesByUserIds($fCustIds);

            foreach ($extraFollow as $accId => $f) {
                $account = null; $type = $f->account_type;
                if ($fCust->has($accId)) {
                    $type = 'customer';
                    $account = $this->customerAccountPayload($fCust->get($accId), $fAddr->get($accId, collect()));
                } elseif ($fLeads->has($accId)) {
                    $type = 'lead';
                    $l = $fLeads->get($accId);
                    $account = [
                        'id' => $l->id, 'accountCode' => $l->accountCode, 'businessName' => $l->businessName,
                        'personName' => $l->personName, 'contactNumber' => $l->contactNumber, 'address' => $l->address,
                        'area' => $l->area, 'pincode' => $l->pincode, 'latitude' => $l->latitude,
                        'longitude' => $l->longitude, 'customerStage' => $l->customerStage,
                    ];
                }
                if (!$account) continue;

                $data->push([
                    'beat_plan_id'     => null,
                    'frequency'        => 'appointment',
                    'days'             => null,
                    'month_date'       => null,
                    'specific_dates'   => null,
                    'appointment_date' => optional($f->due_date)->toDateString(),
                    'interval_days'    => null,
                    'visited_today'    => $visitedAccountIds->has($accId),
                    'follow_up_due'    => true,
                    'account_type'     => $type,
                    'account'          => $account,
                ]);
            }
            $data = $data->values();
        }

            return response()->json([
                'success' => true,
                'date'    => $today->toDateString(),
                'total'   => $data->count(),
                'data'    => $data,
            ]);
        } catch (\Exception $e) {
            \Log::error('Beat plan today error', ['error' => $e->getMessage()]);
            return response()->json([
                'success' => false,
                'error'   => $e->getMessage(),
            ], 500);
        }
    }

    // ── 3. Current-week beat plan ─────────────────────────────────────────────

    public function week(): JsonResponse
    {
        try {
            $salesman  = $this->salesmanId();
            $dateParam = request()->query('date'); // optional, for querying a specific day's accounts

            // If a specific date is requested, return accounts for that day
            if ($dateParam) {
                $date  = Carbon::parse($dateParam, self::TZ);
                $query = BeatPlan::where('salesman_id', $salesman)
                    ->where('is_active', true);
                $this->dayFiringQuery($query, $date);
                $plans = $query->get();

                // Separate leads and customers
                $leadIds = $plans->where('account_type', 'lead')->pluck('account_id')->unique()->values()->toArray();
                $customerIds = $plans->where('account_type', 'customer')->pluck('account_id')->unique()->values()->toArray();

                $leads = !empty($leadIds)
                    ? LeadsAccount::whereIn('id', $leadIds)->get()->keyBy('id')
                    : collect();
                $customers = !empty($customerIds)
                    ? \DB::table('user')->whereIn('userid', $customerIds)->get()->keyBy('userid')
                    : collect();
                $addressesByUser = $this->addressesByUserIds($customerIds);

                $visitedIds = ActionLog::where('employee_mobile', $salesman)
                    ->whereNotNull('check_out_at')
                    ->whereBetween('check_out_at', [$date->copy()->startOfDay(), $date->copy()->endOfDay()])
                    ->pluck('account_id')
                    ->flip();

                $data = $plans->map(function (BeatPlan $plan) use ($visitedIds, $leads, $customers, $addressesByUser) {
                    $account = null;
                    if ($plan->account_type === 'customer') {
                        $user = $customers->get($plan->account_id);
                        $account = $user
                            ? $this->customerAccountPayload($user, $addressesByUser->get($plan->account_id, collect()))
                            : null;
                    } else {
                        $lead = $leads->get($plan->account_id);
                        $account = $lead ? [
                            'id'            => $lead->id,
                            'accountCode'   => $lead->accountCode,
                            'businessName'  => $lead->businessName,
                            'personName'    => $lead->personName,
                            'contactNumber' => $lead->contactNumber,
                            'address'       => $lead->address,
                            'area'          => $lead->area,
                            'pincode'       => $lead->pincode,
                        ] : null;
                    }

                    return [
                        'beat_plan_id'   => $plan->id,
                        'visited_today'  => $visitedIds->has($plan->account_id),
                        'frequency'      => $plan->frequency,
                        'days'           => $plan->days,
                        'month_date'     => $plan->month_date,
                        'interval_days'  => $plan->interval_days,
                        'account_type'   => $plan->account_type,
                        'account'        => $account,
                    ];
                })->filter(fn($r) => $r['account'] !== null)->values();

                return response()->json([
                    'success' => true,
                    'date'    => $date->toDateString(),
                    'data'    => $data,
                ]);
            }

            // Return full-week summary (Mon–Sun). Optional ?week_of=YYYY-MM-DD
            // picks any week (past or future); defaults to current week.
            $weekOf = request()->query('week_of');
            $monday = $weekOf
                ? Carbon::parse($weekOf, self::TZ)->startOfWeek(Carbon::MONDAY)
                : Carbon::now(self::TZ)->startOfWeek(Carbon::MONDAY);

            $allPlans = BeatPlan::where('salesman_id', $salesman)
                ->where('is_active', true)
                ->get();

            $days       = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
            $weekSummary = [];
            $totalPlanned = 0;

            foreach ($days as $i => $dayName) {
                $date  = $monday->copy()->addDays($i);
                $count = $allPlans->filter(fn(BeatPlan $p) => $p->firesOn($date))->count();
                $totalPlanned += $count;
                $weekSummary[$dayName] = [
                    'date'  => $date->toDateString(),
                    'count' => $count,
                ];
            }

            // Visits logged this week (distinct accounts checked out)
            $weekStart = $monday->toDateString();
            $weekEnd   = $monday->copy()->addDays(6)->toDateString();
            $visited   = ActionLog::where('employee_mobile', $salesman)
                ->whereNotNull('check_out_at')
                ->whereBetween('check_out_at', [
                    Carbon::parse($weekStart, self::TZ)->startOfDay(),
                    Carbon::parse($weekEnd, self::TZ)->endOfDay(),
                ])
                ->distinct('account_id')
                ->count('account_id');

            return response()->json([
                'success'      => true,
                'week_start'   => $weekStart,
                'week_end'     => $weekEnd,
                'total'        => $allPlans->count(),
                'planned'      => $totalPlanned,
                'visited'      => $visited,
                'remaining'    => max(0, $totalPlanned - $visited),
                'days'         => $weekSummary,
            ]);
        } catch (\Tymon\JWTAuth\Exceptions\JWTException $e) {
            return response()->json([
                'success' => false,
                'error'   => 'Authentication failed: ' . $e->getMessage(),
            ], 401);
        } catch (\Exception $e) {
            \Log::error('Beat plan week error', ['error' => $e->getMessage()]);
            return response()->json([
                'success' => false,
                'error'   => $e->getMessage(),
            ], 500);
        }
    }

    // ── 4. Per-pincode stats for Allotted Customer screen ────────────────────

    public function accountStats(): JsonResponse
    {
        try {
            $salesman = $this->salesmanId();

            $areaIds = array_filter(array_map('intval', (array) request()->query('area_ids', [])));
            $pincodes = array_filter((array) request()->query('pincodes', []));

            if (empty($areaIds) && empty($pincodes)) {
                return response()->json(['success' => false, 'message' => 'area_ids or pincodes required'], 422);
            }

            // Fetch all matching accounts
            $accountQuery = LeadsAccount::select('id', 'pincode');
            if (!empty($areaIds) && !empty($pincodes)) {
                $accountQuery->where(fn($q) =>
                    $q->whereIn('areaId', $areaIds)->orWhereIn('pincode', $pincodes)
                );
            } elseif (!empty($areaIds)) {
                $accountQuery->whereIn('areaId', $areaIds);
            } else {
                $accountQuery->whereIn('pincode', $pincodes);
            }
            $accounts = $accountQuery->get();

            // Account IDs that already have an active beat plan for this salesman
            $assignedIds = BeatPlan::where('salesman_id', $salesman)
                ->where('is_active', true)
                ->whereIn('account_id', $accounts->pluck('id'))
                ->pluck('account_id')
                ->flip();

            // Group by pincode
            $grouped = [];
            foreach ($accounts as $acc) {
                $pin = ($acc->pincode ?? 'Unknown');
                if (!isset($grouped[$pin])) {
                    $grouped[$pin] = ['existing' => 0, 'assign' => 0, 'remaining' => 0];
                }
                $grouped[$pin]['existing']++;
                if ($assignedIds->has($acc->id)) {
                    $grouped[$pin]['assign']++;
                }
            }
            foreach ($grouped as $pin => &$stats) {
                $stats['remaining'] = max(0, $stats['existing'] - $stats['assign']);
            }

            return response()->json([
                'success' => true,
                'data'    => $grouped,
            ]);
        } catch (\Tymon\JWTAuth\Exceptions\JWTException $e) {
            return response()->json([
                'success' => false,
                'error'   => 'Authentication failed: ' . $e->getMessage(),
            ], 401);
        } catch (\Exception $e) {
            \Log::error('Beat plan account stats error', ['error' => $e->getMessage()]);
            return response()->json([
                'success' => false,
                'error'   => $e->getMessage(),
            ], 500);
        }
    }

    // ── 5. Unassign (soft delete) ─────────────────────────────────────────────

    // ── 5b. All active plans for this salesman (for card chips + day counts) ──

    public function myPlans(): JsonResponse
    {
        try {
            $salesman = $this->salesmanId();
            $plans = BeatPlan::where('salesman_id', $salesman)
                ->where('is_active', true)
                ->get(['id', 'account_id', 'frequency', 'days', 'month_date', 'specific_dates', 'appointment_date', 'week_anchor_date', 'interval_days', 'start_date']);

            return response()->json(['success' => true, 'data' => $plans]);
        } catch (\Tymon\JWTAuth\Exceptions\JWTException $e) {
            return response()->json([
                'success' => false,
                'error'   => 'Authentication failed: ' . $e->getMessage(),
            ], 401);
        } catch (\Exception $e) {
            \Log::error('Beat plan myPlans error', ['error' => $e->getMessage()]);
            return response()->json([
                'success' => false,
                'error'   => $e->getMessage(),
            ], 500);
        }
    }

    // ── 5c. Unassign (soft delete) ─────────────────────────────────────────────

    public function unassign(int $id): JsonResponse
    {
        try {
            $salesman = $this->salesmanId();
            $plan = BeatPlan::where('id', $id)
                ->where('salesman_id', $salesman)
                ->firstOrFail();
            $plan->update(['is_active' => false]);

            return response()->json(['success' => true, 'message' => 'Beat plan removed']);
        } catch (\Tymon\JWTAuth\Exceptions\JWTException $e) {
            return response()->json([
                'success' => false,
                'error'   => 'Authentication failed: ' . $e->getMessage(),
            ], 401);
        } catch (\Exception $e) {
            \Log::error('Beat plan unassign error', ['error' => $e->getMessage()]);
            return response()->json([
                'success' => false,
                'error'   => $e->getMessage(),
            ], 500);
        }
    }

    // ── 6. Unassign by account IDs (bulk) ────────────────────────────────────

    public function unassignBulk(): JsonResponse
    {
        try {
            $salesman = $this->salesmanId();
            $data = request()->validate([
                'account_ids'   => 'required|array|min:1',
                'account_ids.*' => 'required|string',
            ]);

            $count = BeatPlan::where('salesman_id', $salesman)
                ->whereIn('account_id', $data['account_ids'])
                ->update(['is_active' => false]);

            return response()->json(['success' => true, 'message' => "$count beat plan(s) removed"]);
        } catch (\Tymon\JWTAuth\Exceptions\JWTException $e) {
            return response()->json([
                'success' => false,
                'error'   => 'Authentication failed: ' . $e->getMessage(),
            ], 401);
        } catch (\Exception $e) {
            \Log::error('Beat plan unassignBulk error', ['error' => $e->getMessage()]);
            return response()->json([
                'success' => false,
                'error'   => $e->getMessage(),
            ], 500);
        }
    }

    // ── 7. Follow-ups (both roles) ────────────────────────────────────────────
    // A visit/call check-out can schedule a follow-up; it lands in
    // beat_plan_followup_crm and surfaces here + on today()/week() + the
    // telecaller Callbacks screen.

    public function followups(): JsonResponse
    {
        try {
            $staff    = $this->salesmanId();
            $todayStr = Carbon::today(self::TZ)->toDateString();

            $rows = BeatPlanFollowup::where('staff_id', $staff)
                ->where('done', false)
                ->orderBy('due_date')
                ->get();

            $leadIds = $rows->where('account_type', 'lead')->pluck('account_id')->all();
            $custIds = $rows->where('account_type', 'customer')->pluck('account_id')->all();
            $unknown = $rows->whereNull('account_type')->pluck('account_id')->all();
            $leadIds = array_values(array_unique([...$leadIds, ...$unknown]));
            $custIds = array_values(array_unique([...$custIds, ...$unknown]));

            $leads = !empty($leadIds)
                ? LeadsAccount::whereIn('id', $leadIds)->get(['id', 'businessName', 'personName', 'contactNumber', 'area', 'pincode', 'customerStage'])->keyBy('id')
                : collect();
            $cust  = !empty($custIds)
                ? DB::table('user')->whereIn('userid', $custIds)->get(['userid', 'name', 'shop_name', 'contactno', 'city', 'pincode'])->keyBy('userid')
                : collect();

            $data = $rows->map(function (BeatPlanFollowup $f) use ($leads, $cust, $todayStr) {
                $due = optional($f->due_date)->toDateString();
                $acc = $cust->get($f->account_id);
                $type = $f->account_type;
                if ($acc) {
                    $type = 'customer';
                    $name = $acc->shop_name ?: $acc->name;
                    $phone = $acc->contactno; $area = $acc->city; $pincode = $acc->pincode; $stage = 'customer';
                } else {
                    $l = $leads->get($f->account_id);
                    $type = $l ? 'lead' : $type;
                    $name = $l ? ($l->businessName ?: $l->personName) : 'Unknown';
                    $phone = $l->contactNumber ?? ''; $area = $l->area ?? ''; $pincode = $l->pincode ?? ''; $stage = $l->customerStage ?? 'lead';
                }

                return [
                    'id'             => $f->id,
                    'account_id'     => $f->account_id,
                    'account_type'   => $type,
                    'name'           => $name,
                    'phone'          => $phone,
                    'area'           => $area,
                    'pincode'        => $pincode,
                    'stage'          => $stage,
                    'note'           => $f->note,
                    'follow_up_date' => $due,
                    'overdue'        => $due !== null && $due < $todayStr,
                ];
            })->values();

            return response()->json(['success' => true, 'data' => $data]);
        } catch (\Exception $e) {
            \Log::error('Beat plan followups error', ['error' => $e->getMessage()]);
            return response()->json(['success' => false, 'error' => $e->getMessage()], 500);
        }
    }

    public function markFollowupDone(int $id): JsonResponse
    {
        try {
            $staff = $this->salesmanId();
            $f = BeatPlanFollowup::where('id', $id)->where('staff_id', $staff)->firstOrFail();
            $f->update(['done' => true, 'done_at' => now()]);

            return response()->json(['success' => true, 'data' => $f]);
        } catch (\Exception $e) {
            \Log::error('Beat plan markFollowupDone error', ['error' => $e->getMessage()]);
            return response()->json(['success' => false, 'error' => $e->getMessage()], 500);
        }
    }

    public function createFollowup(): JsonResponse
    {
        try {
            $staff = $this->salesmanId();
            $data = request()->validate([
                'account_id'   => 'required|string|max:191',
                'account_type' => 'nullable|in:lead,customer',
                'due_date'     => 'required|date',
                'note'         => 'nullable|string|max:255',
            ]);

            BeatPlanFollowup::where('staff_id', $staff)
                ->where('account_id', $data['account_id'])
                ->where('done', false)
                ->update(['done' => true, 'done_at' => now()]);

            $f = BeatPlanFollowup::create([
                'account_id'   => $data['account_id'],
                'account_type' => $data['account_type'] ?? null,
                'staff_id'     => $staff,
                'due_date'     => Carbon::parse($data['due_date'])->toDateString(),
                'note'         => $data['note'] ?? null,
            ]);

            return response()->json(['success' => true, 'data' => $f], 201);
        } catch (\Exception $e) {
            \Log::error('Beat plan createFollowup error', ['error' => $e->getMessage()]);
            return response()->json(['success' => false, 'error' => $e->getMessage()], 500);
        }
    }

    public function rescheduleFollowup(int $id): JsonResponse
    {
        try {
            $staff = $this->salesmanId();
            $data = request()->validate(['due_date' => 'required|date']);
            $f = BeatPlanFollowup::where('id', $id)->where('staff_id', $staff)->firstOrFail();
            $f->update([
                'due_date' => Carbon::parse($data['due_date'])->toDateString(),
                'done'     => false,
                'done_at'  => null,
            ]);

            return response()->json(['success' => true, 'data' => $f]);
        } catch (\Exception $e) {
            \Log::error('Beat plan rescheduleFollowup error', ['error' => $e->getMessage()]);
            return response()->json(['success' => false, 'error' => $e->getMessage()], 500);
        }
    }
}

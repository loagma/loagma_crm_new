<?php

namespace App\Http\Controllers;

use App\Models\BeatPlan;
use App\Models\BeatPlanVisit;
use App\Models\LeadsAccount;
use Carbon\Carbon;
use Illuminate\Http\JsonResponse;
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

        // Build response with visit status for today
        $visitedIds = BeatPlanVisit::where('salesman_id', $salesman)
            ->where('visit_date', $today->toDateString())
            ->pluck('beat_plan_id')
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
                    'latitude'      => $lead->latitude,
                    'longitude'     => $lead->longitude,
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
                'visited_today'  => $visitedIds->has($plan->id),
                'account_type'   => $plan->account_type,
                'account'        => $account,
            ];
        })->filter(fn($r) => $r['account'] !== null)->values();

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

                $visitedIds = BeatPlanVisit::where('salesman_id', $salesman)
                    ->where('visit_date', $date->toDateString())
                    ->pluck('beat_plan_id')
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
                        'visited_today'  => $visitedIds->has($plan->id),
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

            // Visits logged this week
            $weekStart = $monday->toDateString();
            $weekEnd   = $monday->copy()->addDays(6)->toDateString();
            $visited   = BeatPlanVisit::where('salesman_id', $salesman)
                ->whereBetween('visit_date', [$weekStart, $weekEnd])
                ->count();

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

    // ── 7. Record a visit ─────────────────────────────────────────────────────

    public function recordVisit(int $id): JsonResponse
    {
        try {
            $salesman = $this->salesmanId();
            $plan = BeatPlan::where('id', $id)
                ->where('salesman_id', $salesman)
                ->firstOrFail();

            $data = request()->validate([
                'notes'  => 'nullable|string|max:1000',
                'status' => 'nullable|in:visited,missed,skipped',
            ]);

            $visit = BeatPlanVisit::updateOrCreate(
                ['beat_plan_id' => $plan->id, 'visit_date' => Carbon::today(self::TZ)->toDateString()],
                [
                    'account_id'  => $plan->account_id,
                    'salesman_id' => $salesman,
                    'status'      => $data['status'] ?? 'visited',
                    'notes'       => $data['notes']  ?? null,
                ]
            );

            return response()->json(['success' => true, 'data' => $visit]);
        } catch (\Tymon\JWTAuth\Exceptions\JWTException $e) {
            return response()->json([
                'success' => false,
                'error'   => 'Authentication failed: ' . $e->getMessage(),
            ], 401);
        } catch (\Exception $e) {
            \Log::error('Beat plan recordVisit error', ['error' => $e->getMessage()]);
            return response()->json([
                'success' => false,
                'error'   => $e->getMessage(),
            ], 500);
        }
    }
}

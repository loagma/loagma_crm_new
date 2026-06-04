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

    private function dayFiringQuery(\Illuminate\Database\Eloquent\Builder $q, Carbon $date): void
    {
        $dayName    = $date->shortDayName; // 'Mon', 'Tue', ...
        $dayOfMonth = $date->day;

        $q->where(function ($sub) use ($dayName, $dayOfMonth, $date) {
            // Weekly: today's short day name is in days JSON array
            $sub->where(function ($w) use ($dayName) {
                $w->where('frequency', 'weekly')
                  ->whereJsonContains('days', $dayName);
            })
            // Monthly: month_date matches today's day-of-month
            ->orWhere(function ($m) use ($dayOfMonth) {
                $m->where('frequency', 'monthly')
                  ->where('month_date', $dayOfMonth);
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
        $salesman = $this->salesmanId();

        $data = request()->validate([
            'account_ids'   => 'required|array|min:1',
            'account_ids.*' => 'required|string',
            'frequency'     => 'required|in:weekly,monthly,n_days',
            'days'          => 'required_if:frequency,weekly|nullable|array',
            'days.*'        => 'string|in:Mon,Tue,Wed,Thu,Fri,Sat,Sun',
            'month_date'    => 'required_if:frequency,monthly|nullable|integer|min:1|max:31',
            'interval_days' => 'required_if:frequency,n_days|nullable|integer|min:1',
            'start_date'    => 'required_if:frequency,n_days|nullable|date',
        ]);

        $saved = [];
        foreach ($data['account_ids'] as $accountId) {
            $plan = BeatPlan::updateOrCreate(
                ['account_id' => $accountId, 'salesman_id' => $salesman],
                [
                    'frequency'     => $data['frequency'],
                    'days'          => $data['days']          ?? null,
                    'month_date'    => $data['month_date']    ?? null,
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
    }

    // ── 2. Today's beat plan ──────────────────────────────────────────────────

    public function today(): JsonResponse
    {
        $salesman = $this->salesmanId();
        $today    = Carbon::today(self::TZ);

        $query = BeatPlan::with('account')
            ->where('salesman_id', $salesman)
            ->where('is_active', true);

        $this->dayFiringQuery($query, $today);

        $plans = $query->get();

        // Build response with visit status for today
        $visitedIds = BeatPlanVisit::where('salesman_id', $salesman)
            ->where('visit_date', $today->toDateString())
            ->pluck('beat_plan_id')
            ->flip();

        $data = $plans->map(function (BeatPlan $plan) use ($visitedIds) {
            $account = $plan->account;
            return [
                'beat_plan_id'  => $plan->id,
                'frequency'     => $plan->frequency,
                'days'          => $plan->days,
                'month_date'    => $plan->month_date,
                'interval_days' => $plan->interval_days,
                'visited_today' => $visitedIds->has($plan->id),
                'account' => $account ? [
                    'id'            => $account->id,
                    'accountCode'   => $account->accountCode,
                    'businessName'  => $account->businessName,
                    'personName'    => $account->personName,
                    'contactNumber' => $account->contactNumber,
                    'address'       => $account->address,
                    'area'          => $account->area,
                    'pincode'       => $account->pincode,
                    'latitude'      => $account->latitude,
                    'longitude'     => $account->longitude,
                ] : null,
            ];
        })->filter(fn($r) => $r['account'] !== null)->values();

        return response()->json([
            'success' => true,
            'date'    => $today->toDateString(),
            'total'   => $data->count(),
            'data'    => $data,
        ]);
    }

    // ── 3. Current-week beat plan ─────────────────────────────────────────────

    public function week(): JsonResponse
    {
        $salesman  = $this->salesmanId();
        $dateParam = request()->query('date'); // optional, for querying a specific day's accounts

        // If a specific date is requested, return accounts for that day
        if ($dateParam) {
            $date  = Carbon::parse($dateParam, self::TZ);
            $query = BeatPlan::with('account')
                ->where('salesman_id', $salesman)
                ->where('is_active', true);
            $this->dayFiringQuery($query, $date);
            $plans = $query->get();

            $visitedIds = BeatPlanVisit::where('salesman_id', $salesman)
                ->where('visit_date', $date->toDateString())
                ->pluck('beat_plan_id')
                ->flip();

            $data = $plans->map(function (BeatPlan $plan) use ($visitedIds) {
                $account = $plan->account;
                return [
                    'beat_plan_id'  => $plan->id,
                    'visited_today' => $visitedIds->has($plan->id),
                    'frequency'     => $plan->frequency,
                    'days'          => $plan->days,
                    'month_date'    => $plan->month_date,
                    'interval_days' => $plan->interval_days,
                    'account' => $account ? [
                        'id'            => $account->id,
                        'accountCode'   => $account->accountCode,
                        'businessName'  => $account->businessName,
                        'personName'    => $account->personName,
                        'contactNumber' => $account->contactNumber,
                        'address'       => $account->address,
                        'area'          => $account->area,
                        'pincode'       => $account->pincode,
                    ] : null,
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
    }

    // ── 4. Per-pincode stats for Allotted Customer screen ────────────────────

    public function accountStats(): JsonResponse
    {
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
    }

    // ── 5. Unassign (soft delete) ─────────────────────────────────────────────

    // ── 5b. All active plans for this salesman (for card chips + day counts) ──

    public function myPlans(): JsonResponse
    {
        $salesman = $this->salesmanId();
        $plans = BeatPlan::where('salesman_id', $salesman)
            ->where('is_active', true)
            ->get(['id', 'account_id', 'frequency', 'days', 'month_date', 'interval_days', 'start_date']);

        return response()->json(['success' => true, 'data' => $plans]);
    }

    // ── 5c. Unassign (soft delete) ─────────────────────────────────────────────

    public function unassign(int $id): JsonResponse
    {
        $salesman = $this->salesmanId();
        $plan = BeatPlan::where('id', $id)
            ->where('salesman_id', $salesman)
            ->firstOrFail();
        $plan->update(['is_active' => false]);

        return response()->json(['success' => true, 'message' => 'Beat plan removed']);
    }

    // ── 6. Unassign by account IDs (bulk) ────────────────────────────────────

    public function unassignBulk(): JsonResponse
    {
        $salesman = $this->salesmanId();
        $data = request()->validate([
            'account_ids'   => 'required|array|min:1',
            'account_ids.*' => 'required|string',
        ]);

        $count = BeatPlan::where('salesman_id', $salesman)
            ->whereIn('account_id', $data['account_ids'])
            ->update(['is_active' => false]);

        return response()->json(['success' => true, 'message' => "$count beat plan(s) removed"]);
    }

    // ── 7. Record a visit ─────────────────────────────────────────────────────

    public function recordVisit(int $id): JsonResponse
    {
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
    }
}

<?php

namespace App\Http\Controllers;

use App\Models\PincodeGeo;
use App\Models\TcAllocationItem;
use App\Services\TelecallerAllocationService;
use App\Support\DailyAllocator;
use Illuminate\Http\JsonResponse;
use Illuminate\Support\Carbon;
use Illuminate\Validation\ValidationException;
use Tymon\JWTAuth\Facades\JWTAuth;

/**
 * Telecaller daily allocation: the telecaller selects pincodes (or all of
 * them) and a From–To date range; the backend orders the pincodes by real
 * geography and divides the customers over the days, re-dividing what's left
 * every morning so unfinished work carries forward and the plan ends on time.
 * See TelecallerAllocationService for the rules.
 */
class TelecallerAllocationController extends Controller
{
    public function __construct(private TelecallerAllocationService $allocation)
    {
    }

    private function mobile(): string
    {
        return (string) JWTAuth::parseToken()->authenticate()->mobile;
    }

    // ── POST /telecaller/allocation — create plan or merge into the active one ──
    public function store(): JsonResponse
    {
        $mobile = $this->mobile();

        // From–To range (calendar days, inclusive); customers are divided over
        // it. On a merge into the active plan its start_date is kept, so only
        // end_date matters (it may be moved later, not before today).
        $today = Carbon::today()->toDateString();
        $active = $this->allocation->activePlan($mobile);
        $data = validator(request()->only(['pincodes', 'start_date', 'end_date']), [
            'pincodes'   => 'required|array|min:1',
            'pincodes.*' => 'required|string|max:10',
            'start_date' => $active ? 'nullable|date_format:Y-m-d' : "required|date_format:Y-m-d|after_or_equal:$today",
            'end_date'   => 'required|date_format:Y-m-d|after_or_equal:' . ($active ? $today : 'start_date'),
        ])->validate();

        $start = $active ? $active->start_date->toDateString() : $data['start_date'];
        $maxDays = (int) config('telecaller.allocation_max_days', 366);
        if ($data['end_date'] < $start || DailyAllocator::daysInclusive($start, $data['end_date']) > $maxDays) {
            throw ValidationException::withMessages(['end_date' => "The To date must be on or after the From date and within $maxDays days."]);
        }

        $plan = $this->allocation->createOrMerge($mobile, $data['pincodes'], $start, $data['end_date']);

        return response()->json([
            'success' => true,
            'data'    => $this->allocation->progress($mobile) ?? ['plan_id' => $plan->id],
        ], 201);
    }

    // ── GET /telecaller/allocation — active plan progress ───────────────────────
    public function show(): JsonResponse
    {
        return response()->json(['success' => true, 'data' => $this->allocation->progress($this->mobile())]);
    }

    // ── GET /telecaller/allocation/today — today's list (allocates lazily) ──────
    public function today(): JsonResponse
    {
        [$plan, $items] = $this->allocation->today($this->mobile());

        return response()->json([
            'success' => true,
            'data'    => [
                'plan_id'        => $plan?->id,
                'plan_status'    => $plan?->status,
                'daily_capacity' => $plan?->daily_capacity,
                'start_date'     => $plan?->start_date?->toDateString(),
                'end_date'       => $plan?->end_date?->toDateString(),
                'total'          => count($items),
                'customers'      => $items,
            ],
        ]);
    }

    // ── POST /telecaller/allocation/reassign — set a date for chosen accounts ───
    // For missed accounts (date passed, not called), unscheduled ones (added
    // after the plan was made) or moving any not-yet-called account.
    public function reassign(): JsonResponse
    {
        $mobile = $this->mobile();
        $today = Carbon::today()->toDateString();

        $data = validator(request()->only(['account_ids', 'date']), [
            'account_ids'   => 'required|array|min:1',
            'account_ids.*' => 'required|string|max:64',
            'date'          => "required|date_format:Y-m-d|after_or_equal:$today",
        ])->validate();

        $updated = $this->allocation->reassign($mobile, $data['account_ids'], $data['date']);

        return response()->json([
            'success' => $updated > 0,
            'message' => $updated > 0 ? "$updated customer(s) set to {$data['date']}" : 'None of these customers can be rescheduled',
            'updated' => $updated,
            'data'    => $this->allocation->progress($mobile),
        ], $updated > 0 ? 200 : 422);
    }

    // ── POST /telecaller/allocation/distribute — auto-distribute over weekdays ──
    // Selected accounts (in the order sent) are spread in even consecutive
    // blocks over the chosen weekdays between start_date and end_date.
    public function distribute(): JsonResponse
    {
        $mobile = $this->mobile();
        $today = Carbon::today()->toDateString();

        $maxDays = (int) config('telecaller.allocation_max_days', 366);
        // Either a To date (From–To range) or `days` ("N days" mode: the first
        // N dates on the chosen weekdays counted from start_date).
        $data = validator(request()->only(['account_ids', 'start_date', 'end_date', 'days', 'weekdays']), [
            'account_ids'   => 'required|array|min:1',
            'account_ids.*' => 'required|string|max:64',
            'start_date'    => "required|date_format:Y-m-d|after_or_equal:$today",
            'end_date'      => 'required_without:days|nullable|date_format:Y-m-d|after_or_equal:start_date',
            'days'          => "required_without:end_date|nullable|integer|min:1|max:$maxDays",
            'weekdays'      => 'nullable|array',
            'weekdays.*'    => 'string|in:' . implode(',', DailyAllocator::WEEKDAYS),
        ])->validate();

        $days = isset($data['days']) ? (int) $data['days'] : null;
        if ($days === null && DailyAllocator::daysInclusive($data['start_date'], $data['end_date']) > $maxDays) {
            throw ValidationException::withMessages(['end_date' => "The date range can be at most $maxDays days."]);
        }

        $dates = DailyAllocator::resolveDates($data['start_date'], $data['end_date'] ?? null, $days, $data['weekdays'] ?? []);
        $result = $this->allocation->distribute($mobile, $data['account_ids'], $dates);
        if ($result === null) {
            return response()->json(['success' => false, 'message' => 'No active daily plan'], 404);
        }

        $ok = $result['updated'] > 0;
        $parts = ["{$result['updated']} customer(s) distributed over " . count($result['dates']) . ' day(s)'];
        if ($result['skipped_done'] > 0) $parts[] = "{$result['skipped_done']} already called";
        if ($result['not_in_plan'] > 0) $parts[] = "{$result['not_in_plan']} not in your daily plan";

        return response()->json([
            'success'      => $ok,
            'message'      => $ok ? implode(' · ', $parts) : 'None of these customers can be distributed (' . implode(' · ', array_slice($parts, 1)) . ')',
            'updated'      => $result['updated'],
            'skipped_done' => $result['skipped_done'],
            'not_in_plan'  => $result['not_in_plan'],
            'dates'        => $result['dates'],
            'data'         => $this->allocation->progress($mobile),
        ], $ok ? 200 : 422);
    }

    // ── PATCH /telecaller/allocation/items/{id} — manual skip / in progress ─────
    public function updateItem(string $id): JsonResponse
    {
        $mobile = $this->mobile();

        $data = validator(request()->only(['status']), [
            'status' => 'required|in:assigned,in_progress,skipped',
        ])->validate();

        $item = TcAllocationItem::where('id', $id)->where('employee_mobile', $mobile)->first();
        if (!$item) {
            return response()->json(['success' => false, 'message' => 'Not found'], 404);
        }
        // Only today's open items can be changed by hand; finished calls are
        // driven by the call log.
        if (!in_array($item->status, ['assigned', 'in_progress', 'skipped'], true)) {
            return response()->json(['success' => false, 'message' => 'This customer is already ' . $item->status], 422);
        }

        $item->status = $data['status'];
        $item->completed_at = $data['status'] === 'skipped' ? now() : null;
        $item->save();

        return response()->json(['success' => true, 'data' => $item]);
    }

    // ── DELETE /telecaller/allocation — cancel the active plan ──────────────────
    public function destroy(): JsonResponse
    {
        $cancelled = $this->allocation->cancel($this->mobile());

        return response()->json(['success' => $cancelled, 'message' => $cancelled ? 'Plan cancelled' : 'No active plan'], $cancelled ? 200 : 404);
    }

    // ── Admin: pincode coordinates ───────────────────────────────────────────────

    // GET /pincode-geo?pincodes[]=… — stored points (geocoded + manual).
    public function geoIndex(): JsonResponse
    {
        $q = PincodeGeo::query()->orderBy('pincode');
        if (request()->filled('pincodes')) {
            $q->whereIn('pincode', (array) request('pincodes'));
        }
        return response()->json(['success' => true, 'data' => $q->get()]);
    }

    // PUT /pincode-geo/{pincode} — manual override; never replaced by the geocoder.
    // Send {"source":"geocoded"} to drop the override and look the pincode up again.
    public function geoUpdate(string $pincode): JsonResponse
    {
        $data = validator(request()->only(['lat', 'lng', 'source']), [
            'source' => 'nullable|in:manual,geocoded',
            'lat'    => 'required_unless:source,geocoded|numeric|between:6,38',
            'lng'    => 'required_unless:source,geocoded|numeric|between:68,98',
        ])->validate();

        if (($data['source'] ?? 'manual') === 'geocoded') {
            PincodeGeo::where('pincode', $pincode)->delete();
            $this->allocation->ensurePincodeGeo([$pincode]);
            return response()->json(['success' => true, 'data' => PincodeGeo::find($pincode)]);
        }

        $geo = PincodeGeo::updateOrCreate(
            ['pincode' => $pincode],
            ['lat' => (float) $data['lat'], 'lng' => (float) $data['lng'], 'source' => 'manual'],
        );

        return response()->json(['success' => true, 'data' => $geo]);
    }
}

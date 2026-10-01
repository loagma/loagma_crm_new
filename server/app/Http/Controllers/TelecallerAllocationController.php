<?php

namespace App\Http\Controllers;

use App\Models\PincodeGeo;
use App\Models\TcAllocationItem;
use App\Services\TelecallerAllocationService;
use Illuminate\Http\JsonResponse;
use Tymon\JWTAuth\Facades\JWTAuth;

/**
 * Telecaller daily allocation: the telecaller selects pincodes (or all of
 * them) and a daily capacity; the backend orders them by real geography and
 * hands out a capacity-sized list each day, carrying unfinished pincodes
 * forward. See TelecallerAllocationService for the rules.
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

        $data = validator(request()->only(['pincodes', 'daily_capacity']), [
            'pincodes'       => 'required|array|min:1',
            'pincodes.*'     => 'required|string|max:10',
            'daily_capacity' => 'required|integer|min:1|max:' . config('telecaller.allocation_max_capacity', 500),
        ])->validate();

        $plan = $this->allocation->createOrMerge($mobile, $data['pincodes'], (int) $data['daily_capacity']);

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
                'total'          => count($items),
                'customers'      => $items,
            ],
        ]);
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
            ['lat' => (float) $data['lat'], 'lng' => (float) $data['lng'], 'source' => 'manual', 'sample_count' => 0],
        );

        return response()->json(['success' => true, 'data' => $geo]);
    }
}

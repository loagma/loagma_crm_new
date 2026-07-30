<?php

namespace App\Http\Controllers;

use App\Models\CallLog;
use App\Services\KnowlarityService;
use Illuminate\Http\JsonResponse;
use Tymon\JWTAuth\Facades\JWTAuth;

class KnowlarityCallController extends Controller
{
    public function __construct(protected KnowlarityService $knowlarity) {}

    /**
     * POST /api/telecaller/call
     * Triggered by the "Call" button on a lead/customer's call screen.
     * Bridges the logged-in telecaller's own number with the customer's
     * number via Knowlarity - no in-app dialer/audio involved.
     */
    public function store(): JsonResponse
    {
        $mobile = (string) JWTAuth::parseToken()->authenticate()->mobile;

        $validated = validator(request()->only(['account_id', 'account_type', 'customer_number']), [
            'account_id'      => 'nullable|string|max:191',
            'account_type'    => 'required|in:lead,customer',
            'customer_number' => 'required|string|max:20',
        ])->validate();

        // Pre-create the log row so the call-completed webhook updates this
        // exact row (matched by knowlarity_call_id, or by the row id we pass to
        // Knowlarity as additional_params.uniqueid) instead of guessing the
        // account/agent link from phone numbers alone.
        $log = CallLog::create([
            'employee_mobile' => $mobile,
            'source'          => 'knowlarity',
            'direction'       => 'outbound',
            'account_id'      => $validated['account_id'] ?? null,
            'account_type'    => $validated['account_type'],
            'call_outcome'    => 'pending',
            'called_at'       => now(),
        ]);

        $result = $this->knowlarity->makeCall(
            agentNumber: $mobile,
            customerNumber: $validated['customer_number'],
            uniqueId: (string) $log->id,
        );

        // makecall nests the id as {"success": {"call_id": ...}}; keep flat fallbacks.
        $callId = $result['success']['call_id'] ?? $result['call_id'] ?? $result['id'] ?? null;

        // No call_id means Knowlarity rejected the call outright (bad number,
        // unverified agent, expired SR number, etc.) - there will never be a
        // provider call log entry to reconcile this against later, so resolve
        // it now instead of leaving it stuck on 'pending' forever.
        $log->update([
            'knowlarity_call_id' => $callId,
            'call_outcome'       => $callId ? 'pending' : 'invalid',
            'raw_payload'        => $result,
        ]);

        return response()->json(['success' => true, 'data' => $log, 'knowlarity' => $result]);
    }
}

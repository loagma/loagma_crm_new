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

        $result = $this->knowlarity->makeCall(
            agentNumber: $mobile,
            customerNumber: $validated['customer_number'],
        );

        // Pre-create the log row so the call-completed webhook updates this
        // exact row (matched by knowlarity_call_id) instead of guessing the
        // account/agent link from phone numbers alone.
        $log = CallLog::create([
            'employee_mobile'    => $mobile,
            'source'             => 'knowlarity',
            'direction'          => 'outbound',
            'knowlarity_call_id' => $result['call_id'] ?? $result['id'] ?? null,
            'account_id'         => $validated['account_id'] ?? null,
            'account_type'       => $validated['account_type'],
            'call_outcome'       => 'pending',
            'called_at'          => now(),
            'raw_payload'        => $result,
        ]);

        return response()->json(['success' => true, 'data' => $log, 'knowlarity' => $result]);
    }
}

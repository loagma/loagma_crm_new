<?php

namespace App\Http\Controllers;

use App\Models\CallLog;
use Illuminate\Http\JsonResponse;
use Tymon\JWTAuth\Facades\JWTAuth;

class CallLogController extends Controller
{
    private function authMobile(): string
    {
        return JWTAuth::parseToken()->authenticate()->mobile;
    }

    public function index(): JsonResponse
    {
        $mobile    = $this->authMobile();
        $accountId = request()->query('account_id');

        $query = CallLog::where('employee_mobile', $mobile)
                        ->orderBy('called_at', 'desc');

        if ($accountId) {
            $query->where('account_id', $accountId);
        }

        return response()->json([
            'success' => true,
            'data'    => $query->get(),
        ]);
    }

    public function store(): JsonResponse
    {
        $mobile = $this->authMobile();

        $data = request()->only([
            'account_id', 'account_type', 'call_outcome',
            'notes', 'follow_up_date',
        ]);

        $validated = validator($data, [
            'account_id'    => 'nullable|string|max:191',
            'account_type'  => 'required|in:lead,customer',
            'call_outcome'  => 'required|in:answered,busy,no_answer,switch_off,invalid,callback',
            'notes'         => 'nullable|string',
            'follow_up_date'=> 'nullable|date',
        ])->validate();

        $log = CallLog::create(array_merge($validated, [
            'employee_mobile' => $mobile,
            'called_at'       => now(),
        ]));

        return response()->json(['success' => true, 'data' => $log], 201);
    }

    /**
     * Update a call log owned by the current employee. Used to Reschedule a
     * callback (follow_up_date) or mark it Done (callback_done).
     */
    public function update(string $id): JsonResponse
    {
        $mobile = $this->authMobile();

        $log = CallLog::where('employee_mobile', $mobile)->where('id', $id)->first();
        if (!$log) {
            return response()->json(['success' => false, 'message' => 'Not found'], 404);
        }

        $validated = validator(request()->only(['follow_up_date', 'callback_done']), [
            'follow_up_date' => 'nullable|date',
            'callback_done'  => 'nullable|boolean',
        ])->validate();

        if (array_key_exists('follow_up_date', $validated)) {
            $log->follow_up_date = $validated['follow_up_date'];
        }
        if (array_key_exists('callback_done', $validated)) {
            $log->callback_done = (bool) $validated['callback_done'];
        }
        $log->save();

        return response()->json(['success' => true, 'data' => $log]);
    }
}

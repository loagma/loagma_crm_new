<?php

namespace App\Http\Controllers;

use App\Models\BeatPlanFollowup;
use App\Models\CallLog;
use App\Models\Complaint;
use Illuminate\Http\JsonResponse;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
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
            'notes', 'follow_up_date', 'category', 'description',
        ]);

        $validated = validator($data, [
            // account_id is required when logging a complaint — complaint_crm
            // has no way to represent a ticket with no account attached.
            'account_id'    => 'required_if:call_outcome,complaint|nullable|string|max:191',
            'account_type'  => 'required|in:lead,customer',
            'call_outcome'  => 'required|in:answered,busy,no_answer,switch_off,invalid,callback,pending,complaint',
            'notes'         => 'nullable|string',
            'follow_up_date'=> 'nullable|date',
            // Only required when call_outcome is 'complaint' — this is what
            // creates the linked complaint_crm ticket below.
            'category'      => 'required_if:call_outcome,complaint|string|max:191',
            'description'   => 'required_if:call_outcome,complaint|string',
        ])->validate();

        $category    = $validated['category']    ?? null;
        $description = $validated['description'] ?? null;
        unset($validated['category'], $validated['description']);

        $log = DB::transaction(function () use ($validated, $mobile, $category, $description) {
            $log = CallLog::create(array_merge($validated, [
                'employee_mobile' => $mobile,
                'called_at'       => now(),
            ]));

            if ($validated['call_outcome'] === 'complaint') {
                Complaint::create([
                    'account_id'      => $log->account_id,
                    'account_type'    => $log->account_type,
                    'source_channel'  => 'telecaller_call',
                    'raised_by'       => $mobile,
                    'call_log_id'     => $log->id,
                    'category'        => $category,
                    'description'     => $description,
                ]);
            }

            return $log;
        });

        // Close every open follow-up for this account so notifications clear.
        // The new log itself may open a fresh follow-up if follow_up_date is set.
        if (!empty($validated['account_id'])) {
            CallLog::where('employee_mobile', $mobile)
                ->where('account_id', $validated['account_id'])
                ->whereNotNull('follow_up_date')
                ->where('callback_done', false)
                ->where('id', '!=', $log->id)
                ->update(['callback_done' => true]);

            // beat_plan_followup_crm is the single source the Callbacks screen +
            // both Today lists read — mirror the follow-up into it.
            BeatPlanFollowup::where('staff_id', $mobile)
                ->where('account_id', $validated['account_id'])
                ->where('done', false)
                ->update(['done' => true, 'done_at' => now()]);

            if (!empty($validated['follow_up_date'])) {
                BeatPlanFollowup::create([
                    'account_id'   => $validated['account_id'],
                    'account_type' => $validated['account_type'] ?? null,
                    'staff_id'     => $mobile,
                    'due_date'     => Carbon::parse($validated['follow_up_date'])->toDateString(),
                    'note'         => $validated['notes'] ?? null,
                ]);
            }
        }

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

        // Keep beat_plan_followup_crm in step (Reschedule / Mark done).
        if ($log->account_id) {
            if (!empty($validated['callback_done'])) {
                BeatPlanFollowup::where('staff_id', $mobile)
                    ->where('account_id', $log->account_id)
                    ->where('done', false)
                    ->update(['done' => true, 'done_at' => now()]);
            }
            if (array_key_exists('follow_up_date', $validated) && !empty($validated['follow_up_date'])) {
                BeatPlanFollowup::where('staff_id', $mobile)
                    ->where('account_id', $log->account_id)
                    ->where('done', false)
                    ->update(['done' => true, 'done_at' => now()]);
                BeatPlanFollowup::create([
                    'account_id'   => $log->account_id,
                    'account_type' => $log->account_type,
                    'staff_id'     => $mobile,
                    'due_date'     => Carbon::parse($validated['follow_up_date'])->toDateString(),
                    'note'         => $log->notes,
                ]);
            }
        }

        return response()->json(['success' => true, 'data' => $log]);
    }
}

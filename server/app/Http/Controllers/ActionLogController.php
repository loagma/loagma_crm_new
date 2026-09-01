<?php

namespace App\Http\Controllers;

use App\Models\ActionLog;
use App\Models\ActionLogStage;
use App\Models\BeatPlanFollowup;
use App\Models\CallLog;
use App\Models\Complaint;
use App\Models\DeliStaff;
use App\Models\LeadsAccount;
use Illuminate\Http\JsonResponse;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Tymon\JWTAuth\Facades\JWTAuth;

/**
 * Action Log (was Order Funnel). One shared table for the salesman visit
 * check-out form and the telecaller post-call form — written when the user
 * taps Check Out on the unified worklist-visit screen.
 */
class ActionLogController extends Controller
{
    private function staff(): DeliStaff
    {
        return JWTAuth::parseToken()->authenticate();
    }

    /** salesman | telecaller — telecaller/teleadmin => telecaller, everyone else => salesman. */
    private function roleFor(DeliStaff $staff): string
    {
        $r = strtolower(trim((string) $staff->role));
        return in_array($r, ['telecaller', 'teleadmin'], true) ? 'telecaller' : 'salesman';
    }

    /** Salesman check-out stage options (dynamic source for the Action Log popup). */
    public function stages(): JsonResponse
    {
        $stages = ActionLogStage::where('is_active', true)
            ->orderBy('sort_order')
            ->orderBy('id')
            ->get(['id', 'slug', 'name', 'sort_order']);

        return response()->json(['success' => true, 'data' => $stages]);
    }

    /** Latest saved row for this account + employee (used to prefill). */
    public function latestResponse(): JsonResponse
    {
        $mobile    = (string) $this->staff()->mobile;
        $accountId = request()->query('account_id');

        $row = ActionLog::where('employee_mobile', $mobile)
            ->when($accountId, fn ($q) => $q->where('account_id', $accountId))
            ->orderByDesc('created_at')
            ->first();

        return response()->json(['success' => true, 'data' => $row]);
    }

    /** This employee's own saved rows for an account (kept for backward compat). */
    public function responses(): JsonResponse
    {
        $mobile    = (string) $this->staff()->mobile;
        $accountId = request()->query('account_id');

        $rows = ActionLog::where('employee_mobile', $mobile)
            ->when($accountId, fn ($q) => $q->where('account_id', $accountId))
            ->orderByDesc('created_at')
            ->get();

        return response()->json(['success' => true, 'data' => $rows]);
    }

    /**
     * Save an Action Log row (= complete Check Out). Role-aware:
     *  - salesman  : requires outcome_slug (a stage), plus optional payment / market note
     *  - telecaller: requires call_outcome; links/updates the Knowlarity call_log row
     */
    public function store(): JsonResponse
    {
        $staff  = $this->staff();
        $mobile = (string) $staff->mobile;
        $role   = $this->roleFor($staff);

        $rules = [
            'account_id'         => 'required|string|max:191',
            'account_type'       => 'nullable|in:lead,customer',
            'beat_plan_id'       => 'nullable|integer',
            'check_in_at'        => 'nullable|date',
            'check_out_at'       => 'nullable|date',
            'duration_seconds'   => 'nullable|integer|min:0',
            'check_in_lat'       => 'nullable|numeric',
            'check_in_lng'       => 'nullable|numeric',
            'check_out_lat'      => 'nullable|numeric',
            'check_out_lng'      => 'nullable|numeric',
            'general_notes'      => 'nullable|string',
            'notes_related_to'   => 'nullable|string|max:150',
            'images'             => 'nullable|array',
            'images.*'           => 'string|max:500',
            'follow_up_date'     => 'nullable|date',
            'follow_up_note'     => 'nullable|string|max:255',
        ];

        if ($role === 'salesman') {
            $rules['outcome_slug']      = 'required|string|exists:action_log_stage_crm,slug';
            $rules['payment_collected'] = 'nullable|numeric|min:0';
            $rules['payment_mode']      = 'nullable|string|max:30';
            $rules['market_note']       = 'nullable|string';
        } else {
            $rules['call_outcome']       = 'required|in:answered,busy,no_answer,switch_off,invalid,callback,complaint';
            $rules['call_status']        = 'nullable|string|max:60';
            $rules['is_invalid_call']    = 'nullable|boolean';
            $rules['call_log_id']        = 'nullable|integer';
            $rules['conversation_notes'] = 'nullable|string';
            $rules['discussion_points']  = 'nullable|string';
            $rules['customer_stage']     = 'nullable|string|max:40';
            $rules['funnel_stage']       = 'nullable|string|max:40';
            $rules['category']           = 'required_if:call_outcome,complaint|string|max:191';
            $rules['description']        = 'required_if:call_outcome,complaint|string';
        }

        $data = validator(request()->all(), $rules)->validate();

        $outcomeName = null;
        if ($role === 'salesman') {
            $stage = ActionLogStage::where('slug', $data['outcome_slug'])->firstOrFail();
            $outcomeName = $stage->name;
        }

        $now = now();

        $row = DB::transaction(function () use ($data, $role, $mobile, $outcomeName, $now) {
            // Telecaller: fold the final outcome into the existing Knowlarity
            // call_log row instead of creating a duplicate 'manual' row.
            $callLogId = null;
            if ($role === 'telecaller') {
                $callLogId = $data['call_log_id'] ?? null;
                if ($callLogId) {
                    $log = CallLog::where('id', $callLogId)
                        ->where('employee_mobile', $mobile)
                        ->first();
                    if ($log) {
                        // Fold the telecaller's final outcome into the existing
                        // Knowlarity row so call_log_crm stays the source of
                        // truth for call analytics — no duplicate 'manual' row.
                        $log->call_outcome = $data['call_outcome'];
                        $log->notes        = $data['conversation_notes'] ?? $data['general_notes'] ?? $log->notes;
                        $log->save();
                    } else {
                        $callLogId = null; // not ours / gone
                    }
                }

                // No cloud-call row to attach to (manual dial) — record the call
                // so Call History + analytics still see it.
                if (!$callLogId) {
                    $log = CallLog::create([
                        'employee_mobile' => $mobile,
                        'source'          => 'manual',
                        'direction'       => 'outbound',
                        'account_id'      => $data['account_id'],
                        'account_type'    => $data['account_type'] ?? 'lead',
                        'call_outcome'    => $data['call_outcome'],
                        'notes'           => $data['conversation_notes'] ?? $data['general_notes'] ?? null,
                        'follow_up_date'  => $data['follow_up_date'] ?? null,
                        'called_at'       => $now,
                    ]);
                    $callLogId = $log->id;
                }
            }

            $row = ActionLog::create([
                'employee_mobile'   => $mobile,
                'role'              => $role,
                'account_id'        => $data['account_id'],
                'account_type'      => $data['account_type'] ?? null,
                'beat_plan_id'      => $data['beat_plan_id'] ?? null,
                'check_in_at'       => $data['check_in_at'] ?? null,
                'check_in_lat'      => $data['check_in_lat'] ?? null,
                'check_in_lng'      => $data['check_in_lng'] ?? null,
                'check_out_at'      => $data['check_out_at'] ?? $now,
                'check_out_lat'     => $data['check_out_lat'] ?? null,
                'check_out_lng'     => $data['check_out_lng'] ?? null,
                'duration_seconds'  => $data['duration_seconds'] ?? null,
                'status'            => 'visited',
                'outcome_slug'      => $data['outcome_slug'] ?? null,
                'outcome_name'      => $outcomeName,
                'general_notes'     => $data['general_notes'] ?? null,
                'notes_related_to'  => $data['notes_related_to'] ?? null,
                'images'            => $data['images'] ?? null,
                'call_outcome'      => $data['call_outcome'] ?? null,
                'call_status'       => $data['call_status'] ?? null,
                'is_invalid_call'   => (bool) ($data['is_invalid_call'] ?? false),
                'call_log_id'       => $callLogId,
                'conversation_notes' => $data['conversation_notes'] ?? null,
                'discussion_points' => $data['discussion_points'] ?? null,
                'customer_stage'    => $data['customer_stage'] ?? null,
                'funnel_stage'      => $data['funnel_stage'] ?? null,
                'payment_collected' => $data['payment_collected'] ?? null,
                'payment_mode'      => $data['payment_mode'] ?? null,
                'market_note'       => $data['market_note'] ?? null,
                'follow_up_date'    => $data['follow_up_date'] ?? null,
                'follow_up_note'    => $data['follow_up_note'] ?? null,
            ]);

            // Complaint ticket (telecaller complaint outcome).
            if ($role === 'telecaller' && ($data['call_outcome'] ?? null) === 'complaint') {
                Complaint::create([
                    'account_id'     => $data['account_id'],
                    'account_type'   => $data['account_type'] ?? 'lead',
                    'source_channel' => 'telecaller_call',
                    'raised_by'      => $mobile,
                    'call_log_id'    => $callLogId,
                    'category'       => $data['category'],
                    'description'    => $data['description'],
                ]);
            }

            // Lead stage/funnel update (telecaller).
            if ($role === 'telecaller' && ($data['account_type'] ?? null) === 'lead') {
                $patch = [];
                if (!empty($data['customer_stage'])) $patch['customerStage'] = $data['customer_stage'];
                if (!empty($data['funnel_stage']))   $patch['funnelStage']   = $data['funnel_stage'];
                if ($patch) {
                    LeadsAccount::where('id', $data['account_id'])->update($patch);
                }
            }

            // Follow-up — beat_plan_followup_crm is the single source both roles'
            // Today lists + the Callbacks screen read.
            if (!empty($data['follow_up_date'])) {
                // Legacy: retire any open call_log_crm follow-up for this account.
                CallLog::where('employee_mobile', $mobile)
                    ->where('account_id', $data['account_id'])
                    ->whereNotNull('follow_up_date')
                    ->where('callback_done', false)
                    ->update(['callback_done' => true]);

                BeatPlanFollowup::where('staff_id', $mobile)
                    ->where('account_id', $data['account_id'])
                    ->where('done', false)
                    ->update(['done' => true, 'done_at' => $now]);

                BeatPlanFollowup::create([
                    'account_id'           => $data['account_id'],
                    'account_type'         => $data['account_type'] ?? null,
                    'staff_id'             => $mobile,
                    'due_date'             => Carbon::parse($data['follow_up_date'])->toDateString(),
                    'note'                 => $data['follow_up_note'] ?? ($data['conversation_notes'] ?? null),
                    'source_action_log_id' => $row->id,
                ]);
            }

            return $row;
        });

        return response()->json(['success' => true, 'data' => $row->fresh()], 201);
    }

    /** Upload a single Action Log photo; returns its stored relative path. */
    public function uploadImage(): JsonResponse
    {
        $validated = request()->validate([
            'image' => 'required|image|mimes:jpg,jpeg,png,webp|max:5120',
        ]);

        $file = $validated['image'];
        $name = 'action_' . Str::uuid()->toString() . '.' . $file->getClientOriginalExtension();
        $path = $file->storeAs('action_logs', $name, 'public');

        return response()->json(['success' => true, 'path' => '/storage/' . $path]);
    }
}

<?php

namespace App\Jobs;

use App\Models\CallLog;
use App\Models\DeliStaff;
use App\Models\LeadsAccount;
use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Foundation\Bus\Dispatchable;
use Illuminate\Queue\InteractsWithQueue;
use Illuminate\Queue\SerializesModels;
use Illuminate\Support\Facades\DB;

class ProcessKnowlarityCallCompleted implements ShouldQueue
{
    use Dispatchable, InteractsWithQueue, Queueable, SerializesModels;

    // Knowlarity's exact statuses for "not connected" calls; confirm against a
    // real webhook payload and adjust if this account's plan differs.
    private const MISSED_STATUSES = ['missed', 'no-answer', 'no_answer', 'busy'];

    public function __construct(protected array $payload) {}

    public function handle(): void
    {
        // NOTE: field names below (caller_number, call_id, etc.) are the common
        // shape reported for SR's Call Data Post API. Log the raw payload on your
        // first real webhook hit and adjust these keys to match exactly what
        // this account sends.
        $payload = $this->payload;

        $callId        = $payload['call_id'] ?? $payload['id'] ?? null;
        $callerNumber  = $payload['caller_number'] ?? $payload['customer_number'] ?? null;
        $agentNumber   = $payload['agent_number'] ?? null;
        $status        = $payload['status'] ?? null;
        $duration      = $payload['duration'] ?? $payload['duration_seconds'] ?? null;
        $recordingUrl  = $payload['recording_url'] ?? null;
        $direction     = $payload['direction'] ?? 'inbound';

        $outcome = $this->mapOutcome($status);

        // A row already exists if this call was initiated from the CRM's
        // click-to-call button (KnowlarityCallController pre-creates it).
        $log = $callId ? CallLog::where('knowlarity_call_id', $callId)->first() : null;

        // Fallback: the CRM sends its own call_log row id to Knowlarity as
        // additional_params.uniqueid, which is echoed back here. If call_id
        // didn't line up (response-shape drift), this still finds the
        // pre-created row instead of spawning a duplicate inbound record.
        if (!$log) {
            $extraParams = $payload['additional_params'] ?? [];
            if (is_string($extraParams)) {
                $extraParams = json_decode($extraParams, true) ?: [];
            }
            $uniqueId = $extraParams['uniqueid'] ?? $payload['uniqueid'] ?? null;
            if ($uniqueId) {
                $log = CallLog::where('id', $uniqueId)->where('source', 'knowlarity')->first();
            }
        }

        if ($log) {
            if (!$log->knowlarity_call_id && $callId) {
                $log->knowlarity_call_id = $callId;
            }
            $log->fill([
                'call_outcome'     => $outcome,
                'duration_seconds' => $duration,
                'recording_url'    => $recordingUrl,
                'raw_payload'      => $payload,
            ]);
            if (in_array($outcome, ['missed', 'no_answer', 'busy'], true)) {
                $log->follow_up_date = now()->addHours(2);
                $log->callback_done  = false;
            }
            $log->save();

            return;
        }

        // Genuine inbound call the CRM didn't initiate - match caller + agent by phone.
        [$accountId, $accountType] = $this->matchAccount($callerNumber);
        $employeeMobile = $this->matchAgent($agentNumber);

        $log = CallLog::create([
            'employee_mobile'    => $employeeMobile,
            'source'             => 'knowlarity',
            'direction'          => $direction,
            'knowlarity_call_id' => $callId,
            'account_id'         => $accountId,
            'account_type'       => $accountType,
            'call_outcome'       => $outcome,
            'called_at'          => now(),
            'duration_seconds'   => $duration,
            'recording_url'      => $recordingUrl,
            'raw_payload'        => $payload,
            'follow_up_date'     => in_array($outcome, ['missed', 'no_answer', 'busy'], true) ? now()->addHours(2) : null,
            'callback_done'      => false,
        ]);
    }

    private function mapOutcome(?string $status): ?string
    {
        return match ($status) {
            'answered', 'connected' => 'answered',
            'busy'                  => 'busy',
            'missed', 'no-answer', 'no_answer' => 'no_answer',
            'failed', 'switch-off', 'switch_off' => 'switch_off',
            default => $status,
        };
    }

    /** @return array{0: ?string, 1: string} [account_id, account_type] */
    private function matchAccount(?string $callerNumber): array
    {
        if (!$callerNumber) {
            return [null, 'unknown'];
        }

        $lead = LeadsAccount::where('contactNumber', $callerNumber)->first(['id']);
        if ($lead) {
            return [(string) $lead->id, 'lead'];
        }

        $customer = DB::table('user')->where('contactno', $callerNumber)->first('userid');
        if ($customer) {
            return [(string) $customer->userid, 'customer'];
        }

        return [null, 'unknown'];
    }

    private function matchAgent(?string $agentNumber): ?string
    {
        if (!$agentNumber) {
            return null;
        }

        return DeliStaff::where('mobile', $agentNumber)->value('mobile');
    }
}

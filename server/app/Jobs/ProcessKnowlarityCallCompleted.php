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

    public function __construct(protected array $payload) {}

    public function handle(): void
    {
        static::apply($this->payload);
    }

    /**
     * Shared by the webhook job and the getCallLogs() reconciliation sync
     * (app/Console/Commands/SyncKnowlarityCallLogs.php) - both eventually
     * produce the same raw record shape confirmed from a live /calllog pull:
     * {uuid, customer_number, agent_number, call_duration, call_recording,
     * knowlarity_number, start_time, ...}. The webhook's exact payload shape
     * is still unconfirmed (it has never actually fired in this account), so
     * this also accepts the originally-guessed call_id/caller_number/status/
     * duration/recording_url keys as a fallback.
     */
    public static function apply(array $payload): void
    {
        $callId       = $payload['uuid'] ?? $payload['call_id'] ?? $payload['id'] ?? null;
        $callerNumber = $payload['customer_number'] ?? $payload['caller_number'] ?? null;
        $duration     = $payload['call_duration'] ?? $payload['duration'] ?? $payload['duration_seconds'] ?? 0;
        $recordingUrl = $payload['call_recording'] ?? $payload['recording_url'] ?? null;
        $direction    = $payload['direction'] ?? null;

        // agent_number carries the outcome as a "Label#+91..." prefix, or the
        // literal string "Did Not Process" with no number at all - confirmed
        // from a live /calllog pull, e.g. "Customer Missed#+918103858929".
        [$outcome, $agentNumber] = isset($payload['agent_number'])
            ? static::parseAgentField((string) $payload['agent_number'], (int) $duration, (string) ($recordingUrl ?? ''))
            : [static::mapStatus($payload['status'] ?? null), $payload['agent_number'] ?? null];

        $recordingUrl = $recordingUrl ?: null;

        // A row already exists if this call was initiated from the CRM's
        // click-to-call button (KnowlarityCallController pre-creates it).
        $log = $callId ? CallLog::where('knowlarity_call_id', $callId)->first() : null;

        // Fallback: the CRM sends its own call_log row id to Knowlarity as
        // additional_params.uniqueid, which the webhook (if it ever fires)
        // echoes back. Not present on /calllog pulls - call_id/uuid matching
        // above is the only path there.
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
            if ($outcome === 'no_answer' || $outcome === 'busy') {
                $log->follow_up_date = now()->addHours(2);
                $log->callback_done  = false;
            }
            $log->save();

            return;
        }

        // Genuine inbound call the CRM didn't initiate - match caller + agent by phone.
        [$accountId, $accountType] = static::matchAccount($callerNumber);
        $employeeMobile = static::matchAgent($agentNumber);

        CallLog::create([
            'employee_mobile'    => $employeeMobile,
            'source'             => 'knowlarity',
            'direction'          => $direction ?? 'inbound',
            'knowlarity_call_id' => $callId,
            'account_id'         => $accountId,
            'account_type'       => $accountType,
            'call_outcome'       => $outcome,
            'called_at'          => isset($payload['start_time']) ? now()->parse($payload['start_time']) : now(),
            'duration_seconds'   => $duration,
            'recording_url'      => $recordingUrl,
            'raw_payload'        => $payload,
            'follow_up_date'     => ($outcome === 'no_answer' || $outcome === 'busy') ? now()->addHours(2) : null,
            'callback_done'      => false,
        ]);
    }

    /**
     * agent_number encodes the outcome as a prefix: "Customer Missed#+91...",
     * "Agent Missed#+91...", or the literal "Did Not Process" (no number).
     * A clean number with no "#" and a positive duration means it connected.
     */
    private static function parseAgentField(string $raw, int $duration, string $recordingUrl): array
    {
        if ($raw === 'Did Not Process') {
            return ['invalid', null];
        }

        if (str_contains($raw, '#')) {
            [$label, $number] = explode('#', $raw, 2);
            $label = trim($label);
            $outcome = match (true) {
                str_contains($label, 'Customer Missed') => 'no_answer',
                str_contains($label, 'Agent Missed')    => 'no_answer',
                str_contains($label, 'Busy')             => 'busy',
                default                                   => 'invalid',
            };
            return [$outcome, $number ?: null];
        }

        return [$duration > 0 ? 'answered' : 'no_answer', $raw];
    }

    private static function mapStatus(?string $status): ?string
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
    private static function matchAccount(?string $callerNumber): array
    {
        if (!$callerNumber) {
            return [null, 'unknown'];
        }

        // Incoming numbers are full E.164 (+91XXXXXXXXXX); stored numbers are bare 10-digit.
        $bare = ltrim(preg_replace('/\D/', '', $callerNumber), '91');
        $bare = strlen($bare) > 10 ? substr($bare, -10) : $bare;

        $lead = LeadsAccount::where('contactNumber', $bare)->first(['id']);
        if ($lead) {
            return [(string) $lead->id, 'lead'];
        }

        $customer = DB::table('user')->where('contactno', $bare)->first('userid');
        if ($customer) {
            return [(string) $customer->userid, 'customer'];
        }

        return [null, 'unknown'];
    }

    private static function matchAgent(?string $agentNumber): ?string
    {
        if (!$agentNumber) {
            return null;
        }

        $bare = ltrim(preg_replace('/\D/', '', $agentNumber), '91');
        $bare = strlen($bare) > 10 ? substr($bare, -10) : $bare;

        return DeliStaff::where('mobile', $bare)->value('mobile');
    }
}

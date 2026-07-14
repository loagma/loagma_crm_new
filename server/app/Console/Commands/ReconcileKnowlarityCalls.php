<?php

namespace App\Console\Commands;

use App\Jobs\ProcessKnowlarityCallCompleted;
use App\Models\CallLog;
use App\Services\KnowlarityService;
use Illuminate\Console\Command;

class ReconcileKnowlarityCalls extends Command
{
    protected $signature = 'knowlarity:reconcile {--hours=2 : How far back to sweep}';

    protected $description = 'Close out call_log_crm rows stuck on pending by pulling Knowlarity call logs the webhook may have missed';

    public function handle(KnowlarityService $knowlarity): int
    {
        $hours = max(1, (int) $this->option('hours'));

        // Look slightly further back than the fetch window so a call placed just
        // before the window still has its row available for matching.
        $pending = CallLog::where('source', 'knowlarity')
            ->where('call_outcome', 'pending')
            ->where('called_at', '>=', now()->subHours($hours + 1))
            ->get();

        if ($pending->isEmpty()) {
            $this->info('No pending Knowlarity calls to reconcile.');

            return self::SUCCESS;
        }

        // app timezone is Asia/Kolkata, so P yields the +05:30 offset Knowlarity expects.
        $logs = $knowlarity->getCallLogs(
            now()->subHours($hours)->format('Y-m-d H:i:sP'),
            now()->format('Y-m-d H:i:sP'),
        );

        // Knowlarity's calllog API wraps results in "objects"; keep fallbacks
        // until a real response confirms the shape.
        $entries = $logs['objects'] ?? $logs['data'] ?? [];

        $dispatched = 0;
        foreach ($entries as $entry) {
            if (!is_array($entry)) {
                continue;
            }

            $callId = $entry['call_id'] ?? $entry['id'] ?? $entry['callid'] ?? null;

            $extraParams = $entry['additional_params'] ?? [];
            if (is_string($extraParams)) {
                $extraParams = json_decode($extraParams, true) ?: [];
            }
            $uniqueId = $extraParams['uniqueid'] ?? $entry['uniqueid'] ?? null;

            $row = $pending->first(fn (CallLog $log) => ($callId !== null && (string) $log->knowlarity_call_id === (string) $callId)
                || ($uniqueId !== null && (string) $log->id === (string) $uniqueId));

            if ($row) {
                // Reuse the webhook job so outcome mapping, duration, recording
                // URL, and follow-up scheduling stay identical to the live path.
                ProcessKnowlarityCallCompleted::dispatch($entry);
                $dispatched++;
            }
        }

        $this->info("Reconciled {$dispatched} of {$pending->count()} pending call(s) from " . count($entries) . ' provider log entries.');

        return self::SUCCESS;
    }
}

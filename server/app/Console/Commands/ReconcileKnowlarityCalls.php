<?php

namespace App\Console\Commands;

use App\Jobs\ProcessKnowlarityCallCompleted;
use App\Services\KnowlarityService;
use Illuminate\Console\Command;

class ReconcileKnowlarityCalls extends Command
{
    protected $signature = 'knowlarity:reconcile {--hours=2 : How far back to sweep}';

    protected $description = 'Mirror Knowlarity call log entries into call_log_crm - updates rows the webhook missed and backfills calls the CRM never initiated (e.g. placed from the SR portal directly)';

    public function handle(KnowlarityService $knowlarity): int
    {
        $hours = max(1, (int) $this->option('hours'));

        // app timezone is Asia/Kolkata, so P yields the +05:30 offset Knowlarity expects.
        $logs = $knowlarity->getCallLogs(
            now()->subHours($hours)->format('Y-m-d H:i:sP'),
            now()->format('Y-m-d H:i:sP'),
        );

        // Confirmed live shape: {"meta": {...}, "objects": [{uuid, customer_number,
        // agent_number, call_duration, call_recording, ...}]}. Keep "data" as a
        // fallback in case the shape ever differs by plan/endpoint version.
        $entries = $logs['objects'] ?? $logs['data'] ?? [];

        foreach ($entries as $entry) {
            if (!is_array($entry)) {
                continue;
            }

            // Reuse the webhook job's logic so outcome mapping, duration, recording
            // URL, and follow-up scheduling stay identical to the live path. apply()
            // is idempotent (matches by knowlarity_call_id), so re-processing the
            // same entry across overlapping windows just updates, never duplicates.
            ProcessKnowlarityCallCompleted::dispatch($entry);
        }

        $this->info('Processed ' . count($entries) . " Knowlarity call log entries from the last {$hours}h.");

        return self::SUCCESS;
    }
}

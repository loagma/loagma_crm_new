<?php

namespace App\Services;

use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;

class KnowlarityService
{
    protected string $baseUrl;
    protected string $username;
    protected string $srApiKey;
    protected string $appAccessKey;
    protected string $srNumber;

    public function __construct()
    {
        $this->baseUrl      = config('knowlarity.base_url');
        $this->username     = config('knowlarity.username');
        $this->srApiKey     = config('knowlarity.sr_api_key');
        $this->appAccessKey = config('knowlarity.app_access_key');
        $this->srNumber     = config('knowlarity.sr_number');
    }

    protected function headers(array $extra = []): array
    {
        return array_merge([
            'authorization' => $this->srApiKey,
            'x-api-key'     => "{$this->username}:{$this->appAccessKey}",
            'content-type'  => 'application/json',
        ], $extra);
    }

    /**
     * Bridge an agent and a customer number into a live call.
     * Used behind the telecaller app's "Call" button.
     */
    public function makeCall(string $agentNumber, string $customerNumber): array
    {
        $response = Http::withHeaders($this->headers())
            ->post("{$this->baseUrl}/call", [
                'k_number'        => $this->srNumber,
                'agent_number'    => $agentNumber,
                'customer_number' => $customerNumber,
            ]);

        if ($response->failed()) {
            Log::error('Knowlarity makeCall failed', [
                'status' => $response->status(),
                'body'   => $response->body(),
            ]);
        }

        return $response->json() ?? [];
    }

    /**
     * Pull call logs for a date range - useful for a reconciliation job
     * that catches anything the webhook might have missed.
     */
    public function getCallLogs(string $startTime, string $endTime): array
    {
        $response = Http::withHeaders($this->headers([
            'start_time' => $startTime, // format: 2026-07-01 00:00:00+05:30
            'end_time'   => $endTime,
        ]))->get("{$this->baseUrl}/calllog");

        return $response->json() ?? [];
    }
}

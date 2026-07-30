<?php

namespace App\Services;

use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;

class KnowlarityService
{
    protected string $baseUrl;
    protected string $srApiKey;
    protected string $appAccessKey;
    protected string $srNumber;

    public function __construct()
    {
        $this->baseUrl      = config('knowlarity.base_url');
        $this->srApiKey     = config('knowlarity.sr_api_key');
        $this->appAccessKey = config('knowlarity.app_access_key');
        $this->srNumber     = config('knowlarity.sr_number');
    }

    protected function headers(array $extra = []): array
    {
        return array_merge([
            // kpi Basic API: x-api-key is a single token; authorization is the SR auth key.
            'authorization' => $this->srApiKey,
            'x-api-key'     => $this->appAccessKey,
            'content-type'  => 'application/json',
        ], $extra);
    }

    /**
     * Bridge an agent and a customer number into a live call.
     * Used behind the telecaller app's "Call" button.
     */
    public function makeCall(string $agentNumber, string $customerNumber, ?string $uniqueId = null): array
    {
        $body = [
            'k_number'        => $this->srNumber,
            'agent_number'    => $this->toE164($agentNumber),
            'customer_number' => $this->toE164($customerNumber),
        ];

        if ($uniqueId !== null) {
            // Echoed back on the call-completed webhook; lets the CRM re-find its
            // pre-created call_log row even when call_id parsing drifts.
            $body['additional_params'] = ['uniqueid' => $uniqueId];
        }

        $response = Http::withHeaders($this->headers())
            ->post("{$this->baseUrl}/call/makecall", $body);

        if ($response->failed()) {
            Log::error('Knowlarity makeCall failed', [
                'status' => $response->status(),
                'body'   => $response->body(),
            ]);
        }

        return $response->json() ?? [];
    }

    /**
     * Every phone number stored in this CRM (DeliStaff.mobile, LeadsAccount.contactNumber,
     * legacy user.contactno) is a bare 10-digit Indian number with no country code, but
     * Knowlarity's API requires full international format (+91XXXXXXXXXX) or it rejects
     * the call outright ("Please enter a valid Agent number in international format").
     */
    protected function toE164(string $number): string
    {
        $digits = preg_replace('/\D/', '', $number);

        if (str_starts_with($number, '+')) {
            return '+' . $digits;
        }
        if (strlen($digits) === 10) {
            return '+91' . $digits;
        }
        if (strlen($digits) === 12 && str_starts_with($digits, '91')) {
            return '+' . $digits;
        }

        return '+' . $digits; // best effort for any other shape
    }

    /**
     * Pull call logs for a date range - the reconciliation path for calls the
     * webhook missed (confirmed unreliable for C2C calls in this account).
     * start_time/end_time are query params, NOT headers - sending them as
     * headers (the original bug here) gets a silent 500 from Knowlarity.
     */
    public function getCallLogs(string $startTime, string $endTime): array
    {
        $response = Http::withHeaders($this->headers())
            ->get("{$this->baseUrl}/calllog", [
                'start_time' => $startTime, // format: 2026-07-01 00:00:00+05:30
                'end_time'   => $endTime,
            ]);

        if ($response->failed()) {
            Log::error('Knowlarity getCallLogs failed', [
                'status' => $response->status(),
                'body'   => $response->body(),
            ]);
        }

        return $response->json() ?? [];
    }

    /**
     * Recording URLs (kservices.knowlarity.com/kstorage/read?...) require the
     * same authorization/x-api-key headers as every other API call - a plain
     * browser <audio> element or a mobile player pointed straight at the URL
     * gets a 401, since neither can attach custom headers to a media request.
     * The CRM backend fetches the bytes itself (it holds the credentials) and
     * hands them to the client, instead of exposing a directly-playable URL.
     *
     * @return array{0: string, 1: string} [raw bytes, content-type]
     */
    public function fetchRecording(string $url): array
    {
        $response = Http::withHeaders($this->headers())->get($url);

        if ($response->failed()) {
            Log::error('Knowlarity fetchRecording failed', [
                'status' => $response->status(),
                'url'    => $url,
            ]);

            return ['', ''];
        }

        return [$response->body(), $response->header('Content-Type') ?: 'audio/mpeg'];
    }
}

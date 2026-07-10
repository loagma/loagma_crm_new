<?php

namespace App\Http\Controllers;

use App\Jobs\ProcessKnowlarityCallCompleted;
use Illuminate\Http\Request;
use Illuminate\Http\Response;

class KnowlarityWebhookController extends Controller
{
    /**
     * Shared-secret check for webhook routes.
     *
     * Knowlarity does not publish a signed-payload/HMAC scheme, so the practical
     * approach is: a long random token embedded in the webhook URL registered
     * with Knowlarity (Resources > Hook APIs > Call Data Post API), checked here
     * with a constant-time comparison before any processing happens.
     */
    protected function verifySecret(string $secret): void
    {
        abort_unless(hash_equals((string) config('knowlarity.webhook_secret'), $secret), Response::HTTP_FORBIDDEN);
    }

    /**
     * "Call Data Post API" - Knowlarity posts here when a call finishes.
     * Registered URL: https://yourcrm.com/webhooks/knowlarity/{secret}/call-completed
     *
     * Keep this handler fast: validate + dispatch a queued job, return 200 immediately.
     * Knowlarity may retry on slow/non-200 responses.
     */
    public function callCompleted(Request $request, string $secret)
    {
        $this->verifySecret($secret);

        ProcessKnowlarityCallCompleted::dispatch($request->all());

        return response()->json(['status' => 'received']);
    }
}

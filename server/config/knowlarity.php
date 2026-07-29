<?php

// Add the matching keys below to your .env file:
//
// KNOWLARITY_SR_API_KEY=your_sr_api_key                // goes into the "Authorization" header, as-is
// KNOWLARITY_APP_ACCESS_KEY=your_application_access_key
// KNOWLARITY_SR_NUMBER=+9190XXXXXXXX
// KNOWLARITY_BASE_URL=https://kpi.knowlarity.com/Basic/v1/account
// KNOWLARITY_WEBHOOK_SECRET=some_long_random_string   // shared secret we invent ourselves (Knowlarity has no signed-webhook scheme), checked in KnowlarityWebhookController

return [
    'sr_api_key'     => env('KNOWLARITY_SR_API_KEY'),
    'app_access_key' => env('KNOWLARITY_APP_ACCESS_KEY'),
    'sr_number'      => env('KNOWLARITY_SR_NUMBER'),
    'base_url'       => env('KNOWLARITY_BASE_URL', 'https://kpi.knowlarity.com/Basic/v1/account'),
    'webhook_secret' => env('KNOWLARITY_WEBHOOK_SECRET'),
];

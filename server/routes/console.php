<?php

use Illuminate\Foundation\Inspiring;
use Illuminate\Support\Facades\Artisan;
use Illuminate\Support\Facades\Schedule;

Artisan::command('inspire', function () {
    $this->comment(Inspiring::quote());
})->purpose('Display an inspiring quote');

// Safety net for Knowlarity webhooks that never arrived (server down, retry
// exhausted): sweep the last 2h of provider call logs and close out any
// call_log_crm rows still stuck on call_outcome='pending'.
Schedule::command('knowlarity:reconcile')->hourly();

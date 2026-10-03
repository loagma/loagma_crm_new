<?php

namespace App\Providers;

use Illuminate\Cache\RateLimiting\Limit;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\RateLimiter;
use Illuminate\Support\ServiceProvider;

class AppServiceProvider extends ServiceProvider
{
    /**
     * Register any application services.
     */
    public function register(): void
    {
        //
    }

    /**
     * Bootstrap any application services.
     */
    public function boot(): void
    {
        // The login "OTP" is a short static PIN — cap guesses per mobile+IP so
        // it can't be brute-forced. Keyed on both so one shared office IP
        // doesn't lock every telecaller out at 9am.
        RateLimiter::for('otp', function (Request $request) {
            return Limit::perMinute(5)->by($request->input('mobile') . '|' . $request->ip());
        });
    }
}

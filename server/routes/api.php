<?php

use Illuminate\Support\Facades\Route;
use App\Http\Controllers\HealthController;
use App\Http\Controllers\Auth\OtpAuthController;
use App\Http\Controllers\MastersController;

Route::get('/health', [HealthController::class, 'index']);

// Public: used by Flutter dev-mode role picker
Route::get('/masters/roles', [MastersController::class, 'roles']);

// OTP Auth
Route::prefix('auth')->group(function () {
    Route::post('/send-otp',   [OtpAuthController::class, 'sendOtp']);
    Route::post('/verify-otp', [OtpAuthController::class, 'verifyOtp']);

    Route::middleware('jwt.auth')->group(function () {
        Route::get('/me',       [OtpAuthController::class, 'me']);
        Route::post('/logout',  [OtpAuthController::class, 'logout']);
    });
});

// ---------------------------------------------------------------------------
// RBAC-protected routes (examples — add your real routes here)
// ---------------------------------------------------------------------------
// Route::middleware(['jwt.auth', 'role:admin'])->group(function () {
//     Route::get('/admin/...', [...]);
// });
//
// Route::middleware(['jwt.auth', 'role:manager,admin'])->group(function () {
//     Route::get('/reports/...', [...]);
// });

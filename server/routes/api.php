<?php

use Illuminate\Support\Facades\Route;
use App\Http\Controllers\HealthController;
use App\Http\Controllers\Auth\OtpAuthController;
use App\Http\Controllers\MastersController;
use App\Http\Controllers\LeadsAccountController;
use App\Http\Controllers\AreaController;
use App\Http\Controllers\AreaAssignController;

Route::get('/health', [HealthController::class, 'index']);

// Public: used by Flutter dev-mode role picker
Route::get('/masters/roles', [MastersController::class, 'roles']);
// List staff/employees (simple public endpoint for dashboards)
Route::get('/employees', [MastersController::class, 'employees']);
Route::post('/employees', [MastersController::class, 'store']);
Route::put('/employees/{id}', [MastersController::class, 'update']);
Route::get('/employees/{id}', [MastersController::class, 'show']);

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
// Lead Accounts CRUD
// ---------------------------------------------------------------------------
Route::prefix('lead-accounts')->group(function () {
    Route::get('/',                [LeadsAccountController::class, 'index']);
    Route::post('/',               [LeadsAccountController::class, 'store']);
    Route::post('/upload-image',   [LeadsAccountController::class, 'uploadImage']);
    Route::get('/check-contact',   [LeadsAccountController::class, 'checkContact']); // must be before /{id}
    Route::get('/{id}',            [LeadsAccountController::class, 'show']);
    Route::put('/{id}',            [LeadsAccountController::class, 'update']);
    Route::delete('/{id}',         [LeadsAccountController::class, 'destroy']);
});

// ---------------------------------------------------------------------------
// Areas + Pincodes (dynamic marketing + area assign source)
// ---------------------------------------------------------------------------
Route::prefix('areas')->group(function () {
    Route::get('/', [AreaController::class, 'index']);
    Route::post('/', [AreaController::class, 'store']);
    Route::get('/{id}', [AreaController::class, 'show']);
    Route::put('/{id}', [AreaController::class, 'update']);
    Route::delete('/{id}', [AreaController::class, 'destroy']);

    Route::post('/{id}/pincodes', [AreaController::class, 'addPincodes']);
    Route::put('/{id}/pincodes/{pincode}', [AreaController::class, 'updatePincode']);
    Route::delete('/{id}/pincodes/{pincode}', [AreaController::class, 'deletePincode']);
});

// ---------------------------------------------------------------------------
// Area Assign (per employee: get / save / delete)
// ---------------------------------------------------------------------------
Route::prefix('area-assign')->group(function () {
    Route::get('/',                [AreaAssignController::class, 'index']);
    Route::get('/{employeeId}',    [AreaAssignController::class, 'show']);
    Route::post('/{employeeId}',   [AreaAssignController::class, 'save']);
    Route::delete('/{employeeId}', [AreaAssignController::class, 'destroy']);
});

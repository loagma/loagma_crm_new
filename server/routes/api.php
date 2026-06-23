<?php

use Illuminate\Support\Facades\Route;
use App\Http\Controllers\HealthController;
use App\Http\Controllers\Auth\OtpAuthController;
use App\Http\Controllers\MastersController;
use App\Http\Controllers\LeadsAccountController;
use App\Http\Controllers\AreaController;
use App\Http\Controllers\AreaAssignController;
use App\Http\Controllers\InchargeAssignController;
use App\Http\Controllers\AttendanceController;
use App\Http\Controllers\BeatPlanController;
use App\Http\Controllers\CallLogController;
use App\Http\Controllers\OrderFunnelController;
use App\Http\Controllers\PincodeController;

Route::get('/health', [HealthController::class, 'index']);

// Pincode lookup proxy (api.postalpincode.in is unreachable from web client)
Route::get('/utils/pincode/{pincode}', [PincodeController::class, 'lookup']);

// Roles CRUD (role_crm table)
Route::get('/masters/roles',         [MastersController::class, 'roles']);
Route::post('/masters/roles',        [MastersController::class, 'storeRole']);
Route::delete('/masters/roles/{id}', [MastersController::class, 'destroyRole']);
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
Route::get('/customers', [LeadsAccountController::class, 'customers']);

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
// Attendance (employee actions)
// ---------------------------------------------------------------------------
Route::prefix('attendance')->group(function () {
    Route::post('/upload-photo',  [AttendanceController::class, 'uploadPhoto']);
    Route::post('/punch-in',      [AttendanceController::class, 'punchIn']);
    Route::post('/punch-out',     [AttendanceController::class, 'punchOut']);
    Route::post('/confirm-punch', [AttendanceController::class, 'confirmPunch']);
    Route::post('/break',         [AttendanceController::class, 'updateBreak']);
    Route::get('/today',          [AttendanceController::class, 'today']);
    Route::get('/history',        [AttendanceController::class, 'myHistory']);
});

// ---------------------------------------------------------------------------
// Attendance (admin management)
// ---------------------------------------------------------------------------
Route::prefix('admin/attendance')->group(function () {
    Route::get('/pending',                   [AttendanceController::class, 'pendingList']);
    Route::get('/pending-count',             [AttendanceController::class, 'pendingCount']);
    Route::get('/settings/{employeeMobile}', [AttendanceController::class, 'getSettings']);
    Route::put('/settings/{employeeMobile}', [AttendanceController::class, 'updateSettings']);
    Route::post('/{id}/approve',             [AttendanceController::class, 'approve']);
    Route::post('/{id}/reject',              [AttendanceController::class, 'reject']);
    Route::get('/{employeeMobile}',          [AttendanceController::class, 'adminEmployeeAttendance']);
});

// ---------------------------------------------------------------------------
// Area Assign (salesman + incharge: get / save / delete)
// ---------------------------------------------------------------------------
Route::prefix('area-assign')->group(function () {
    Route::get('/',                [AreaAssignController::class, 'index']);
    Route::get('/{employeeId}',    [AreaAssignController::class, 'show']);
    Route::post('/{employeeId}',   [AreaAssignController::class, 'save']);
    Route::delete('/{employeeId}', [AreaAssignController::class, 'destroy']);
});

// ---------------------------------------------------------------------------
// Incharge Assign (head_incharge → incharge mapping: get / save / delete)
// ---------------------------------------------------------------------------
Route::prefix('incharge-assign')->group(function () {
    Route::get('/',                    [InchargeAssignController::class, 'index']);
    Route::get('/{headInchargeId}',    [InchargeAssignController::class, 'show']);
    Route::post('/{headInchargeId}',   [InchargeAssignController::class, 'save']);
    Route::delete('/{headInchargeId}', [InchargeAssignController::class, 'destroy']);
});

// ---------------------------------------------------------------------------
// Beat Plan (salesman self-assigns accounts to recurring schedule)
// ---------------------------------------------------------------------------
Route::prefix('beat-plan')->group(function () {
    Route::get('/my-plans',         [BeatPlanController::class, 'myPlans']);
    Route::post('/assign',          [BeatPlanController::class, 'assign']);
    Route::post('/unassign-bulk',   [BeatPlanController::class, 'unassignBulk']);
    Route::get('/today',            [BeatPlanController::class, 'today']);
    Route::get('/week',             [BeatPlanController::class, 'week']);
    Route::get('/stats',            [BeatPlanController::class, 'accountStats']);
    Route::delete('/{id}',          [BeatPlanController::class, 'unassign']);
    Route::post('/{id}/visit',      [BeatPlanController::class, 'recordVisit']);
});

// ---------------------------------------------------------------------------
Route::get('/call-logs',  [CallLogController::class, 'index']);
Route::post('/call-logs', [CallLogController::class, 'store']);

// ---------------------------------------------------------------------------
// Order Funnel (dynamic stages from order_funnel_crm + saved responses)
// ---------------------------------------------------------------------------
Route::prefix('order-funnels')->group(function () {
    Route::get('/',             [OrderFunnelController::class, 'options']);
    Route::get('/response',     [OrderFunnelController::class, 'latestResponse']);
    Route::get('/responses',    [OrderFunnelController::class, 'responses']);
    Route::post('/response',    [OrderFunnelController::class, 'store']);
    Route::post('/upload-image',[OrderFunnelController::class, 'uploadImage']);
});

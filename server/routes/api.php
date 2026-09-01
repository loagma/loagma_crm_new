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
use App\Http\Controllers\CartController;
use App\Http\Controllers\CallLogController;
use App\Http\Controllers\ComplaintController;
use App\Http\Controllers\KnowlarityCallController;
use App\Http\Controllers\KnowlarityWebhookController;
use App\Http\Controllers\AccountHistoryController;
use App\Http\Controllers\ActionLogController;
use App\Http\Controllers\OrderListController;
use App\Http\Controllers\PincodeController;
use App\Http\Controllers\ProductController;
use App\Http\Controllers\SalesOrderController;
use App\Http\Controllers\TelecallerController;
use App\Http\Controllers\CallScriptController;
use App\Http\Controllers\TrackingController;

Route::get('/health', [HealthController::class, 'index']);

// Pincode lookup proxy (api.postalpincode.in is unreachable from web client)
Route::get('/utils/pincode/{pincode}', [PincodeController::class, 'lookup']);

// Roles CRUD (role_crm table)
Route::get('/masters/roles',         [MastersController::class, 'roles']);
Route::post('/masters/roles',        [MastersController::class, 'storeRole']);
Route::delete('/masters/roles/{id}', [MastersController::class, 'destroyRole']);
// Unit list (units_master table) — Sales Order line-item unit dropdown
Route::get('/masters/units', [MastersController::class, 'units']);
// List staff/employees (simple public endpoint for dashboards)
Route::get('/employees', [MastersController::class, 'employees']);
Route::post('/employees', [MastersController::class, 'store']);
Route::put('/employees/{id}', [MastersController::class, 'update']);
Route::get('/employees/{id}', [MastersController::class, 'show']);

// OTP Auth
Route::prefix('auth')->group(function () {
    Route::post('/send-otp',   [OtpAuthController::class, 'sendOtp']);
    Route::post('/verify-otp', [OtpAuthController::class, 'verifyOtp']);

    Route::middleware('jwtauth')->group(function () {
        Route::get('/me',       [OtpAuthController::class, 'me']);
        Route::post('/logout',  [OtpAuthController::class, 'logout']);
    });
});

// ---------------------------------------------------------------------------
// Lead Accounts CRUD
// ---------------------------------------------------------------------------
Route::get('/customers', [LeadsAccountController::class, 'customers']);

// Order list (real orders/user/admin tables — separate from the order-funnel feature)
Route::get('/orders', [OrderListController::class, 'index']);
Route::get('/orders/owner/{buyerUserId}/products', [OrderListController::class, 'ownerProductHistory']); // must be before /orders/{orderId}
Route::get('/orders/{orderId}', [OrderListController::class, 'show']);

// Sales Order create (draft/pending only — see server/app/Http/Controllers/SalesOrderController.php)
Route::get('/sales-orders/next-order-id', [SalesOrderController::class, 'nextOrderId']); // must be before POST /sales-orders in case of future {id} routes
Route::post('/sales-orders', [SalesOrderController::class, 'store']);
Route::put('/orders/{orderId}/items', [SalesOrderController::class, 'updateItems']); // edit items on an existing pending order
Route::get('/products/search', [ProductController::class, 'search']);

// Persisted cart (real customers only — see CartController)
Route::get('/cart',        [CartController::class, 'index']);
Route::post('/cart',       [CartController::class, 'upsert']);
Route::post('/cart/clear', [CartController::class, 'clear']);

Route::prefix('lead-accounts')->group(function () {
    Route::get('/',                [LeadsAccountController::class, 'index']);
    Route::post('/',               [LeadsAccountController::class, 'store']);
    Route::post('/upload-image',   [LeadsAccountController::class, 'uploadImage']);
    Route::get('/image/{filename}', [LeadsAccountController::class, 'showImage']);
    Route::get('/check-contact',   [LeadsAccountController::class, 'checkContact']); // must be before /{id}
    Route::get('/pending',         [LeadsAccountController::class, 'pendingList'])->middleware('role:admin,teleadmin'); // must be before /{id}
    Route::get('/pending-count',   [LeadsAccountController::class, 'pendingCount'])->middleware('role:admin,teleadmin'); // must be before /{id}
    Route::get('/pending-creators', [LeadsAccountController::class, 'pendingCreators'])->middleware('role:admin,teleadmin'); // must be before /{id}
    Route::post('/{id}/approve',   [LeadsAccountController::class, 'approve'])->middleware('role:admin,teleadmin');
    Route::post('/{id}/reject',    [LeadsAccountController::class, 'reject'])->middleware('role:admin,teleadmin');
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
// Tracking (Phase 1: salesman GPS ping ingest only; admin views land in later phases)
// ---------------------------------------------------------------------------
// Admin views are limited to the SALESMAN hierarchy's seniors (admin → manager
// → head/zonal/area incharge). Teleadmin sits on the telecaller branch and owns
// no salesmen, so it is deliberately NOT in this list.
Route::prefix('tracking')->middleware('jwtauth')->group(function () {
    Route::post('/ping', [TrackingController::class, 'ping']);
    Route::get('/live', [TrackingController::class, 'live'])
        ->middleware('role:admin,manager,incharge,head_incharge,zonal_incharge,area_incharge');
    Route::get('/live-route', [TrackingController::class, 'liveRoute'])
        ->middleware('role:admin,manager,incharge,head_incharge,zonal_incharge,area_incharge');
    Route::get('/route', [TrackingController::class, 'route'])
        ->middleware('role:admin,manager,incharge,head_incharge,zonal_incharge,area_incharge');
    Route::get('/roster', [TrackingController::class, 'roster'])
        ->middleware('role:admin,manager,incharge,head_incharge,zonal_incharge,area_incharge');
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
    Route::get('/my-plans',           [BeatPlanController::class, 'myPlans']);
    Route::post('/assign',            [BeatPlanController::class, 'assign']);
    Route::post('/unassign-bulk',     [BeatPlanController::class, 'unassignBulk']);
    Route::get('/today',              [BeatPlanController::class, 'today']);
    Route::get('/week',               [BeatPlanController::class, 'week']);
    Route::get('/stats',              [BeatPlanController::class, 'accountStats']);
    Route::get('/followups',                   [BeatPlanController::class, 'followups']);   // must be before /{id}
    Route::post('/followups',                   [BeatPlanController::class, 'createFollowup']);
    Route::post('/followups/{id}/done',         [BeatPlanController::class, 'markFollowupDone']);
    Route::post('/followups/{id}/reschedule',   [BeatPlanController::class, 'rescheduleFollowup']);
    Route::delete('/{id}',                      [BeatPlanController::class, 'unassign']);
});

// ---------------------------------------------------------------------------
Route::get('/call-logs',  [CallLogController::class, 'index']);
Route::post('/call-logs', [CallLogController::class, 'store']);
Route::put('/call-logs/{id}', [CallLogController::class, 'update']); // reschedule / mark done

// ---------------------------------------------------------------------------
// Complaints (hierarchy-scoped ticket tracking — see ComplaintController)
// ---------------------------------------------------------------------------
Route::middleware('jwtauth')->group(function () {
    Route::post('/complaints',                [ComplaintController::class, 'store']); // salesman-visit channel; telecaller channel goes via /call-logs
    Route::get('/complaints',                  [ComplaintController::class, 'index']);
    Route::get('/complaints/assigned-count',   [ComplaintController::class, 'assignedCount']); // must be before /complaints/{id}/* if such a route is ever added
    Route::put('/complaints/{id}/status',      [ComplaintController::class, 'updateStatus']);
    Route::put('/complaints/{id}/assign',      [ComplaintController::class, 'assign']);
});

// ---------------------------------------------------------------------------
// Telecaller dashboard + agent modules (live data, scoped to JWT mobile)
// ---------------------------------------------------------------------------
Route::prefix('telecaller')->group(function () {
    Route::get('/dashboard',    [TelecallerController::class, 'dashboard']);
    Route::get('/callbacks',    [TelecallerController::class, 'callbacks']);
    Route::get('/call-history', [TelecallerController::class, 'callHistory']);
    // Hierarchy-scoped: admin sees everyone, a teleadmin/incharge sees their
    // own descendants — never a flat unscoped dump.
    //
    // Limited to the TELECALLER hierarchy's seniors (admin → manager →
    // head/zonal incharge → teleadmin). area_incharge owns salesmen only and is
    // deliberately NOT in this list — the mirror image of the tracking routes
    // above, which exclude teleadmin. head_incharge/zonal_incharge sit above
    // BOTH branches, so they keep access to both modules.
    Route::get('/team-call-history', [TelecallerController::class, 'teamCallHistory'])
        ->middleware('role:admin,manager,incharge,head_incharge,zonal_incharge,teleadmin');
    // Roster that fronts the module: the working telecallers under this viewer
    // with their call stats. Same scope + same role list as team-call-history.
    Route::get('/team-agents', [TelecallerController::class, 'teamAgents'])
        ->middleware('role:admin,manager,incharge,head_incharge,zonal_incharge,teleadmin');
    Route::get('/call-status/{id}', [TelecallerController::class, 'callStatus']);
    // Not role-restricted at the route level: serves both a telecaller's own
    // recordings and a senior's team view — canAccessCallLog() inside does the
    // actual authorization per-recording.
    Route::get('/call-recording/{id}', [TelecallerController::class, 'callRecording']);
    Route::get('/worklist',     [TelecallerController::class, 'worklist']);
    Route::post('/label',       [TelecallerController::class, 'setLabel']);

    Route::get('/scripts',         [CallScriptController::class, 'index']);
    Route::post('/scripts',        [CallScriptController::class, 'store']);
    Route::put('/scripts/{id}',    [CallScriptController::class, 'update']);
    Route::delete('/scripts/{id}', [CallScriptController::class, 'destroy']);

    // Knowlarity click-to-call bridge (agent's own number <-> customer number)
    Route::middleware('jwtauth')->post('/call', [KnowlarityCallController::class, 'store']);
});

// ---------------------------------------------------------------------------
// Knowlarity webhooks (inbound from Knowlarity - no CRM auth, secret-protected)
// Register this exact URL in the SuperReceptionist account:
//   Resources > Hook APIs > Call Data Post API -> https://yourcrm.com/api/webhooks/knowlarity/{secret}/call-completed
// (this file is mounted under /api - see bootstrap/app.php)
// ---------------------------------------------------------------------------
Route::post('/webhooks/knowlarity/{secret}/call-completed', [KnowlarityWebhookController::class, 'callCompleted']);

// ---------------------------------------------------------------------------
// Action Log (was Order Funnel) — check-out form for the unified visit screen
// ---------------------------------------------------------------------------
Route::prefix('action-log')->group(function () {
    Route::get('/stages',       [ActionLogController::class, 'stages']);
    Route::get('/response',     [ActionLogController::class, 'latestResponse']);
    Route::get('/responses',    [ActionLogController::class, 'responses']);
    Route::post('/response',    [ActionLogController::class, 'store']);
    Route::post('/upload-image',[ActionLogController::class, 'uploadImage']);
});

// ---------------------------------------------------------------------------
// Per-customer history for the unified visit screen (all staff, one account)
// ---------------------------------------------------------------------------
Route::prefix('accounts/{accountId}')->middleware('jwtauth')->group(function () {
    Route::get('/action-logs',            [AccountHistoryController::class, 'actionLogs']);
    Route::get('/call-history',            [AccountHistoryController::class, 'callHistory']);
    Route::get('/call-recording/{id}',    [AccountHistoryController::class, 'callRecording']);
    Route::get('/ledger',                 [AccountHistoryController::class, 'ledger']);
});

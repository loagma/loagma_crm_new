# Loagma CRM: Production-Readiness Audit

**Date:** 2026-10-03
**Scope:**
- Laravel API (`server/`): all 29 controllers, the services, the job, the models and the routes.
- Flutter app (`client/lib` + Android/iOS config).
- Dev DB (TiDB) vs prod DB (`updated-loagma-structure.sql`, MariaDB 10.11).

**Deliverables:**
- `changes.sql` (repo root). Run it on prod.
- The code fixes listed in this report.
- This document.

---

## 1. Summary

| Area | Before | After |
|---|---|---|
| API authentication | ~100 of 143 routes were **public**. Anyone on the internet could create admins, read every order and customer, edit orders, rewrite the reporting hierarchy, etc. | Every route needs a valid JWT, except login, health, the pincode lookup, lead images and the Knowlarity webhook. Admin-only writes are role-gated. |
| Prod DB compatibility | 21 CRM tables and 12 columns missing on prod. Several CRM writes would fail on prod-only constraints (NOT NULL, UNSIGNED, latin1). | `changes.sql` adds everything. Code fixed for the prod-only constraints. **Verified by running the CRM's own write paths against a copy of the prod schema.** |
| Logic bugs | 12 confirmed: wrong auto punch-out, call outcomes overwritten, inbound-call matching broken, beat-plan date maths, … | All 12 fixed (§4). |
| Client | Expired login not detected, GPS kept running after logout, misleading login error, iOS crash on camera, Android reminders never fired. | Fixed (§5). Store-release items are listed for you (§7). |

---

## 2. Deploying to prod: checklist

1. **Back up the prod DB.**
2. **Run `changes.sql`** in phpMyAdmin (prod DB → SQL tab). It is idempotent (safe to run twice) and only *adds* things: no drops, renames or changes to existing columns.
3. **Do NOT run `php artisan migrate` on prod.** `changes.sql` replaces it. Several migrations would fail there or touch shared tables, e.g. prod already has `orders.Bill_Narration`. The `server/Dockerfile` runs `migrate --force` on start-up, so don't use it against prod as-is.
4. **Server `.env` on prod:**
   ```
   APP_ENV=production
   APP_DEBUG=false            # true leaks stack traces + SQL to every client
   APP_URL=https://<your-api-domain>
   DB_CONNECTION=mysql
   DB_HOST=localhost          # prod MariaDB
   DB_PORT=3306
   DB_DATABASE=loagma_new
   DB_USERNAME=...
   DB_PASSWORD=...
   # REMOVE the TiDB-only lines: DB_SSL_MODE, DB_SSL_VERIFY_SERVER_CERT, DB_SSL_CA, MYSQL_ATTR_SSL_CA
   JWT_SECRET=...             # generate a NEW one for prod (php artisan jwt:secret)
   CACHE_STORE=file
   SESSION_DRIVER=file
   QUEUE_CONNECTION=sync      # changes.sql does not create cache/jobs/sessions tables
   LOG_LEVEL=warning
   KNOWLARITY_SR_API_KEY=... / KNOWLARITY_APP_ACCESS_KEY=... / KNOWLARITY_SR_NUMBER=...
   KNOWLARITY_WEBHOOK_SECRET=<long random string>
   ```
   The current dev `.env` also holds Twilio, Redis and Mapbox credentials that the CRM code doesn't use. Don't copy them to prod. Rotate them if that file has ever been shared.
5. **Run once on the server:** `php artisan storage:link` (attendance and visit photos are served from `/storage/...`), then `php artisan config:cache` and `php artisan route:cache`.
6. **Cron:** `* * * * * cd /path/to/server && php artisan schedule:run >> /dev/null 2>&1`. This runs the hourly Knowlarity reconcile.
7. **Writable dirs:** `storage/` and `bootstrap/cache/`.
8. **Knowlarity webhook URL:** `https://<api-domain>/api/webhooks/knowlarity/<KNOWLARITY_WEBHOOK_SECRET>/call-completed`.
9. **Client:** point `client/lib/services/api_config.dart` (`_productionUrl`) at the prod API, then rebuild.
10. **Dev DB only:** dev has the beat-plan enum bug (§4.5). Run this on dev so appointment plans work there too:
    `ALTER TABLE beat_plan_crm MODIFY frequency ENUM('weekly','monthly','n_days','specific_dates','appointment') NOT NULL;`

---

## 3. Security findings (all fixed)

| # | Severity | Finding | Where | Fix |
|---|---|---|---|---|
| S1 | **Critical** | `POST /api/employees` was public and used `firstOrNew(mobile)`. Anyone could overwrite an existing admin's or delivery driver's `role` and `password`, which is a full account takeover. `PUT /employees/{id}` and role create/delete were also public. | `routes/api.php`, `MastersController::store` | Behind JWT + `role:admin`. Create now refuses an existing mobile (422) instead of overwriting it. Edits must use PUT. |
| S2 | **Critical** | Orders: `POST /sales-orders` and `PUT /orders/{id}/items` were public and wrote to the live `orders`/`orders_item`/`master_orders`. `updateItems` could edit **any** pending order, including consumer-app orders. | `SalesOrderController` | JWT required. Item edits are allowed only on CRM orders (`txn_id` starting `CRM-`, else 403). |
| S3 | **Critical** | Data leak: `GET /orders`, `/orders/{id}`, `/orders/owner/{id}/products` and `/customers` were public. They exposed every customer's name, phone, address and order history. | `OrderListController`, `LeadsAccountController::customers` | JWT required. |
| S4 | **Critical** | Hierarchy takeover: `area-assign`, `incharge-assign` and `areas` CRUD were public. `incharge_assign_crm` decides who may approve attendance and see whose data, so rewriting it granted approval rights. | `routes/api.php` | JWT required. Writes are `role:admin`. |
| S5 | High | `admin/attendance/settings/*` (shift times, approval flag) and `admin/attendance/{mobile}` were public. | `AttendanceController` | Settings are `role:admin`. The attendance history is visible only to admin, the employee themself, or their seniors. |
| S6 | High | Leads: index/show/update/delete were public. `update` accepted `isApproved`/`approvedById` from anyone, so a salesman could self-approve. | `LeadsAccountController` | JWT required. Review fields are ignored unless the caller is admin/teleadmin. Delete is allowed for an approver or the creator only. An unfiltered list returns only the caller's own leads for non-approvers. `per_page` is capped at 1000. |
| S7 | High | Beat plans: `assign`/`auto-distribute` accepted any `salesman_id`, even with no token. | `BeatPlanController` | JWT required. The `salesman_id` override is honoured only for admin (the app never sends it). |
| S8 | Medium | `complaints?raised_by=` / `?assigned_to=` let any user read any staff member's complaints. | `ComplaintController::index` | The filter must be yourself or someone in your team (admin: anyone). |
| S9 | Medium | Tracking live/route/roster were role-gated but **not team-scoped**. Any area incharge could watch every salesman's live location. | `TrackingController` | Scoped to the viewer's hierarchy subtree. Admin is unrestricted. |
| S10 | Medium | The login PIN (4 digits, static) could be brute-forced: no rate limit. | `routes/api.php` | `verify-otp` throttled to 5 tries/min per mobile+IP. Login logic is otherwise unchanged, as you asked. |
| S11 | Medium | Error responses leaked internals: the BeatPlan endpoints returned raw SQL errors, `/health` returned the DB connection error, and `APP_DEBUG=true` returns stack traces. | `BeatPlanController`, `HealthController` | Generic messages with details logged server-side. Set `APP_DEBUG=false` (§2). |
| S12 | Low | Upload endpoints (attendance/lead/visit photos) were public, which allowed storage abuse. | routes | JWT required. |

**Still public by design:** `POST /auth/send-otp`, `POST /auth/verify-otp`, `GET /health`, `GET /utils/pincode/{pin}`, `POST /webhooks/knowlarity/{secret}/...` (secret-checked) and `GET /lead-accounts/image/{file}`. The app loads lead images with no auth header, and the filenames are random UUIDs.

---

## 4. Bugs found and fixed

| # | Severity | Bug | Fix |
|---|---|---|---|
| 4.1 | **High** | **Wrong auto punch-out.** Opening the Live Salesmen screen auto-closed any shift with no GPS pings for 6 h, setting `punch_out_time` = shift end (often *in the future*). Telecallers and web users (no background GPS) were force-punched-out mid-day and then couldn't punch out. | `TrackingController::autoCloseStaleShifts` now closes only shifts left open from earlier days, or today's shifts whose tracking was alive and then went silent. Punch-out is never later than now. |
| 4.2 | **High** | **Call outcomes overwritten.** The Knowlarity handler re-runs on every call-status poll and on the hourly reconcile. It replaced the outcome the telecaller chose (callback/complaint) with "answered". | `ProcessKnowlarityCallCompleted` sets the outcome only while the call is still `pending`. Duration and recording still refresh. Verified. |
| 4.3 | **High** | **Inbound call matching broken.** Phone numbers were normalised with `ltrim($digits, '91')`, which strips *every* leading 9 and 1, so 98xxxxxxxx became 8xxxxxxxx. Almost no inbound call matched its customer or agent. | Uses the last 10 digits. Verified. |
| 4.4 | High | An unknown Knowlarity status was written straight into the `call_outcome` ENUM, so the DB error lost the call. | Unknown → `invalid`. |
| 4.5 | **High** | **Appointment beat plans can't be saved on dev.** Migration order removed `'appointment'` from the `beat_plan_crm.frequency` enum. | `changes.sql` creates the enum correctly on prod. Dev needs the ALTER in §2.10. |
| 4.6 | High | **Beat-plan date maths (Carbon 3).** `diffInDays()` is now signed, so the alternate-week parity was wrong and n-day plans "fired" before their start date. The week summary disagreed with the Today list. | `BeatPlan::firesOn` and the SQL `dayFiringQuery` now use the same rule. **Verified identical over 28 days × 1,895 live plans.** |
| 4.7 | High | **Empty product catalog on prod.** Prod `deli_staff.admin_id` defaults to `0`, which the code treated as "vendor #0", so it found no products. | `admin_id <= 0` means "no vendor filter". Verified on the prod schema. |
| 4.8 | High | **Order creation fails on prod** when a discount exceeds the subtotal: `order_total` is UNSIGNED on prod. Negative prices and fractional quantities were also accepted; `quantity` is an integer column, so 1.5 was stored as 2 while being charged as 1.5. | The total clamps to ≥ 0. Negative price/discount/delivery → 422. A fractional quantity → 422 "must be a whole number". |
| 4.9 | High | **Employee create/edit fails on prod**: `admin_id`/`is_locked` are NOT NULL there, and the form sends null. | null → 0. |
| 4.10 | High | **Non-English text crashes prod writes.** Prod `user` and `deli_staff` are **latin1**. Approving a lead with a Hindi shop name, or saving an employee with a Hindi name, returned a 500. | A clear 422 asks for English characters. (To support Hindi there, see §7.) |
| 4.11 | Medium | Order-draft rows on the shared `cart` table used the real customer id as `userid`, so they could show up in that customer's consumer-app cart. | `userid = 0` (the account is kept in `account_ref`). |
| 4.12 | Medium | Ledger aging used the wrong date: the `start_time` epoch was parsed as a date string. | `Carbon::createFromTimestamp`. |
| 4.13 | Medium | Two leads created at the same moment could get the same `accountCode`, a unique-key 500. | Retry up to 5 times. |
| 4.14 | Medium | Approved customers got `register_date = 0`: the field wasn't fillable. | Set to now. |
| 4.15 | Medium | Customer-assign list returned a 500 if an assigned customer had been deleted. | Null-safe. |
| 4.16 | Medium | Creating an allocation plan with many new pincodes geocoded each one in the request (1.1 s each), which would exceed PHP's time limit. | At most 15 lookups per request. The rest are located on later requests; they're already handled as "unlocated". |
| 4.17 | Low | Telecaller report: a bad `from`/`to` date gave a 500. Durations and range-days were sent as floats (`125.0`). | Validated, and cast to int. |
| 4.18 | Low | `payment_collected` was serialised as a string (`"150.00"`), which crashed the app's `as num` reads. | Cast to float. |
| 4.19 | Low | A missing `KNOWLARITY_*` env var made every controller that injects the service crash. | Null-safe. |
| 4.20 | Low | Unbounded `per_page` on several list endpoints. | Capped. |

---

## 5. Client fixes

| Issue | Fix |
|---|---|
| An expired or invalid token (30-day TTL) left users "logged in" on empty screens. | The splash screen checks the token once (`ApiService.validateSession`). It logs out only on an explicit 401, never when offline. |
| GPS tracking kept running after logout. | `UserService.logout()` stops tracking first. That covers all logout paths. |
| The login screen said "Phone number not found" for timeouts and server errors. | It now says "Couldn't reach the server…". |
| Login parsing used hard casts (`as int`/`as String`). | Tolerant parsing. The unused dev fake-login (`dev_token`) was removed. |
| `setState` after `await` without a `mounted` check. | Guarded in employee create, allotted accounts, verify leads, area assign, and order detail. |
| **iOS:** no camera/photo-library usage strings, so the app crashed when taking a photo. | Added `NSCameraUsageDescription` and `NSPhotoLibraryUsageDescription`. |
| **Android:** follow-up reminders never fired (the notification receivers weren't declared). `USE_EXACT_ALARM` (Play-restricted) was requested but unused. | Receivers added. Both exact-alarm permissions removed; reminders are scheduled inexact. |

`flutter analyze`: 0 errors, and the same 196 info/warning items as before the changes (all pre-existing).

---

## 6. What `changes.sql` does

- **Creates 21 tables:**
  - `LeadsAccount_crm`, `action_log_crm`, `action_log_stage_crm`
  - `area_crm`, `area_assign_crm`, `attendance_crm`
  - `beat_plan_crm`, `beat_plan_followup_crm`
  - `call_log_crm`, `call_scripts_crm`, `complaint_crm`, `customer_assign_crm`
  - `incharge_assign_crm`, `language_crm`, `location_pings_crm`, `pincode_geo_crm`
  - `role_crm`, `target_crm`
  - `tc_allocation_plan_crm`, `tc_allocation_item_crm`
  - `telecaller_label_crm`

  They are generated from the dev DB's real definitions (indexes included), converted to MariaDB syntax, utf8mb4.
- **Adds columns** (all nullable or defaulted, so the other apps are unaffected):
  - `deli_staff`: `pincode`, `city`, `language`, `punch_in_time`, `punch_out_time`, `grace_minutes`, `approval_required`.
  - `user`: `lead_account_id`.
  - `cart`: `staff_id`, `account_ref`, `account_type`, `draft_payload` + unique key `cart_crm_draft_unique`.
- **Required master rows** (`INSERT IGNORE`). The app doesn't work without these:
  - 9 roles.
  - 8 check-out stages (the salesman check-out validates against them).
  - 29 languages.
- **Not added (not used by CRM code):**
  - dev's `deli_staff.otp`/`otp_expires_at`
  - `user.party_code` (only read with a fallback)
  - `units_master.dimension`/`base_unit_name`

**Verified:**
- Loaded the prod structure into a scratch MariaDB, then ran `changes.sql` twice: no errors, no duplicate rows.
- A re-diff against dev shows no missing table or column that the CRM uses.
- Then ran 21 real API write flows against that prod-schema copy, all passing:
  - create/edit employee
  - attendance settings and punch-in
  - lead create, approve → `user` row
  - appointment beat plan
  - order draft on `cart`
  - sales order + item edit
  - consumer order protected
  - catalog search
  - call log + follow-up

---

## 7. Needs your decision / action (not changed)

| Item | Why it matters | Suggestion |
|---|---|---|
| **Android `applicationId com.example.client`** + release builds **signed with the debug key** | Google Play rejects `com.example.*`, and the id can't be changed after publishing. Debug-signed builds can't be published or updated safely. | Choose a real id (e.g. `com.loagma.crm`) and create an upload keystore *before* the first store release. Changing the id means existing installs need a reinstall. |
| Version numbers disagree | pubspec `1.0.0+1`, installer `1.0.10`, drawer text "Version 1.0.0". | Set pubspec to the real version and bump `+build` every release. |
| Login PIN is plain text and static (shared `deli_staff.password`) | Kept as you asked. The rate limit now blocks brute force. | Later: real SMS OTP, or hashed PINs (needs the delivery app to agree, since the column is shared). |
| Prod `user`/`deli_staff` are **latin1** | Hindi names can't be stored there. The CRM now shows a clear message instead of crashing. | If you need Hindi: `ALTER TABLE ... CONVERT TO CHARACTER SET utf8mb4`. That's a shared-table change, so coordinate with the consumer and delivery apps first. |
| 173 `print()` calls in the app log full API responses (customer PII) | Visible in logcat and the browser console in release builds. | Wrap them in `if (kDebugMode)` or switch to a logger. |
| The JWT is passed as `?token=` for call-recording downloads | The token ends up in browser history and server logs. | Acceptable for now. Later, use a short-lived signed URL. |
| Token stored in `shared_preferences` (`localStorage` on web) | Readable by any XSS on the web build. | Consider `flutter_secure_storage` for mobile. |
| OpenStreetMap tiles fetched directly (`tile.openstreetmap.org`) | OSM's usage policy discourages production traffic. | Use a tile provider (MapTiler, Mapbox, etc.) at scale. |
| `/masters/units` fails **on dev only** | Dev's `units_master` lacks the `serial_no` column, which prod has. | Nothing needed for prod. |
| Lead read access | Any staff member can still read leads in the areas they filter by. That's needed for the Allotted Accounts screen. | Fine for now. Tighten if leads become sensitive. |

---

## 8. Files changed

**Server:**
- `routes/api.php`
- `app/Providers/AppServiceProvider.php`
- `app/Support/Latin1.php` (new)
- `app/Support/PincodeGeocoder.php`
- `app/Services/KnowlarityService.php`
- `app/Jobs/ProcessKnowlarityCallCompleted.php`
- Models: `BeatPlan`, `ActionLog`, `UserCustomer`
- Controllers: `AccountHistory`, `Attendance`, `BeatPlan`, `Complaint`, `CustomerAssign`, `Health`, `LeadsAccount`, `Masters`, `Product`, `SalesOrder`, `SalesOrderDraft`, `TeamReport`, `TelecallerReport`, `Tracking`

**Client:**
- `lib/services/user_service.dart`, `lib/services/api_service.dart`
- `lib/screens/auth/splash_screen.dart`, `lib/screens/auth/login_screen.dart`
- 5 screens (mounted guards)
- `android/app/src/main/AndroidManifest.xml`
- `ios/Runner/Info.plist`

**New:** `changes.sql`, `docs/PRODUCTION_AUDIT.md`

**Not committed:** nothing has been committed yet; review the diff and commit when ready.

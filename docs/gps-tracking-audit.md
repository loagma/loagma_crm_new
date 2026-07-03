# Loagma CRM — GPS Live-Tracking + Attendance Module Audit

Investigation only, no code changed. Repo root: `e:\A project\ADRS all\loagma_crm_new`

---

## 1. Stack & structure

**Backend**: Laravel **^12.0**, PHP **^8.2** (composer.json requires `php: ^8.2`; COMMANDS.md confirms PHP 8.2.31 in dev). Auth package: `tymon/jwt-auth ^2.3`. Lives in `server/`, a standard Laravel skeleton (`laravel/laravel` scaffold), not CodeIgniter or plain PHP.

**Flutter**: SDK constraint `^3.10.8` (pubspec.yaml); COMMANDS.md records the dev machine's installed Flutter as **3.41.0**. **ONE app**, not separate admin/employee apps — single Flutter project at `client/` with role-based routing (see §2). `lib/screens/` has `admin/`, `employee/`, `telecaller/`, `marketing/`, `lead/`, `auth/`, `dashboard/` subfolders inside the same app, gated by `role_guard.dart`.

**Database**: MySQL, specifically **TiDB Cloud** (MySQL-wire-compatible), confirmed by `server/.env`:
```
DB_CONNECTION=mysql
DB_HOST=gateway01.ap-southeast-1.prod.aws.tidbcloud.com
DB_PORT=4000
DB_DATABASE=loagma_new
DB_SSL_MODE=required
DB_SSL_CA="E:/A project/ADRS all/loagma_crm_new/server/storage/certs/isrgrootx1.pem"
```
Not Postgres/Neon. TLS is required with a CA bundle.

**Hosting**: Backend is containerized (`server/Dockerfile`, PHP 8.2 + Apache) and deployed to **Render** — `ApiConfig._productionUrl = 'https://loagma-crm-new-1.onrender.com'` (client/lib/services/api_config.dart). The repo's `render.yaml` at root only declares the **Flutter web** static site (`rootDir: client`, `env: static`); there is no backend service block in `render.yaml`, so the Laravel/Docker service on Render is configured directly in the Render dashboard, not in-repo. DB lives on TiDB Cloud (managed, ap-southeast-1), not on Render.

**Top-level folder tree (2 levels):**

Backend (`server/`):
```
server/
├── app/
│   ├── Http/ (Controllers/, Controllers/Auth/, Middleware/)
│   ├── Models/
│   └── Providers/
├── bootstrap/
├── config/
├── database/ (migrations/, factories/, seeders/)
├── public/
├── resources/
├── routes/ (api.php, web.php, console.php)
├── storage/
├── tests/
└── vendor/
```

Flutter (`client/`):
```
client/
├── android/
├── ios/
├── lib/
│   ├── router/
│   ├── screens/ (admin/, auth/, dashboard/, employee/, lead/, marketing/, telecaller/)
│   ├── services/
│   └── widgets/
├── linux/ macos/ windows/ web/  (unused desktop/web scaffolds)
└── test/
```

---

## 2. Auth (critical — tracking rides on this)

**Login mechanism**: OTP-based login issuing a **JWT** via `tymon/jwt-auth`. Flow:
- `POST /api/auth/send-otp` → `OtpAuthController::sendOtp` generates a 4-digit OTP, stores it on the staff row, logs it (no SMS gateway wired despite Twilio creds sitting unused in `.env`).
- `POST /api/auth/verify-otp` → `OtpAuthController::verifyOtp` checks the OTP (or a **master OTP `5555`**, from `.env` `MASTER_OTP=5555`, hardcoded also as `OtpAuthController::MASTER_OTP`), then issues a token: `$token = JWTAuth::fromUser($staff);`
- Guard config (`server/config/auth.php`): `'api' => ['driver' => 'jwt', 'provider' => 'deli_staff']` — the JWT provider model is `DeliStaff`, **not** Laravel's default `User`.

**Where the token is stored on Flutter**: `shared_preferences`, key **`'token'`** (`client/lib/services/user_service.dart`, `UserService._keyToken = 'token'`). Also stored: `user_id`, `user_name`, `user_mobile`, `user_role`. Restored via `UserService.init()` at app startup.

**How current user is resolved server-side**: Not via `Auth::user()`/`$request->user()` (session guard isn't used for API). Every controller instead calls `JWTAuth::parseToken()->authenticate()` directly, e.g. `AttendanceController::authMobile()`:
```php
private function authMobile(): string
{
    return JWTAuth::parseToken()->authenticate()->mobile;
}
```
The `jwt.auth` middleware (`app/Http/Middleware/JwtAuthenticate.php`) exists and is registered as an alias in `bootstrap/app.php`, but **most routes don't use it** — only `/api/auth/me` and `/api/auth/logout` are wrapped in `Route::middleware('jwt.auth')`. Every other route (including all of `attendance/*`, `beat-plan/*`, `telecaller/*`) is unprotected at the routing layer; the controllers self-authenticate by calling `JWTAuth::parseToken()->authenticate()` inline, which throws if there's no valid token but returns a raw exception (500), not a clean 401, unless the controller catches it.

**Role system**: Yes — column-based, not a package like spatie/permission.
- `deli_staff.role` — a plain `string(50)` column (migration `2026_05_01_000000_create_deli_staff_table.php`), free text, not an enum in the DB.
- Canonical values come from a separate lookup table **`role_crm`** (`app/Models/RoleCrm.php`, table `role_crm`, column `role_name`), seeded in `2026_05_28_000001_create_role_crm_table.php`:
  ```
  admin, manager, salesman, telecaller, incharge, head_incharge
  ```
  (`teleadmin` added later, `2026_06_22_000001_seed_teleadmin_role.php`; `zonal`/`area` incharge variants seeded in `2026_06_13_000001_seed_zonal_area_incharge_roles.php`.)
- Enforcement: `CheckRole` middleware (`app/Http/Middleware/CheckRole.php`, aliased as `'role'`) does `JWTAuth::parseToken()->authenticate()` then `in_array($staff->role, $roles, true)` — **but it is not attached to any route** in `routes/api.php`. Role checks that do happen are done ad hoc inside controllers (e.g. `AttendanceController::authorizeApproval()` checks `strtolower($approver->role ?? '') === 'admin'`) and client-side (`role_guard.dart` in Flutter, which only guards navigation, not the API).
- Client-side: `UserService.currentRole`, persisted from the login response's `data.role`.

---

## 3. Existing user/employee model

Full schema of `deli_staff` (base migration + all subsequent `ALTER` migrations, in order):

| Column | Type | Notes |
|---|---|---|
| `deli_id` | `unsignedBigInteger`, autoincrement | not the PK |
| `mobile` | `string(20)` | **primary key**, non-incrementing string PK |
| `name` | `string(255)` | |
| `role` | `string(50)`, nullable | free text, see §2 |
| `pincode` | `string(20)`, nullable | |
| `city` | `string(100)`, nullable | |
| `state` | `string(100)`, nullable | |
| `lat` | `decimal(10,7)`, nullable | added `2026_05_23…`; **already exists for a static "home/base" location, not live tracking** |
| `lng` | `decimal(10,7)`, nullable | same migration |
| `password` | `string`, nullable | added same migration, unused by OTP login flow |
| `admin_id` | `unsignedBigInteger`, nullable | added same migration, links staff to the admin/tenant who created them |
| `is_locked` | `boolean`, default false | |
| `sess_id` | `string`, nullable | |
| `location_last_updated` | `datetime`, nullable | in base migration; cast to `datetime` in the model but **no code anywhere writes to it** (grep found none) |
| `otp`, `otp_expires_at` | added `2026_05_11…` | |
| `punch_in_time`, `punch_out_time` | `time`, defaults `09:00:00`/`18:00:00` | added `2026_05_27_000002…`, per-employee shift schedule |
| `grace_minutes` | `integer`, default 15 | same migration |
| `approval_required` | `boolean`, default true | added `2026_05_30…` |

Notable: **no `created_at`/`updated_at`** — `$timestamps = false` in the model. No `email`. No soft deletes.

Model: `server/app/Models/DeliStaff.php` — `extends Authenticatable implements JWTSubject`. `getJWTCustomClaims()` embeds `role` in the JWT. No `hasMany`/`belongsTo` relationships defined on `DeliStaff` itself (the inverse relation, `Attendance::employee()`, lives on the `Attendance` model pointing back via `employee_mobile ↔ mobile`).

There is also a legacy Laravel `users` table (default scaffold migration) and a separate `user` table (customer-facing, per `TABLES.md`) — both explicitly called out as legacy/mostly-unused. **`deli_staff` is the real employee/staff table** and the one any tracking/attendance work should hang off.

---

## 4. Anything location/map/attendance-related already

**This is the single most important finding: a full punch-in/punch-out attendance system already exists.** It is NOT a stub — it's production code with approval workflows, shift settings, and history.

**Backend:**
- Table `attendance_crm` (model `App\Models\Attendance`, `app/Models/Attendance.php`), migrations `2026_05_27_000001` → `2026_06_01`. Columns: `employee_mobile`, `date`, `punch_in_time`, `punch_out_time`, `punch_in_photo`, `punch_in_location` (JSON `{lat,lng}`), `punch_out_photo`, `punch_out_location` (JSON), `break_details` (JSON array of `{type,start,end}`), `total_work_minutes`, `total_break_minutes`, `is_late`, `is_early_out`, `is_early_in`, `late_reason`, `early_out_reason`, `early_in_reason`, `status` (enum `on_time|pending|approved|rejected`), `admin_notes`, `approved_by`, `approved_at`. Unique constraint on `(employee_mobile, date)` — one row per employee per day.
- `AttendanceController` (`app/Http/Controllers/AttendanceController.php`, 508 lines) implements: `uploadPhoto`, `punchIn`, `punchOut`, `confirmPunch` (post-approval re-confirm with fresh photo/location), `updateBreak` (tea/lunch/emergency, start/end), `today`, `myHistory`, plus admin-side `pendingList`, `pendingCount`, `approve`, `reject`, `getSettings`/`updateSettings` (per-employee shift config), `adminEmployeeAttendance` (calendar view). Includes a recursive incharge-hierarchy walk (`getDescendantMobiles`) so any manager in the chain can approve subordinates' attendance.
- **This captures location only as a single point-in-time snapshot at punch-in and punch-out** (`punch_in_location`/`punch_out_location` JSON `{lat,lng}`), not a continuous track. There is no `location_pings`/`gps_log`/similar table.

**Flutter:**
- Punch-in/out UI and logic live in `client/lib/widgets/app_drawer.dart` (a shared drawer widget, not a dedicated screen) — `_captureLocation()` does a single `Geolocator.getCurrentPosition()` call (best-effort, swallowed on error), attached to the punch API calls (`ApiService.punchIn/punchOut/confirmPunch`, `api_service.dart` lines ~890–970). This is a **one-shot GPS read at the moment of the button tap**, not a background/continuous tracker.
- Admin-side attendance screens: `lib/screens/admin/attendance_employee_screen.dart`, `attendance_manage_screen.dart`, `attendance_settings_screen.dart`.
- `Geolocator` is also used one-shot elsewhere: `employee_create_screen.dart` (capturing an employee's home lat/lng at creation — matches `deli_staff.lat/lng`), `lead_account_screen.dart` (capturing a lead's location).

**Map packages**: **NOT PRESENT** in `pubspec.yaml` — no `google_maps_flutter`, `flutter_map`, or `mapbox_gl` dependency, despite the backend `.env` holding both `GOOGLE_MAPS_API_KEY` and `MAPBOX_ACCESS_TOKEN`. Those keys are currently unused by any code found — they look like they were provisioned ahead of a mapping feature that was never built.

**Location packages**: `geolocator: ^13.0.2` present and used (one-shot only, see above). No `location`, no `flutter_background_service`, no `workmanager`, no `background_locator` — **NOT PRESENT**. Nothing capable of continuous/background GPS tracking exists today.

**Suspicious pre-provisioned infra for live tracking** (present but **unused by any application code** — grep of `app/` found zero references outside `.env`):
```
REDIS_ENABLED=true
REDIS_URL=redis://default:...@redis-16979...redislabs.com:16979
# Redis cache for tracking latest-location fanout        <- literal comment in .env
WS_PORT=8081
```
This strongly suggests someone already scoped a Redis-backed "latest location" pub/sub + WebSocket design for this exact feature, but never implemented it. Worth asking the user/team if there's a spec or prior attempt to recover, since the intended architecture (Redis fanout + WS) may already be decided.

**AndroidManifest.xml permissions** (`client/android/app/src/main/AndroidManifest.xml`):
```
INTERNET, POST_NOTIFICATIONS, RECEIVE_BOOT_COMPLETED, VIBRATE,
SCHEDULE_EXACT_ALARM, USE_EXACT_ALARM, CAMERA,
ACCESS_COARSE_LOCATION, ACCESS_FINE_LOCATION
```
No `ACCESS_BACKGROUND_LOCATION`, no foreground-service permissions (`FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_LOCATION`) — all required additions for continuous background tracking on modern Android.

**iOS Info.plist** (`client/ios/Runner/Info.plist`): **NOT PRESENT** — no `NSLocationWhenInUseUsageDescription`, `NSLocationAlwaysAndWhenInUseUsageDescription`, or `NSLocationAlwaysUsageDescription` keys at all. Location requests will silently fail/crash on iOS until these are added (background tracking additionally needs the `location` UIBackgroundMode).

---

## 5. API conventions (so new endpoints match)

**Base URL / route prefix**: No `/api/v1` versioning — flat `/api/*` (Laravel's default `api` route file prefix, wired in `bootstrap/app.php` via `withRouting(api: __DIR__.'/../routes/api.php', ...)`, which auto-prefixes `/api`). `routes/api.php` organizes by `Route::prefix('...')->group(...)` per feature: `auth`, `lead-accounts`, `areas`, `attendance` (+ `admin/attendance`), `area-assign`, `incharge-assign`, `beat-plan`, `telecaller`, `order-funnels`, plus a few flat top-level routes (`/employees`, `/customers`, `/call-logs`, `/masters/roles`).

**Standard JSON response shape** — consistent across controllers, hand-rolled (no API Resource classes), always `response()->json([...])`:
```php
// success, single record
return response()->json(['success' => true, 'data' => $record], 201);

// success, paginated
return response()->json([
    'success' => true,
    'data'    => $p->items(),
    'meta'    => [
        'current_page' => $p->currentPage(),
        'last_page'    => $p->lastPage(),
        'per_page'     => $p->perPage(),
        'total'        => $p->total(),
    ],
]);

// failure
return response()->json(['success' => false, 'message' => 'Already punched in today'], 422);
```
New tracking/attendance endpoints should follow this exact `{success, data|message, meta?}` shape — it's the de facto contract the Flutter `ApiService` already parses against (see `getRoles()`/`getEmployees()` checking `decoded['data']`).

**Validation**: Inline `$request->validate([...])` per method (no Form Request classes anywhere). Errors surface as Laravel's default 422 with a `message`/`errors` structure from the validator (not the hand-rolled `success/message` shape) when validation fails — i.e. validation-failure responses are inconsistent with the app's normal success/failure envelope. Manual checks are also used ad hoc (e.g. `punchIn` manually checks for an existing record and returns a hand-rolled 422).

**Pagination**: Laravel's built-in `->paginate($perPage, ['*'], 'page', $page)`, with `per_page`/`page` query params, reflected into the `meta` block shown above. Used in `myHistory`, `pendingList`, `adminEmployeeAttendance`.

**Base API controller / response helper**: `app/Http/Controllers/Controller.php` is an **empty abstract class** (`abstract class Controller {}`) — NOT PRESENT: no shared response-helper trait, no base API controller with `success()`/`error()` methods. Every controller repeats the `response()->json([...])` boilerplate by hand.

---

## 6. Flutter networking conventions

**HTTP client**: `package:http` (`http: ^1.2.2`), not `dio`. Central class: `client/lib/services/api_service.dart` (1422 lines, all-static methods, one per endpoint — e.g. `ApiService.punchIn(...)`, `ApiService.getEmployees(...)`).

**Base URL config**: `client/lib/services/api_config.dart`. A compile-time `--dart-define=API_BASE_URL=...` override takes priority; otherwise a hardcoded `static const bool useProduction = true` flag switches between:
- prod: `https://loagma-crm-new-1.onrender.com`
- local: `http://10.0.2.2:8000` (Android emulator) / `http://localhost:8000` (web/desktop)

This is a manually-flipped boolean in source (`useProduction`), not an env file — anyone building locally must remember to flip it or pass `--dart-define`.

**Authenticated requests**: No interceptor — manual header construction per call via a static getter:
```dart
static Map<String, String> get _authHeaders => {
      ..._headers,
      'Authorization': 'Bearer ${UserService.token}',
    };
```
Example real call (`api_service.dart`):
```dart
static Future<Map<String, dynamic>> me() async {
  final url = Uri.parse('${ApiConfig.baseUrl}/api/auth/me');
  final response = await http
      .get(url, headers: _authHeaders)
      .timeout(const Duration(seconds: 15));
  return jsonDecode(response.body) as Map<String, dynamic>;
}
```
Retry logic (3 attempts, exponential-ish backoff) is present on some calls (`sendOtp`, `verifyOtp`) but not universal — no shared retry/interceptor wrapper.

---

## 7. Migrations & DB conventions

**Naming**: Mixed — some CRM-specific tables carry a `_crm` suffix (`attendance_crm`, `area_crm`, `beat_plan_crm`, `call_log_crm`, `role_crm`, `LeadsAccount_crm`, `order_funnel_crm`, `telecaller_label_crm`, `call_scripts_crm`) to distinguish them from Laravel's own default tables (`users`, `jobs`, `cache`) and from pre-existing legacy tables (`user`, `deli_staff` — no suffix). Columns are `snake_case` throughout. `LeadsAccount_crm` breaks the otherwise-consistent lowercase-snake convention (PascalCase table name) — worth noting if a new table needs to join against it. Migration filenames are dated (`YYYY_MM_DD_...`), one migration per schema change, heavy use of incremental `add_x_to_y_table` migrations rather than editing the original create migration.

**Seeders**: `database/seeders/DatabaseSeeder.php` and `InchargeSeeder.php` exist, but role seeding for `role_crm` is actually done inline inside migrations (`DB::table('role_crm')->insert([...])` directly in the `create_role_crm_table` migration and in the later `seed_*_roles` migrations), not through the seeder classes — an unusual but consistent pattern in this repo (use it if adding new roles/lookup data).

---

## 8. Build/run

**Backend** (from `COMMANDS.md`, using the pinned local PHP/Composer):
```
C:\Users\Dell\php82\composer.phar install --working-dir="server"
php artisan key:generate
php artisan jwt:secret
php artisan migrate
php artisan serve --host=0.0.0.0 --port=8000   # for LAN/phone testing
```
`composer.json` also defines a combined `composer dev` script that runs `php artisan serve` + `queue:listen` + `pail` (log viewer) + `npm run dev` concurrently — but this is boilerplate from the Laravel skeleton; nothing in the app actually dispatches queued jobs today (see §9).

**Flutter**:
```
flutter pub get
flutter run --dart-define=API_BASE_URL=http://10.29.126.87:8000   # physical device over LAN
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000       # Android emulator
```

**Test account / dev credentials**: No seeded demo user found in seeders. Login is OTP-based but a **master OTP bypass `5555`** works for any registered mobile (`server/.env` → `MASTER_OTP=5555`, hardcoded fallback also in `OtpAuthController::MASTER_OTP`). Any `deli_staff.mobile` already in the DB + OTP `5555` logs in. There's no self-registration endpoint — staff must be pre-created (`POST /employees` from `MastersController`, admin-only in practice though not enforced by middleware).

---

## 9. Deployment

**Backend deploy**: Docker image built from `server/Dockerfile` (PHP 8.2 + Apache), deployed to **Render** as a web service (inferred from the production URL; the Render service itself is not declared in this repo's `render.yaml`, which only covers the Flutter web static build). The Dockerfile's `CMD` runs a startup script that does `php artisan storage:link --force && php artisan migrate --force && apache2-foreground` on every boot — so migrations auto-run on deploy, but this is a single ephemeral container per Render's model, not a persistent worker fleet.

**Scheduler/cron**: **NOT PRESENT.** `routes/console.php` only defines the stock `inspire` Artisan command. There is no `app/Console/Kernel.php` (Laravel 12 moved scheduling into `bootstrap/app.php` via `->withSchedule(...)`), and `bootstrap/app.php` does **not** call `withSchedule()` — confirmed by reading the file directly. No `Schedule::` calls exist anywhere in the codebase. This means **there is currently no way to run a periodic job** (e.g. auto-closing forgotten punch-outs at midnight, pruning stale GPS pings) without first standing up Laravel's scheduler AND an external trigger to call `php artisan schedule:run` every minute — which a single-container Apache/PHP deployment on Render does not provide out of the box. Render's free/starter web services also don't include a built-in cron feature in this repo's config; a Render **Cron Job** service or **Background Worker** service would need to be added separately (and paid for) to get either a scheduler tick or a persistent queue worker.

**Queues/workers**: `QUEUE_CONNECTION=sync` in `.env` — jobs run inline, synchronously, in the same request. `config/queue.php` supports `database`/`redis`/etc. but nothing overrides the sync default in production config, and there's no worker process defined in the Dockerfile or Render config to run `queue:work` continuously even if the connection were switched. Effectively: **no background job processing today** — everything is request/response only.

---

## 10. Gaps & risks you noticed

1. **No scheduler, and the deployment model can't easily support one.** Auto-closing forgotten punch-outs, retention-pruning old GPS pings, or any "run this every N minutes" job has no home today. Adding Laravel's scheduler requires `withSchedule()` in `bootstrap/app.php` *and* an external trigger (Render Cron Job hitting `schedule:run`, or a dedicated worker service) — extra infrastructure, not just code.

2. **No queue workers in production** (`QUEUE_CONNECTION=sync`, no worker process in the Docker image). Anything that should be async (e.g., fanning out a location ping to subscribers, sending a push notification when a salesman goes off-route) will currently block the request/response cycle unless a worker is added.

3. **Most API routes are unauthenticated at the middleware layer.** `jwt.auth` is only applied to `/api/auth/me` and `/api/auth/logout`; every other route — including all attendance and (presumably) future tracking endpoints — relies on each controller manually calling `JWTAuth::parseToken()->authenticate()` and letting it throw on failure. That throw isn't uniformly caught, so an invalid/missing token can surface as a raw 500 instead of a 401 on some endpoints. A live-tracking ping endpoint hit continuously by every field employee needs to be reliably protected — this pattern should be tightened (apply `jwt.auth` middleware directly on the route group) before adding a new high-frequency endpoint.

4. **Role authorization is not centrally enforced.** The `CheckRole`/`role` middleware exists but is wired to zero routes; role checks are duplicated ad hoc per controller (string-compare on `$staff->role`, case-sensitivity handled inconsistently — sometimes `strtolower()`, sometimes not, e.g. `CheckRole` does an exact `in_array` without lowercasing while `AttendanceController::authorizeApproval` does `strtolower()`). A tracking module that needs "admin/incharge can view all live locations, salesman can only see/update their own" should not copy this ad hoc pattern — worth centralizing via the existing `role` middleware alias (already registered in `bootstrap/app.php`, just unused).

5. **No live/continuous location capability exists anywhere in the stack.** `geolocator` only ever does one-shot `getCurrentPosition()` calls tied to a button tap (punch-in, punch-out, employee creation, lead capture). There is no background service, no periodic ping, no map rendering package, and no backend table for a location time series (`attendance_crm.punch_in_location`/`punch_out_location` are single JSON points, not a track). This is a from-scratch build, not an extension of an existing tracker.

6. **Redis + WebSocket infra is provisioned but dead.** `.env` has `REDIS_ENABLED=true`, a live Redis Cloud URL with a comment "Redis cache for tracking latest-location fanout", and `WS_PORT=8081` — but nothing in `app/` uses Redis or opens a WebSocket. This looks like a half-started plan for exactly this feature. Recommend checking with the team/prior developer whether there's a design doc or partial branch for this before building a new architecture from scratch, since credentials are already paid for and provisioned.

7. **Google Maps + Mapbox API keys sit unused.** Both `GOOGLE_MAPS_API_KEY` and `MAPBOX_ACCESS_TOKEN` are in `.env` with no corresponding Flutter map package installed and no backend usage. Whichever is chosen for rendering live-location maps, the other key is dead weight (or a signal of an earlier decision reversal — worth asking).

8. **iOS location permissions are completely missing** (`Info.plist` has zero `NSLocation*` keys). Location requests will fail/crash on iOS as-is; this needs to be added regardless of tracking design, and background tracking needs the additional `UIBackgroundModes: location` entry plus `NSLocationAlwaysAndWhenInUseUsageDescription`.

9. **Android is missing background-location and foreground-service permissions.** Only `ACCESS_COARSE_LOCATION`/`ACCESS_FINE_LOCATION` are declared. Continuous tracking while the app is backgrounded (the realistic requirement for a "salesman GPS live-tracking" feature) needs `ACCESS_BACKGROUND_LOCATION` (with its own Play Store policy justification requirements) and a foreground service with `FOREGROUND_SERVICE_LOCATION`, none of which are present, plus a background-capable Flutter package (none installed — no `flutter_background_service`, `workmanager`, etc.).

10. **`deli_staff` primary key is the mobile number itself** (`string`, non-incrementing). Any new tracking table should key off `mobile` (matching `Attendance::employee_mobile`) for consistency, not off `deli_id`, since `deli_id` is an incrementing column that coexists with but is not the actual PK.

11. **Validation error responses are inconsistent with the app's normal envelope.** Laravel's default validation-failure JSON (`{message, errors}`) differs from the hand-rolled `{success, message}` shape used everywhere else. A high-traffic tracking-ping endpoint will get malformed/rapid-fire requests from the field — worth deciding up front whether to catch `ValidationException` and reshape it, or accept the inconsistency (matches existing precedent, so not a blocker, just a gap to be aware of).

12. **No base API controller or response helper.** Every controller hand-writes `response()->json([...])`. Not a blocker, but there's no existing trait to extend — a new `TrackingController` will need to copy the same by-hand pattern used everywhere else (or this would be a good moment to introduce a shared helper, at the cost of diverging from existing style).

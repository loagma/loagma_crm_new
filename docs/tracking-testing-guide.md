# GPS Tracking — How to Test Everything (Phase 2)

Test account: mobile **9876500001** (Aman Sharma, salesman) · OTP **5555** · device A069.

---

## 0. Start everything

```powershell
# Backend (from repo root) — phone connects over the iQOO hotspot
cd server
C:\Users\Dell\php82\php.exe artisan serve --host=0.0.0.0 --port=8123

# App on the phone (only needed after code changes; app is already installed)
cd client
flutter run -d 002987649002082 --dart-define=API_BASE_URL=http://10.29.126.87:8123
```

Sanity check both sides:
```powershell
curl http://127.0.0.1:8123/api/health                      # from PC
adb shell "curl -s http://10.29.126.87:8123/api/health"    # from phone
```
Both must return `{"status":"ok","database":{"status":"ok"}}`.
**If the phone one fails after switching networks:** toggle the phone's WiFi off/on — a stale WiFi state after roaming was the cause last time.

---

## 1. Salesman side (on the phone)

| What to check | How | Pass looks like |
|---|---|---|
| Punch in starts tracking | Drawer → Punch In → reason → photo | Persistent notification **"LoagmaCRM — On Duty · Recording your route"** appears |
| Tracking survives background | Press Home, lock screen, use other apps | Notification stays; pings keep arriving (see §2) |
| Punch out stops tracking | Drawer → Punch Out | Notification disappears, no new pings after |
| Session expiry | (dev-only test, see §4) | Notification changes to "Session expired — please punch in again" and tracking stops |

Movement rule: a new point is recorded roughly every **20 meters** of movement. Standing still = no new points (by design, saves battery).

---

## 2. Backend: watch pings arrive (run on the PC)

Live ping count + latest point:
```powershell
cd server
C:\Users\Dell\php82\php.exe artisan tinker --execute="
echo 'pings: ' . App\Models\LocationPing::where('employee_mobile','9876500001')->count() . PHP_EOL;
\$p = App\Models\LocationPing::where('employee_mobile','9876500001')->orderByDesc('recorded_at')->first();
if (\$p) echo 'latest: ' . \$p->lat . ',' . \$p->lng . ' heading=' . \$p->heading . ' battery=' . \$p->battery . ' at ' . \$p->recorded_at;
"
```
Open the latest point on a map: `https://maps.google.com/?q=<lat>,<lng>`

Attendance row (last_ping_at must track the newest ping; was_interrupted flips after a >5 min offline gap):
```powershell
C:\Users\Dell\php82\php.exe artisan tinker --execute="
\$a = App\Models\Attendance::where('employee_mobile','9876500001')->orderByDesc('date')->first();
echo 'in=' . \$a->punch_in_time . ' out=' . \$a->punch_out_time . ' last_ping=' . \$a->last_ping_at . ' interrupted=' . (\$a->was_interrupted?1:0);
"
```

Full trail for a day (gaps, headings, batteries):
```powershell
C:\Users\Dell\php82\php.exe artisan tinker --execute="
foreach (App\Models\LocationPing::where('employee_mobile','9876500001')->where('date','2026-07-06')->orderBy('recorded_at')->get() as \$p)
  echo \$p->recorded_at . '  ' . \$p->lat . ',' . \$p->lng . '  head=' . \$p->heading . ' bat=' . \$p->battery . ' mock=' . \$p->is_mock . PHP_EOL;
"
```

---

## 3. On-phone queue (offline buffer) — needs USB

While the phone is out of WiFi range, points pile up locally instead of uploading.
To inspect (debug build only):
```powershell
adb exec-out run-as com.example.client cat databases/tracking_queue.db > q.db
C:\Users\Dell\AppData\Local\Android\Sdk\platform-tools\sqlite3.exe q.db "SELECT COUNT(*), MIN(recorded_at), MAX(recorded_at) FROM location_queue;"
```
- Rows here + none arriving in §2 → buffering is working while offline
- After reconnecting to WiFi, this drains to 0 within ~30 s and the backend count in §2 jumps by the same amount, with **original capture timestamps** (not upload time)

The queue holds max 5,000 points and survives app reinstalls and phone restarts.

---

## 4. The offline / expiry drills

**Offline buffering (acceptance c):** punch in → walk out of WiFi range for 6–7 min → walk back → within a minute the whole backlog appears in §2, and `was_interrupted` flips to 1 (gap was >5 min).

**Session expiry (acceptance e, dev-only):** while punched in and moving, blacklist the phone's token:
```powershell
# grab the phone's JWT (debug build)
adb exec-out run-as com.example.client cat shared_prefs/FlutterSharedPreferences.xml | grep -o 'flutter.token[^<]*'
# then blacklist it
curl -X POST http://127.0.0.1:8123/api/auth/logout -H "Authorization: Bearer <TOKEN>"
```
Next upload attempt → app retries once → then stops tracking and shows the "Session expired" notification. It must NOT keep retrying forever.

---

## 5. What "all-pass" looks like (Phase 2 acceptance)

- (a) Punch in → notification → points appear in `location_pings_crm` with capture-time `recorded_at`
- (b) Points keep flowing with the app backgrounded / screen locked
- (c) Airplane/no-WiFi buffers locally, uploads in order on reconnect, nothing lost
- (d) Punch out → service + notification gone, no further inserts
- (e) Dead token → one retry → clean stop + "Session expired" notification
- (f) Real `heading` (non-zero when moving) and `battery` values on the rows

## 6. Where you'll SEE it (coming next)

- **Phase 3**: admin screen listing all on-duty salesmen (last seen, battery, 🟢/🟠)
- **Phase 4**: live map — watch the route line grow as the salesman moves
- **Phase 5**: history — pick any past day, see the full route with start/end pins

Until then, §2's queries are the only viewer.

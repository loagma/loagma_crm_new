# Telecaller Daily Allocation by Pincode Location — Context

Branch `feat/telecaller-geo-allocation` (not yet merged to `main`). Built 2026-10-01. First commit `05d6ee0`; the date-range change came after it.

A telecaller picks pincodes (or **Select All**) and a **From–To date range** on a calendar. The backend:

1. Orders the pincodes by each **pincode's own location**.
2. Builds one queue of customers and leads.
3. Divides the customers over the days. Each day's count is **remaining customers ÷ remaining days** (today through the To date), worked out again every morning.
4. Carries unfinished work forward to the next day.

The telecaller only sees "Today's Customers: N". The internal geographic clusters are never shown.

---

## 1. Business rules (agreed with the product owner)

| Rule | Decision |
|---|---|
| Pincode order | By real location, **never** by pincode number. |
| Where a pincode's location comes from | The pincode itself, looked up once from OpenStreetMap Nominatim and cached in `pincode_geo_crm`. **Customer latitude/longitude are never used**: most `user` rows hold placeholder coordinates inside one ~300 m Hyderabad block. |
| Which pincode a customer belongs to | Only its `pincode` field. |
| Order inside a pincode | Customers first, then leads, each by id. It is fixed and repeatable. |
| How many per day | **Not entered by the telecaller.** They pick From–To dates. Every calendar day counts, Sundays included, up to 366 days (`config/telecaller.php`). Each morning the count is `ceil(remaining ÷ days left)`. A slow day raises the next days' share, so the plan still ends on the To date. |
| Before the From date | No list. |
| After the To date (overdue) | Each day's list is **everything still remaining**. |
| Quota per pincode | None. A day's list can be 52+48, 75+25 or 20+30+50; the day's count just fills in queue order. |
| Carry-forward | Accounts handed out but not worked go back to *pending* at their original position. They come first the next day and are counted in the next day's split. |
| Busy / no answer / switched off | Counted as **done** for this cycle (the attempt is logged). |
| Callback outcome | Status `callback`. The existing Callbacks / follow-up flow takes it over, and it does **not** count toward the day's list. |
| Who is in the queue | `user` customers in the telecaller's area pincodes, leads in their areas, and customers directly assigned to them (`customer_assign_crm`). Accounts the telecaller labelled `do_not_call` or `wrong_number` are excluded. |
| Recently called accounts | Included (a full sweep). |
| New plan while one is active | **Merged**. The part of the walk already started stays fixed; untouched and new pincodes are ordered onward from the current position. The **From date stays fixed**; the telecaller can move the **To date** (not before today). From the next day, everything remaining is split over the remaining days. |
| When the daily list is built | On the telecaller's first request of the IST day. Days not opened still count toward the range (see section 7). |
| Beat plan (`beat_plan_crm`) | Untouched. Allocation runs alongside it. |

### Examples (unit-tested)
- **250 customers, From 5 Oct To 9 Oct (5 days):** 50 a day. If only 30 of day 1's 50 are called, 220 are left over 4 days, so days 2–5 get 55 each.
- **187 customers over 4 days:** 47, 47, 47, 46.
- **101 customers left with 2 days to go:** 51, then 50.
- **The spec's 4-day example at a fixed 100 a day.** Queue order 482001(52) → 482005(48) → 482002(75) → 482008(60) → 482020(100). Each day takes the next 100, crossing pincode boundaries:

| Day | Customers |
|---|---|
| 1 | 482001:52 + 482005:48 |
| 2 | 482002:75 + 482008:25 |
| 3 | 482008:35 + 482020:65 |
| 4 | 482020:35 |

---

## 2. Data model (3 new CRM tables; no shared table touched)

### `pincode_geo_crm`
One point per pincode.

| Column | Notes |
|---|---|
| `pincode` | Primary key, varchar(10) |
| `lat`, `lng` | double |
| `source` | `geocoded` or `manual`. The column default is `derived`, a leftover; the code always sets `source`. |
| `sample_count` | Unused, always 0 |

- **Live state (2026-10-01):** 74 rows, i.e. all pincodes in `area_crm`. 73 are `geocoded`; 1 is `manual` (500053, set to 17.33, 78.47 because Nominatim placed it about 50 km west).
- `manual` rows are never replaced by the geocoder.

### `tc_allocation_plan_crm`
A telecaller's plan.

| Column | Notes |
|---|---|
| `employee_mobile` | `deli_staff.mobile` |
| `selected_pincodes` | JSON |
| `pincode_sequence` | JSON, the ordered pincodes |
| `daily_capacity` | The **current** per-day count (`ceil(remaining ÷ days left)`), refreshed every morning by `allocateDay()`. Shown as the dashboard's daily target. Not entered by the user. |
| `start_date`, `end_date` | The From–To range. Naive IST dates, cast `date:Y-m-d`. Added by migration `2026_10_01_000004` (nullable). |
| `status` | `active`, `completed` or `cancelled` |

At most one `active` plan per telecaller. This is enforced in code, not by the database.

### `tc_allocation_item_crm`
The queue: one row per account in a plan.

| Column | Notes |
|---|---|
| `plan_id`, `employee_mobile` | |
| `account_id` | `user.userid` or the `LeadsAccount_crm` UUID |
| `account_type` | `customer` or `lead` |
| `pincode`, `pincode_rank`, `account_rank` | **Queue order = (`pincode_rank`, `account_rank`)** |
| `status` | `pending`, `assigned`, `in_progress`, `completed`, `skipped` or `callback` |
| `allocated_date` | Naive IST `date`, cast `date:Y-m-d` |
| `call_log_id`, `completed_at` | |

- Unique on (`plan_id`, `account_id`).
- "Where we stopped" is simply the lowest-ranked `pending` row. No separate cursor is stored.

Migrations: `server/database/migrations/2026_10_01_00000{1,2,3,4}_*.php` (all already run on `loagma_new`).

---

## 3. How it works

```
POST /telecaller/allocation {pincodes[], start_date, end_date}   (start_date ignored on a merge)
  ensurePincodeGeo(pincodes)       ← outside the lock; Nominatim at ~1 req/s, only for pincodes not cached yet
  ┌ transaction, active plan row locked
  │ union = old selected + new (on merge)
  │ candidates(mobile, union)      ← accounts belong to a pincode by their pincode field only
  │ sequence = merge ? mergedSequence() : sequenceFor()   (GeoSequencer)
  │ upsertQueue(rankAccounts())    ← new rows inserted as pending; existing rows only get re-ranked
  │ daily_capacity = ceil(open ÷ days from max(today, start) to end)
  └

GET /telecaller/allocation/today
  ┌ transaction, active plan row locked
  │ if today's rows already exist → return them unchanged
  │ else allocateDay():
  │   today < start_date → nothing (plan not started)
  │   assigned/in_progress from earlier days → pending (carry-forward)
  │   queueNewAccounts()   ← new customers/leads in plan pincodes, appended to their pincode
  │   skipLabelled()       ← do_not_call / wrong_number → skipped
  │   nothing pending → plan.status = completed
  │   quota = DailyAllocator::quotaFor(pending, today, start, end)
  │         = ceil(pending ÷ days from today to end), or all pending after end_date
  │   take lowest-ranked pending rows up to quota → assigned, allocated_date = today
  └

CallLog saved (manual log, action log, Knowlarity create + webhook)
  → recordCallOutcome(): the item in today's list (assigned/in_progress) gets:
      callback                                         → callback
      invalid (manual)                                 → skipped
      invalid (Knowlarity)                             → ignored (may be a provider-side rejection)
      answered/complaint/busy/no_answer/switch_off     → completed
```

**GeoSequencer** (pure, unit-tested):
1. Groups pincodes whose points are within 5 km of each other (union-find; set by `TC_ALLOCATION_CLUSTER_KM`).
2. Chains the clusters nearest-first, starting from the outermost one.
3. Within each cluster: nearest-first from where the previous cluster ended, then a 2-opt pass to remove crossings.
4. Pincodes with no location go last.
5. With a `$from` point it continues the walk from there instead of starting fresh. This is used for merges.

---

## 4. API (all routes check the JWT; the telecaller is taken from the token's mobile)

| Method | Path | Body / query | Returns |
|---|---|---|---|
| GET | `/api/telecaller/allocation` | – | Progress, or `data: null` without an active plan: `plan_id, start_date, end_date, total_days, day (0 before start), days_left, overdue, daily_capacity (current per-day), selected_pincodes, pincode_sequence, total, done, pending, status_counts, remaining_by_pincode[]` |
| POST | `/api/telecaller/allocation` | New plan: `{"pincodes":["500014",…],"start_date":"2026-10-05","end_date":"2026-10-09"}`. Merge: `{"pincodes":[…],"end_date":"…"}` | 201 + progress. Creates the plan or merges into the active one. 422 if: no callable accounts; `start_date` is before today; `end_date` is before `start_date` (or before today on a merge); or the range is over 366 days. |
| GET | `/api/telecaller/allocation/today` | – | `{plan_id, plan_status, daily_capacity, start_date, end_date, total, customers:[{item_id, account_id, account_type, allocation_status, pincode, name, business_name, person_name, phone, area, city, stage, address, latitude, longitude}]}`, in queue order |
| PATCH | `/api/telecaller/allocation/items/{id}` | `{"status":"skipped"\|"in_progress"\|"assigned"}` | Manual skip, start or undo (only for your own items that are still open or skipped) |
| DELETE | `/api/telecaller/allocation` | – | Cancels the active plan; history is kept |
| GET | `/api/pincode-geo?pincodes[]=` | admin, teleadmin | Stored points |
| PUT | `/api/pincode-geo/{pincode}` | `{"lat":17.33,"lng":78.47}` or `{"source":"geocoded"}` | Manual override, or drop the override and look the pincode up again |

The dashboard (`GET /api/telecaller/dashboard`) `daily_target` is the active plan's current per-day count, or 60 without a plan.

---

## 5. Files

**Backend (`server/`)**
- `app/Services/TelecallerAllocationService.php`: all allocation logic (create/merge, today, progress, call hook, candidates, ensuring pincode locations, enrichment).
- `app/Support/GeoSequencer.php`: proximity ordering (pure).
- `app/Support/DailyAllocator.php`: `quotaFor()` (remaining ÷ days left), `daysInclusive()` and `take()` (pure).
- `app/Support/PincodeGeocoder.php`: Nominatim pincode lookup.
- `app/Support/TelecallerScope.php`: a telecaller's areas and pincodes, with pincodes trimmed. Also used by `TelecallerController`.
- `app/Http/Controllers/TelecallerAllocationController.php`: the endpoints above, including date validation.
- `app/Models/{PincodeGeo,TcAllocationPlan,TcAllocationItem}.php`; `app/Models/CallLog.php` (`booted()` → `recordCallOutcome`).
- `app/Http/Controllers/TelecallerController.php`: `daily_target` change, plus `myAreaScope()` now delegating to `TelecallerScope`.
- `routes/api.php`: the `telecaller/allocation*` group and the `pincode-geo` group.
- `config/telecaller.php` and env keys:
  - `TC_ALLOCATION_CLUSTER_KM`, `TC_ALLOCATION_MAX_DAYS`
  - `PINCODE_GEOCODER_URL`, `PINCODE_GEOCODER_UA`, `PINCODE_GEOCODER_TIMEOUT`
  - `PINCODE_GEOCODER_CA` (defaults to `OSRM_CA`; Windows PHP needs the ISRG root)
- `tests/Unit/TelecallerAllocationTest.php`: 10 tests.
- `tools/allocation_dryrun.php`: end-to-end check (section 6).

**Flutter (`client/lib/`)**
- `services/api_service.dart`: `getAllocationPlan`, `createAllocationPlan(pincodes, startDate:, endDate:)`, `cancelAllocationPlan`, `getAllocationToday`, `updateAllocationItem`.
- `screens/employee/allotted_customer_accounts_screen.dart`: the "Daily Calling Plan" card (telecaller role only).
  - Line 1: "From – To · N pincode(s) · Day x of y".
  - Line 2: "done · pending · ~per day · days left" (or "overdue").
  - Buttons: Create / "Add Pincodes / Change Dates", and Cancel.
- `screens/telecaller/daily_plan_sheet.dart`: the bottom sheet.
  - A **From – To calendar** (date-range picker; on an update only the To date can change).
  - A live preview: "N customers ÷ D day(s) ≈ X per day".
  - **Select All** and a pincode checklist. Pincodes already in the plan are locked.
- `screens/telecaller/telecaller_worklist_screen.dart`: "Today's Customers: N · done · left" banner. Allocated accounts are merged into Today, sorted after due follow-ups in plan order, with `PLAN #n` and `SKIP` / `SKIPPED · UNDO` tags.

---

## 6. How to verify it works

### A. Automated (backend), about 1 minute
```bash
cd server
php vendor/bin/phpunit tests/Unit/TelecallerAllocationTest.php   # expect OK (10 tests)
php tools/allocation_dryrun.php 9000000070 4                     # 4-day range → expect "ALL CHECKS PASSED"
php tools/allocation_dryrun.php 9000000076 5                     # 5-day range
```
`allocation_dryrun.php` runs real HTTP requests (routes, JWT, controllers, the CallLog hook) against the live database inside **one transaction that is always rolled back**. The clock is faked from 2026-10-01. It prints row counts before and after, and checks:
- a To date before the From date is rejected
- the day 1 size = ceil(queue ÷ days)
- every later day = ceil(remaining ÷ days left), and everything is handed out by the To date
- a second fetch on the same day returns the same list
- each call outcome → status mapping
- the merge (From date kept, To date extended by one day)
- carry-forward
- no duplicates
- plan completion
- the dashboard fallback
- that nothing persisted

**Last run (2026-10-01):** all checks passed for both telecallers. For 9000000070: 187 customers over 4 days gave 47 on day 1. After the merge and the one-day extension, the 204 remaining were split 51 a day, finishing on the To date.

Requirements:
- The telecaller has ≥3 assigned pincodes and no active plan (the script refuses otherwise).
- Seeded telecallers are mobiles `9000000069`–`9000000104` (see `docs/SEED_DATA_CONTEXT.md`).

### B. Manual (app), as a telecaller with assigned areas
1. Drawer → **Allotted Customer** → the "Daily Calling Plan" card is visible. It shouldn't be for a salesman.
2. Tap **Create Daily Plan**.
   - The sheet lists the pincodes with account counts.
   - Tap the date field and pick From = today, To = 4 days later. Tap **Select All**.
   - The preview shows "N customers ÷ 5 day(s) ≈ X per day". Tap **Create Plan**.
   - Expect a green snackbar and the card line "1 Oct – 5 Oct · N pincode(s) · Day 1 of 5".
3. Drawer → **Today Worklist** → "Today's Customers: X" banner. Cards carry `PLAN #1…#X` in that order, after any due follow-ups.
4. Call one customer and log an outcome:
   - *answered*: the card's plan tag stays and the banner "done" count goes up after refresh.
   - *callback*: the account moves to the follow-up flow.
5. Tap **SKIP** on a card → it becomes `SKIPPED · UNDO`; tap again to undo.
6. Back to Allotted Customer → **Add Pincodes / Change Dates**. Existing pincodes are ticked and locked, and the From date is fixed. Add pincodes or move the To date → "Daily plan updated".
7. Next day, Today Worklist → yesterday's uncalled customers appear first, then the next pincode in order. The day's count is remaining ÷ days left, so it rises if yesterday's list wasn't finished.
8. **Cancel** on the card → confirm → the card returns to "Create Daily Plan" and the banner disappears.

### C. Useful read-only SQL
```sql
SELECT * FROM tc_allocation_plan_crm WHERE employee_mobile = '9000000070';
SELECT allocated_date, pincode, status, COUNT(*) FROM tc_allocation_item_crm
 WHERE employee_mobile = '9000000070' GROUP BY 1,2,3 ORDER BY 1, MIN(pincode_rank);
SELECT * FROM pincode_geo_crm ORDER BY pincode;
```

---

## 7. Known limitations and gotchas

- **Geocoder quality.** Nominatim's postal-code points are approximate, and one (500053) was ~50 km off and corrected by hand. Check suspicious ones with `GET /api/pincode-geo` and fix them with `PUT /api/pincode-geo/{pincode}`.
- **Unknown pincodes.** A pincode Nominatim can't find stays unlocated and is sequenced **last** until an admin sets it.
- **First use of a new pincode** costs ~1 s per pincode inside the POST, because of the geocoder rate limit.
- **The list doesn't refill mid-day.** Once today's list exists it never grows, even if the telecaller finishes early or moves the To date; changes apply from the next day.
- **Days not opened still count.** Every calendar day in the range counts. If the telecaller doesn't open the app one day, that day's share is spread over the remaining days, so the per-day count rises.
- **Calls outside today's list.** A call to a *pending* (not yet allocated) account doesn't mark it done. It will still be allocated later.
- **Accounts that leave the scope.** Accounts that drop out of the telecaller's scope after the plan was built stay in the queue.
- **No admin screen** for pincode coordinates yet (API only).
- **Leads without a pincode** can't be selected; they need a pincode to be placed.
- **Don't use customer coordinates** (`user.latitude/longitude`) for any geo logic. See the placeholder-coordinates finding above.
- **Database rule.** Any write to the live DB (including these CRM tables) needs the owner's approval. Test write paths in a rolled-back transaction, as `tools/allocation_dryrun.php` does.

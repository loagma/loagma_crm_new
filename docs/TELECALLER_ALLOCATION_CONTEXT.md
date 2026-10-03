# Telecaller Daily Calling Plan (pincodes by location, fixed dates) — Context

Branch `feat/telecaller-geo-allocation` (not yet merged to `main`). First commit `05d6ee0` (2026-10-01). The date-range and fixed-date changes (2026-10-03) came after it.

A telecaller picks pincodes (or **Select All**) and a **From–To date range** on a calendar. The backend:

1. Orders the pincodes by each **pincode's own location**.
2. Puts all their customers and leads in that order.
3. Splits them **once** over the From–To days. Every customer gets one **fixed date**.
4. Never moves a date by itself. A customer whose date passes without a call is **Missed**, and the telecaller gives them new dates with Auto-Distribute.

The telecaller sees "Today's Customers: N" in Today Worklist. On the Allotted Customer screen they see each customer's date, with per-pincode Assign / Unassigned / Missed counts. The internal geographic clusters are never shown.

---

## 1. Business rules (agreed with the product owner)

| Rule | Decision |
|---|---|
| Pincode order | By real location, **never** by pincode number. |
| Where a pincode's location comes from | The pincode itself, looked up once from OpenStreetMap Nominatim and cached in `pincode_geo_crm`. **Customer latitude/longitude are never used**: most `user` rows hold placeholder coordinates inside one ~300 m Hyderabad block. |
| Which pincode a customer belongs to | Only its `pincode` field. |
| Order inside a pincode | Customers first, then leads, each by id. It is fixed and repeatable. |
| How many per day | **Not entered by the telecaller.** They pick From–To dates. Every calendar day counts, Sundays included, up to 366 days (`config/telecaller.php`). At creation the accounts are split evenly, larger days first, e.g. 187 over 4 days → 47, 47, 47, 46. Each account keeps its date. |
| Quota per pincode | None. A day fills in queue order and crosses pincode boundaries (e.g. 482001:52 + 482005:32). |
| Uncalled on its day | **No re-division and no carry-forward.** The account stays on its date with status `assigned` and shows as **Missed** once the date has passed. Other days' lists don't change. |
| Missed customers | The telecaller selects them on the Allotted Customer screen (**Missed** tab per pincode) and taps **Auto-Distribute** to spread them over new dates (today or later). |
| Adding pincodes to a running plan | Their accounts come in **without a date** ("without date" / Unassigned). The telecaller dates them with **Auto-Distribute**. Existing accounts keep their dates. |
| Changing only the To date | Nothing moves. An Auto-Distribute date beyond the To date extends the To date. |
| New customers later appearing in plan pincodes | Added without a date (when Today Worklist is next opened), to be dated the same way. |
| Busy / no answer / switched off | Counted as **done** (the attempt is logged). |
| Callback outcome | Status `callback`. The existing Callbacks / follow-up flow takes it over. |
| A missed customer called later | Counts as done (any open account in the plan is matched, whatever its date). |
| Who is in the plan | `user` customers in the telecaller's area pincodes, leads in their areas, and customers directly assigned to them (`customer_assign_crm`). Accounts labelled `do_not_call` or `wrong_number` are excluded or skipped. |
| Auto-Distribute over weekdays | Select N customers → **Auto-Distribute** → popup 1: From date plus either a **Date range** (To date) or **N days** → **Next** → popup 2: tick the weekdays (Mon–Sun chips or **All days**) → **Distribute**. Only ticked weekdays get customers: those inside the From–To range, or in **N days** mode (no To date) the first N dates on the ticked weekdays counted from the From date (the From date counts if it matches). Example: from Sat 3 Oct, Mon + Fri, N = 8 → Mon 5, Fri 9, Mon 12, Fri 16, Mon 19, Fri 23, Mon 26, Fri 30 Oct = 4 Mondays + 4 Fridays. With All days, N is N consecutive days. They are spread in **even consecutive blocks** in plan pincode order (not round-robin), e.g. 30 customers over Mon/Wed/Fri of two weeks = 5 on each of 6 days. With an active Daily Plan the dates go into the plan; without one they go to the beat plan. Already-called customers are left alone and reported. |
| Plan completion | When no account is left open (pending, assigned or in progress). |
| Beat plan (`beat_plan_crm`) | Untouched. Allocation runs alongside it. On the Allotted Customer screen, "Assign" counts accounts with a beat plan **or** a plan date. |

### Example (unit-tested)
Queue order 482001(52) → 482005(48) → 482002(75) → 482008(60) → 482020(100) = 335 accounts, From 1 Oct To 4 Oct:

| Date | Customers |
|---|---|
| 1 Oct | 482001:52 + 482005:32 |
| 2 Oct | 482005:16 + 482002:68 |
| 3 Oct | 482002:7 + 482008:60 + 482020:17 |
| 4 Oct | 482020:83 |

If only 60 of 1 Oct's 84 are called, 2 Oct is still exactly its 84. The 24 left over show as Missed (1 Oct) until the telecaller sets them a new date.

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

- **Live state:** 74 rows, i.e. all pincodes in `area_crm`. 73 are `geocoded`; 1 is `manual` (500053, set to 17.33, 78.47 because Nominatim placed it about 50 km west).

### `tc_allocation_plan_crm`
A telecaller's plan.

| Column | Notes |
|---|---|
| `employee_mobile` | `deli_staff.mobile` |
| `selected_pincodes` | JSON |
| `pincode_sequence` | JSON, the ordered pincodes |
| `daily_capacity` | Informational: accounts per day at creation (`ceil(total ÷ days)`) |
| `start_date`, `end_date` | The From–To range. Naive IST dates, cast `date:Y-m-d`. Added by migration `2026_10_01_000004`. |
| `status` | `active`, `completed` or `cancelled` |

At most one `active` plan per telecaller. This is enforced in code, not by the database.

### `tc_allocation_item_crm`
One row per account in a plan.

| Column | Notes |
|---|---|
| `plan_id`, `employee_mobile` | |
| `account_id` | `user.userid` or the `LeadsAccount_crm` UUID |
| `account_type` | `customer` or `lead` |
| `pincode`, `pincode_rank`, `account_rank` | Plan order |
| `allocated_date` | **The account's fixed date** (naive IST, `date:Y-m-d`). NULL = no date yet. |
| `status` | See below |
| `call_log_id`, `completed_at` | |

`status` values:
- `pending`: no date yet
- `assigned` / `in_progress`: dated, not called yet. **Missed** = this and `allocated_date` < today. Missed is derived, not stored.
- `completed`, `skipped`, `callback`: worked

Unique on (`plan_id`, `account_id`).

Migrations: `server/database/migrations/2026_10_01_00000{1,2,3,4}_*.php` (all already run on `loagma_new`).

**Live data note (2026-10-03):** plan 10 (telecaller 8103858929, 1–31 Oct, 934 accounts) was created under an earlier re-divide version. With the owner's approval, its 903 undated rows were given fixed dates using the same split (30–31 per day). The 31 already on 1 Oct matched exactly.

---

## 3. How it works

```
POST /telecaller/allocation {pincodes[], start_date, end_date}
  ensurePincodeGeo(pincodes)       ← outside the lock; Nominatim ~1 req/s, only for pincodes not cached yet
  ┌ transaction, active plan row locked
  │ NEW PLAN:  sequence = sequenceFor(pincodes)                       (GeoSequencer)
  │            rows = rankAccounts(candidates, sequence)              (plan order)
  │            dates = DailyAllocator::datesFor(count, start, end)    (one-time even split)
  │            insert rows: status assigned, allocated_date = dates[i]
  │ MERGE:     union pincodes, sequence = mergedSequence(), end_date updated
  │            new accounts inserted: status pending, allocated_date NULL (telecaller dates them)
  │            existing accounts: only ranks updated — dates untouched
  └

GET /telecaller/allocation/today
  queueNewAccounts()  ← new customers/leads in plan pincodes → pending, no date
  skipLabelled()      ← do_not_call / wrong_number → skipped
  completeIfDone()    ← no open accounts → plan completed
  return accounts with allocated_date = today, in plan order

POST /telecaller/allocation/distribute {account_ids[] (selection order), start_date, end_date | days, weekdays[]}
  dates = DailyAllocator::resolveDates(start, end, days, weekdays)   (days → first N matching dates; else the range; 422 if none)
  open/skipped accounts of the active plan → status assigned, consecutive even blocks over dates
    (DailyAllocator::blocksOver); called accounts untouched; date > end_date extends end_date

POST /telecaller/allocation/reassign {account_ids[], date}
  open or skipped accounts of the active plan → status assigned, allocated_date = date
  (completed/callback are left alone; date > end_date extends end_date)

CallLog saved (manual log, action log, Knowlarity create + webhook)
  → recordCallOutcome(): the plan's account (pending/assigned/in_progress, any date):
      callback                                         → callback
      invalid (manual)                                 → skipped
      invalid (Knowlarity)                             → ignored (may be a provider-side rejection)
      answered/complaint/busy/no_answer/switch_off     → completed
```

**GeoSequencer** (pure, unit-tested):
1. Groups pincodes whose points are within 5 km of each other (`TC_ALLOCATION_CLUSTER_KM`).
2. Chains the clusters nearest-first, starting from the outermost one.
3. Within each cluster: nearest-first from where the previous cluster ended, then a 2-opt pass.
4. Pincodes with no location go last.
5. With a `$from` point it continues from there (used for merges).

**DailyAllocator** (pure, unit-tested):
- `split(n, start, end)`: per-day counts.
- `datesFor(n, start, end)`: date per position.
- `daysInclusive()`

---

## 4. API (all routes check the JWT; the telecaller is taken from the token's mobile)

| Method | Path | Body / query | Returns |
|---|---|---|---|
| GET | `/api/telecaller/allocation` | – | `data: null` without an active plan; otherwise the fields listed below this table. |
| POST | `/api/telecaller/allocation` | New: `{"pincodes":[…],"start_date":"2026-10-05","end_date":"2026-10-09"}`. Merge: `{"pincodes":[…],"end_date":"…"}` | 201 + progress. 422 if: no callable accounts; `start_date` is before today; `end_date` is before `start_date` (or before today on a merge); or the range is over 366 days. |
| GET | `/api/telecaller/allocation/today` | – | `{plan_id, plan_status, daily_capacity, start_date, end_date, total, customers:[{item_id, account_id, account_type, allocation_status, pincode, name, business_name, person_name, phone, area, city, stage, address, latitude, longitude}]}`: accounts dated today, in plan order |
| POST | `/api/telecaller/allocation/reassign` | `{"account_ids":["…"],"date":"2026-10-05"}` (date ≥ today) | `{success, message, updated, data: progress}`. 422 if nothing could be rescheduled (e.g. all already called). |
| POST | `/api/telecaller/allocation/distribute` | `{"account_ids":["…"],"start_date":"2026-10-05","end_date":"2026-10-18","weekdays":["Mon","Wed","Fri"]}`, or N-days mode `{"account_ids":["…"],"start_date":"2026-10-03","days":8,"weekdays":["Mon","Fri"]}` (send `end_date` or `days`; empty/absent weekdays = every day; ids in the order to lay them out; `days` 1–366) | `{success, message, updated, skipped_done, not_in_plan, dates:{date:count}, data: progress}`. 422 if the date range or a weekday is invalid, no chosen weekday falls in the range, or nothing could be distributed; 404 without an active plan. |
| POST | `/api/beat-plan/auto-distribute` | existing body + optional `weekdays[]` and `days` (N-days mode, instead of `end_date`) | Beat-plan fallback when the telecaller has no Daily Plan: same weekday filter and even-block spread; 422 if no chosen weekday falls in the range. |
| PATCH | `/api/telecaller/allocation/items/{id}` | `{"status":"skipped"\|"in_progress"\|"assigned"}` | Manual skip, start or undo |
| DELETE | `/api/telecaller/allocation` | – | Cancels the active plan; history is kept |
| GET | `/api/pincode-geo?pincodes[]=` | admin, teleadmin | Stored points |
| PUT | `/api/pincode-geo/{pincode}` | `{"lat":17.33,"lng":78.47}` or `{"source":"geocoded"}` | Manual override, or look the pincode up again |

Progress fields returned by `GET /api/telecaller/allocation`:
- **Plan and dates:** `plan_id`, `today`, `start_date`, `end_date`, `total_days`, `day` (0 before start), `days_left`.
- **Counts:** `daily_capacity`, `today_count`, `total`, `done`, `pending`, `missed`, `unscheduled`.
- **Lists:** `selected_pincodes`, `pincode_sequence`, `status_counts`, `remaining_by_pincode[]`.
- **`schedule`:** `{account_id: {date, status}}` for every dated account.

The dashboard (`GET /api/telecaller/dashboard`) `daily_target` is the number of accounts dated today in the active plan, or 60 without a plan.

---

## 5. Files

**Backend (`server/`)**
- `app/Services/TelecallerAllocationService.php`: create/merge, today, progress (with schedule), reassign, cancel, call hook, candidates, pincode locations, enrichment.
- `app/Support/GeoSequencer.php`: proximity ordering (pure).
- `app/Support/DailyAllocator.php`: one-time day split, `datesInRange()` (weekday filter), `datesByCount()` (N-days mode), `resolveDates()` and `blocksOver()` (even consecutive blocks) (pure).
- `app/Support/PincodeGeocoder.php`: Nominatim pincode lookup.
- `app/Support/TelecallerScope.php`: a telecaller's areas and pincodes (trimmed). Also used by `TelecallerController`.
- `app/Http/Controllers/TelecallerAllocationController.php`: the endpoints above.
- `app/Models/{PincodeGeo,TcAllocationPlan,TcAllocationItem}.php`; `app/Models/CallLog.php` (`booted()` → `recordCallOutcome`).
- `app/Http/Controllers/TelecallerController.php`: `daily_target` = today's dated count.
- `routes/api.php`: the `telecaller/allocation*` group and the `pincode-geo` group.
- `config/telecaller.php` and env keys:
  - `TC_ALLOCATION_CLUSTER_KM`, `TC_ALLOCATION_MAX_DAYS`
  - `PINCODE_GEOCODER_URL`, `PINCODE_GEOCODER_UA`, `PINCODE_GEOCODER_TIMEOUT`
  - `PINCODE_GEOCODER_CA` (defaults to `OSRM_CA`)
- `tests/Unit/TelecallerAllocationTest.php`: 8 tests.
- `tools/allocation_dryrun.php`: end-to-end check (section 6).

**Flutter (`client/lib/`)**
- `services/api_service.dart`: `getAllocationPlan`, `createAllocationPlan(pincodes, startDate:, endDate:)`, `reassignAllocation(accountIds, date)`, `cancelAllocationPlan`, `getAllocationToday`, `updateAllocationItem`.
- `screens/employee/allotted_customer_accounts_screen.dart` (telecaller with a plan):
  - **Plan card:** "From – To · N pincode(s) · Day x of y", "today · done · pending · days left", and a red "X missed · Y without date" hint.
  - **Per pincode:**
    - **Assign** = beat plan or plan date.
    - **Unassigned** = neither.
    - **Missed** tab, shown when any account is missed.
    - The Mon–Sun chips include plan dates.
  - **Each card:** a green "Daily Plan: Thu 23 Oct" tag, or a red "Missed: Wed 1 Oct".
  - **Bottom bar:** the existing Unassign / Auto-Distribute / Assign buttons (the separate "Set Plan Date" button was removed; use Auto-Distribute to give missed or undated customers new dates).
- `screens/shared/auto_distribute_dialog.dart` (popup 1: From date + **Date range / N days** switch → Next) and `screens/shared/auto_distribute_flow.dart` (`showAutoDistributeFlow()` and popup 2 `AutoDistributeDaysDialog`: Mon–Sun chips + All days, live preview "N customers over D day(s) (Mon, Wed, Fri) ≈ X per day", disabled with a red hint when no ticked day falls in the range). Used by the Allotted Customer screen and Today Worklist; both send the customers in plan pincode order to `distributeAllocation` when a Daily Plan is active, otherwise to `autoDistributeBeatPlan(weekdays: …)`.
- `screens/telecaller/daily_plan_sheet.dart`:
  - From–To calendar (on an update only To can change).
  - Create preview: "N customers ÷ D day(s) ≈ X per day".
  - Update note: "new customers will be added without a date".
  - Select All and a pincode checklist.
- `screens/telecaller/telecaller_worklist_screen.dart`: "Today's Customers: N" banner, plus `PLAN #n` and `SKIP` / `SKIPPED · UNDO` tags on today's accounts.

---

## 6. How to verify it works

### A. Automated (backend), about 1 minute
```bash
cd server
php vendor/bin/phpunit tests/Unit/TelecallerAllocationTest.php   # expect OK (8 tests)
php tools/allocation_dryrun.php 9000000070 4                     # expect "ALL CHECKS PASSED"
php tools/allocation_dryrun.php 9000000076 5
```
`allocation_dryrun.php` runs real HTTP requests (routes, JWT, controllers, the CallLog hook) against the live database inside **one transaction that is always rolled back**. The clock is faked from 2026-10-01. It checks:
- a To date before the From date is rejected
- every account gets a fixed date, split evenly
- each day's list = exactly the accounts dated that day
- a second fetch on the same day returns the same list
- Auto-Distribute over two chosen weekdays: only those weekdays are used, the other day gets none, even consecutive blocks in selection order, called accounts skipped, unknown ids counted, an empty weekday match and an invalid weekday are rejected
- N-days mode (first N matching days from the start date, no To date); neither a To date nor N, and N = 0, are rejected
- the beat-plan fallback (no active plan) honours the weekdays and N (From 3 Oct, N = 8, Mon+Fri → 4 Mon + 4 Fri)
- the dashboard target
- each call outcome → status mapping
- day 1's uncalled accounts are **not** moved and show as missed with their day 1 date
- reassigning to a past date is rejected
- reassigning missed accounts to day 3 works
- already-called accounts can't be rescheduled
- merged pincodes come in undated, while existing dates don't change, and can then be dated
- the plan completes when everyone is called
- nothing persisted

**Last run (2026-10-03):** all checks passed for 9000000070 and 9000000076.

Requirements:
- The telecaller has ≥3 assigned pincodes and no active plan (the script refuses otherwise).
- Seeded telecallers are mobiles `9000000069`–`9000000104` (see `docs/SEED_DATA_CONTEXT.md`).

### B. Manual (app), as a telecaller with assigned areas
1. Drawer → **Allotted Customer** → the "Daily Calling Plan" card (not shown to salesmen).
2. Tap **Create Daily Plan**.
   - Pick From = today and To = 4 days later. Tap **Select All**.
   - The preview shows "N customers ÷ 5 day(s) ≈ X per day". Tap **Create Plan**.
   - Each pincode's **Assign** box now counts its accounts and the Mon–Sun chips fill in. Cards show "Daily Plan: <day date>".
3. **Today Worklist** → "Today's Customers: X", the accounts dated today.
4. Call some, leave some uncalled. Next day: those show as **Missed** (red tag, Missed tab, card hint "X missed"), and today's list is only today's own accounts.
5. Select missed customers → **Auto-Distribute** → pick dates and weekdays → Distribute. They move to those days.
6. **Add Pincodes / Change Dates** → add a pincode → its customers show "without date" / Unassigned. Select them → **Auto-Distribute**.
7. **Auto-Distribute over weekdays:** select N customers (e.g. **Select All** in a pincode, or Select N) → **Auto-Distribute** → pick From and To (or switch to **N days**, pick From and type N, e.g. 8) → **Next** → tick e.g. Mon, Wed, Fri (or **All days**) → **Distribute**. The Mon–Sun chips, Assign counts and "Daily Plan: …" tags update; only Mon/Wed/Fri get customers, in even blocks. Try a range with no ticked weekday inside it: the button is disabled with a red hint.
8. **Cancel** on the card → confirm → the card returns to "Create Daily Plan".

### C. Useful read-only SQL
```sql
SELECT * FROM tc_allocation_plan_crm WHERE employee_mobile = '8103858929';
SELECT allocated_date, status, COUNT(*) FROM tc_allocation_item_crm
 WHERE employee_mobile = '8103858929' GROUP BY 1,2 ORDER BY 1;
SELECT * FROM pincode_geo_crm ORDER BY pincode;
```

---

## 7. Known limitations and gotchas

- **Geocoder quality.** Nominatim's postal-code points are approximate (500053 was ~50 km off and corrected by hand). Fix others with `PUT /api/pincode-geo/{pincode}`.
- **Unknown pincodes.** A pincode Nominatim can't find stays unlocated and is ordered **last** until an admin sets it.
- **First use of a new pincode** costs ~1 s per pincode inside the POST (geocoder rate limit).
- **Missed customers only move by hand.** Nothing is ever re-divided automatically; missed customers wait until the telecaller sets a new date.
- **Accounts that leave the scope.** Accounts that drop out of the telecaller's scope after the plan was built stay in the plan.
- **No admin screen** for pincode coordinates yet (API only).
- **Leads without a pincode** can't be selected.
- **Don't use customer coordinates** (`user.latitude/longitude`) for any geo logic.
- **Database rule.** Any write to the live DB (including these CRM tables) needs the owner's approval. Test write paths in a rolled-back transaction, as `tools/allocation_dryrun.php` does.

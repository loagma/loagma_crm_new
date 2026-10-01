# Demo / seed data entered into the live DB (Sep 2026)

All of this was inserted directly into the live TiDB database (`loagma_new`) with one-off PHP scripts
(Laravel bootstrap + `DB::table()`); the scripts were deleted afterwards. **Nothing here went through the API,
so no app-level side effects (notifications, reminders, follow-up rows in `beat_plan_followup_crm`) were triggered.**
Data is synthetic: shop names like "Shop 500028 14" come from the pre-existing `user` table, not from this seed.

## Staff mapping

| Group | Mobiles | Names |
|---|---|---|
| Telecaller N | `9000000068 + N` | Telecaller 1 = 9000000069 ... Telecaller 36 = 9000000104 |
| Salesman N | `9000000032 + N` | Salesman 1 = 9000000033 ... Salesman 36 = 9000000068 |
| Area Incharge N | `9000000020 + N` | 9000000021..32 |
| Teleadmin N | `9000000008 + N` | 9000000009..20 |
| Zonal Incharge N | `9000000002 + N` | 9000000003..08 |
| Head Incharge 1 / 2 | 9000000001 / 9000000002 | |

Salesman `deli_id` = 478..513 (this, not the mobile, is what `orders.salesman_id` stores).

## Hierarchy (`incharge_assign_crm`, parent mobile in `head_incharge_id`)

- Head 1 -> Zonal 1-3, Head 2 -> Zonal 4-6 (pre-existing).
- Zonal k -> Teleadmin (pre-existing) **+ Area Incharge 2k-1, 2k (added Sep 25)**.
- Area Incharge n -> Salesman 3n-2, 3n-1, 3n (new rows, added Sep 25). E.g. Area Incharge 1 -> Salesman 1-3.
- Teleadmin -> 3 telecallers each (pre-existing).
- Verified with `App\Support\Hierarchy::descendantMobilesFast`: Head 1 sees 18 salesmen, Zonal 1 sees 6, Area Incharge 1 sees 3.

## What was seeded

### 1. Telecaller 13-32: call logs (task 1)
- `call_log_crm`, 392 rows, 15-25 per telecaller, picked at random from each telecaller's area-scoped worklist
  (`area_assign_crm` -> `area_crm.pincodes` -> `LeadsAccount_crm` + `user`). Calls only, no visits.

### 2. Telecaller 5-36: Self Report data (beat-plan based)
- Source accounts = the telecaller's active `beat_plan_crm` rows (the Self/Team Report only lists beat-plan accounts).
- `call_log_crm`: 1-4 calls per account (~12% of accounts left untouched), outcome weights
  answered 45 / busy 15 / no_answer 15 / callback 12 / switch_off 8 / invalid 5; ~55% `manual`, ~45% `knowlarity`.
- `action_log_crm` (role `telecaller`): a **check-in + check-out row for every call** (linked via `call_log_id`),
  plus ~55% of accounts got an extra standalone visit. "Visited" in the report = `check_out_at IS NOT NULL`.
- Orders on telecaller visits are **synthetic**: `order_no` is a random 6-digit string (28xxxx) with **no row in `orders`**.
  The report only checks `order_no` or an `orders` row by `buyer_userid`, so this is enough for the UI.
- Skipped telecallers that already had solid data: 9000000073, 75, 76 (organic), 82, 86, 87, 91, 100 (seeded earlier).
- All timestamps were later re-dated into **2026-09-21 .. 2026-09-23** (business hours, capped at "now").

### 3. Salesman 1-36 (Sep 25)
- `area_assign_crm`: 2 random areas each (from 53 areas with 60+ customers).
- `beat_plan_crm`: 905 active plans, weekly Mon-Sun, `start_date` 2026-09-21; ~20-26 customers + 2-4 leads per salesman.
- `action_log_crm` (role `salesman`): 1,540 visits, Sep 21-25, 7-10/day, sequential with 8-25 min travel gaps;
  check-in/out GPS = customer location +/- ~40 m. Checkout form fully filled: `outcome_slug` (from `action_log_stage_crm`),
  `general_notes`, `notes_related_to`, `market_note`, `follow_up_date/note`, `payment_collected/mode` on some.
- **496 real orders** (`orders` + `orders_item` + `master_orders`, ~Rs 82.9 lakh total) for `placed_order` visits, built the same way as
  `SalesOrderController::store` (state `pending`, `cod`, `not_paid`, `admin_id` 108, `salesman_id` = deli_id, 2-5 items from
  271 products that have real pack prices). `action_log_crm.order_no` = the real `orders.order_id`.

### 4. Salesman 1-36 attendance + GPS route (Sep 27)
Added so the attendance-based Team Report / My Report stop showing every seeded salesman as "Absent" with 0 km.
- `attendance_crm`: 180 rows (ids 330361..330540), one per salesman per visit day (Sep 21-25). Punch-in 08:50-09:12 and
  always before the first visit (`early_in` if before the 09:00 shift start, else `on_time`); punch-out 18:00-18:25 (no early-outs,
  nothing pending approval). No punch photos. `total_distance_km` computed from the pings with `RouteDistance::stats`;
  `route_snapped` left NULL (the app fills it on first route view).
- `location_pings_crm`: 45,214 rows (ids 211215..257214), **all `is_mock = 1`**. Day base 1.5-3 km from the first shop ->
  each visit in order (travel pings every 60-90 s, dwell pings every 3-4 min at the shop) -> back to base until punch-out.
  Avg ~25 km/day (4-89).
- Legs over 40 km between consecutive seeded visits (7 legs; Salesman 5 has one area in Jabalpur and one in Hyderabad, Salesman 2
  has far-off customer coordinates) got **no pings**, i.e. a tracking gap: excluded from distance, day marked `was_interrupted = 1` (8 days).
- These pings are never pruned: retention pruning only runs on the employee's own first ping of the day.

## How to find / remove the seeded rows

Run a `SELECT COUNT(*)` first; these are one-way deletes.

| Table | Seeded rows |
|---|---|
| `call_log_crm` | `id > 630090` (all rows above the last organic id at the time) |
| `action_log_crm` (telecaller) | `id > 510078` and `role = 'telecaller'` |
| `action_log_crm` (salesman) | `role = 'salesman' AND employee_mobile BETWEEN '9000000033' AND '9000000068'` |
| `orders` | `salesman_id BETWEEN '478' AND '513' AND txn_id LIKE 'CRM-%'` (also delete matching `orders_item`, `master_orders` by `order_id`) |
| `beat_plan_crm` (salesman) | `salesman_id BETWEEN '9000000033' AND '9000000068'` |
| `area_assign_crm` (salesman) | `employee_id BETWEEN 9000000033 AND 9000000068` |
| `attendance_crm` (salesman) | `employee_mobile BETWEEN '9000000033' AND '9000000068' AND date BETWEEN '2026-09-21' AND '2026-09-25'` (ids 330361..330540) |
| `location_pings_crm` (salesman) | `employee_mobile BETWEEN '9000000033' AND '9000000068' AND is_mock = 1` (ids 211215..257214) |
| `incharge_assign_crm` | rows with `head_incharge_id` 9000000021..32 (new); zonal rows 9000000003..08 had Area Incharge ids appended to `incharge_ids/incharge_names` |

Caveat: a real order for a seeded salesman placed later would match the `orders` filter only if its `txn_id` starts with `CRM-`
(the app uses the same prefix) - filter by `salesman_id` range **and** the Sep 21-25 `start_time` window before deleting.

## Known realism gaps
- Notes come from small template sets, so sentences repeat across staff.
- Uniform behaviour across staff (~38% order rate, similar start times).
- All seeded orders are `pending` / `not_paid`, even the oldest; no bill/invoice numbers; no visit photos.
- Some order baskets contain odd catalogue items (e.g. a test product named "eextra").
- Telecaller "orders" are order-number strings only (see above); salesman orders are real.
- Seeded visits are only Sep 21-25, so the reports' default "Today"/"Yesterday" filters show beat-plan customers with all zeros
  from Sep 26 on; use "This Month" or Custom 21-25 Sep.
- About 130 consecutive-visit legs are 10-40 km apart with only 8-25 min between them (faster than road travel); route pings follow them.
- Punch-out is ~3.5 h after the last visit (visits end by ~14:30); the afternoon is stationary pings at base.

## Related code changes made in the same session (already committed)
- `notification_service.dart`: skip init on web (fixed the deployed white screen).
- `server/config/cors.php` added (API had no CORS headers).
- `BeatPlanController::accountStats` returns `{}` not `[]` when empty; Customer List Allotment tolerates a non-map `data`.
- Report "Custom" date filter is now a small dialog; `font_awesome_flutter` upgraded to 11.x.

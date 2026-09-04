# Database Tables — Loagma CRM

**Only the tables and columns this codebase actually reads or writes.** The database
(`loagma_new`, TiDB Cloud) has **123 tables**; the Laravel backend in `server/` touches
**36**. Of those, 8 are unused Laravel scaffolding, leaving **28 real tables** and
**318 of their 465 columns** in actual use. Everything else belongs to the older shared
ERP / consumer app and is not listed.

**How this was produced:** every query-builder chain (`DB::table('x')->…;`) and Eloquent
statement in `server/app`, `server/routes` and `server/database` was sliced out of the
source, its quoted identifiers and array keys extracted, and the result **intersected
with the live `SHOW COLUMNS` output** for that table. A token that isn't a real column of
that table is dropped, so nothing here is guessed. Types, nullability, keys and defaults
are the live production schema, not migration files.

Last verified: **2026-09-05**. Narrative companion (created vs. borrowed vs. added-columns,
with the why/how): [DB_GUIDE.md](DB_GUIDE.md).

> **2026-09-05:** by product decision the Create Sales Order draft was moved off
> `sales_order_draft_crm` (now dropped) onto the shared **`cart`** table — one JSON row
> per (staff, account), `ctype_id = 'crm_sales_draft'`, in a new `draft_payload` column.
> `cart` is therefore now a **written** shared table (CRM-added columns only). See the
> `cart` section and migration `2026_09_05_000001_move_sales_order_draft_to_cart`.

---

## Ownership — read this first

| Class | Count | Meaning |
|---|---|---|
| **CRM** | 15 | Created and owned by this repo's migrations. Safe to alter. |
| **Shared** | 13 | Owned by the parent ERP / consumer app. Do not alter existing columns; `cart` carries CRM-added columns. |
| **Laravel** | 8 | Framework scaffolding. Present, unused by app code. |

The `_crm` suffix marks CRM ownership — with three traps:

- **`deli_staff` is shared, despite having a `create` migration here.** That migration
  ([2026_05_01_000000](server/database/migrations/2026_05_01_000000_create_deli_staff_table.php))
  opens with `if (Schema::hasTable('deli_staff')) return;` — it's a local-bootstrap stub
  that no-ops against the real database. Its column list is also a *subset* of reality
  (10 columns vs the real 22), so don't read it as the schema.
- **`LeadsAccount_crm`** breaks the naming convention twice: PascalCase table name, and
  camelCase columns (`businessName`, `assignedToId`). Every other CRM table is
  snake_case. Quote it carefully.
- **`action_log_crm` / `action_log_stage_crm`** were created as `order_funnel_response_crm`
  / `order_funnel_crm` and renamed by
  [2026_09_01_000001](server/database/migrations/2026_09_01_000001_rename_order_funnel_to_action_log.php).
  Note the swap: the *response* table became `action_log_crm` (the log rows), and the
  *funnel* table became `action_log_stage_crm` (the lookup).

---

## Cross-cutting conventions

**Staff identity is `deli_staff.mobile`, not `deli_id`.** Every CRM table keys staff by
the phone number string. The column name varies by table and that is the single most
common source of confusion:

| Column | Tables |
|---|---|
| `employee_mobile` | `action_log_crm`, `attendance_crm`, `call_log_crm`, `call_scripts_crm`, `location_pings_crm`, `telecaller_label_crm` |
| `staff_id` | `beat_plan_followup_crm`, `cart` (`crm_sales_draft` rows) |
| `salesman_id` | `beat_plan_crm` |
| `raised_by`, `assigned_to`, `assigned_by`, `resolved_by` | `complaint_crm` |
| `approved_by` | `attendance_crm` |

**Accounts are polymorphic.** A CRM record points at either a lead or a customer via the
pair `(account_id, account_type)`. `account_type = 'lead'` → `account_id` is a
`LeadsAccount_crm.id` (a 36-char UUID string); `account_type = 'customer'` → it's a
`user.userid` (numeric, still stored as a string). There is no FK either way.

**Timestamps are naive IST.** Datetime columns store IST wall-clock with no zone. The API
serialises to UTC-Z on the wire and `date` columns cast to `Y-m-d`. Do not apply a second
conversion server-side.

**Three shared tables have no `AUTO_INCREMENT`** — `orders.order_id`, `orders_item.item_id`
and `master_orders.id` are allocated as `MAX(...) + 1` under `lockForUpdate()`. See the
`orders` notes for the failure this caused.

**JSON is stored two ways.** CRM tables use a real `json` column type; shared tables use
`text`/`longtext` holding JSON (`orders_item.pinfo`, `vendor_products.packs`,
`orders.delivery_info`). Cast accordingly.

---

## Summary

### CRM-owned (15)

| Table | Cols used | Purpose |
|---|---|---|
| `LeadsAccount_crm` | 36/36 | Prospective business accounts before they become `user` rows |
| `action_log_crm` | 34/35 | Every salesman visit / telecaller call outcome — the activity spine |
| `action_log_stage_crm` | 5/7 | Lookup of selectable visit/call outcomes |
| `area_assign_crm` | 4/6 | Which areas an employee covers |
| `area_crm` | 3/5 | Named service areas and their pincodes |
| `attendance_crm` | 26/29 | Daily punch in/out, breaks, route, approval |
| `beat_plan_crm` | 13/15 | Recurring visit schedule per salesman + account |
| `beat_plan_followup_crm` | 9/11 | One-off follow-ups scheduled from a check-out |
| `call_log_crm` | 15/17 | Telecaller call records, manual and Knowlarity |
| `call_scripts_crm` | 6/8 | Per-telecaller call scripts |
| `complaint_crm` | 16/18 | Customer complaints, assignment and resolution |
| `incharge_assign_crm` | 4/6 | Head-incharge → incharge hierarchy |
| `location_pings_crm` | 10/11 | GPS breadcrumbs during a punched-in shift |
| `role_crm` | 4/4 | Role name lookup |
| `telecaller_label_crm` | 4/7 | Per-telecaller labels on an account |

### Shared / parent-app (13) — do not alter existing columns

| Table | Cols used | Purpose |
|---|---|---|
| `admin` | 2/32 | Vendor org; only the name is read |
| `cart` | 8/14 | **Written by the CRM** — un-submitted Create Sales Order draft (`ctype_id='crm_sales_draft'`), CRM-added columns only |
| `deli_staff` | 18/22 | **Core auth table.** Every non-customer login |
| `master_orders` | 13/13 | Order header twin of `orders` |
| `orders` | 27/43 | Real sales orders |
| `orders_item` | 9/15 | Order line items |
| `product` | 9/37 | Product catalog |
| `product_taxes` | 6/8 | Authoritative GST rates per product |
| `taxes` | 3/8 | Tax component names (SGST/CGST/IGST/CESS) |
| `units_master` | 4/9 | Unit of measure lookup |
| `user` | 19/33 | Registered customer accounts |
| `user_addresses` | 7/15 | Customer address book |
| `vendor_products` | 6/8 | Per-vendor pack pricing and stock |

### Laravel scaffolding (8) — present, unused by app code

`cache`, `cache_locks`, `failed_jobs`, `job_batches`, `jobs`, `password_reset_tokens`,
`sessions`, `users`. Created by the default framework migrations. **`users` is not the
customer table** — that's `user` (singular).

---

# CRM-owned tables

## LeadsAccount_crm
A prospective business account. Becomes a `user` row on conversion, linked back via
`user.lead_account_id`. Used by `LeadsAccountController`, `BeatPlanController`,
`ActionLogController`, `ComplaintController`, `AccountHistoryController`.

All 36 columns are in use (the model's `$fillable` covers the table).

| Column | Type | Notes |
|---|---|---|
| `id` | char(36) **PK** | UUID string, not an integer |
| `accountCode` | varchar(191) **UNI** | Human-facing account code |
| `businessName` | varchar(191) | Shop/business name — what the UI shows as the account title |
| `businessType`, `businessSize` | varchar(191) | Indexed; used as list filters |
| `personName`, `contactNumber` | varchar(191) NOT NULL | Contact person; `contactNumber` is the dedupe key for `/check-contact` |
| `dateOfBirth` | datetime | |
| `customerStage`, `funnelStage` | varchar(191) | Pipeline position; mirrored onto `action_log_crm` at check-out |
| `gstNumber`, `panCard` | varchar(191) | |
| `ownerImage`, `shopImage` | varchar(191) | Relative upload paths, served via `/lead-accounts/image/{filename}` |
| `isActive` | tinyint(1) default 1 | Soft-delete flag |
| `pincode` | varchar(191) | Indexed; drives area/pincode scoping |
| `country`, `state`, `district`, `city`, `area`, `address` | varchar(191) | |
| `latitude`, `longitude` | double | Used for the 50 m geofence on visit check-in |
| `areaId` | bigint unsigned | → `area_crm.id` |
| `assignedToId` | varchar(191) | `deli_staff.mobile` of the owning salesman/telecaller |
| `assignedDays` | json | Which weekdays this account is visited |
| `createdById` | varchar(191) | `deli_staff.mobile` |
| `approvedById`, `approvedAt`, `isApproved` | varchar/datetime/tinyint | Legacy approval trio |
| `approval_status` | varchar(20) default `pending` | **Current** approval state (`pending`/`approved`/`rejected`). Snake_case, unlike every other column here — added later by migration |
| `verificationNotes`, `rejectionNotes` | varchar(191) | |
| `createdAt`, `updatedAt` | timestamp | camelCase, so Eloquent's default timestamp names are overridden |

> **Gotcha:** both `isApproved` (bool) and `approval_status` (string) exist. `approval_status`
> is authoritative; `isApproved` is kept in sync for older readers.

## action_log_crm
The activity spine: one row per salesman visit or telecaller call outcome. Also stores
standalone **merchandise photo logs** (`outcome_slug = 'merchandise'`) — there is no
separate merchandise table. Used by `ActionLogController`, `BeatPlanController`,
`AccountHistoryController`, `CallLogController`.

| Column | Type | Notes |
|---|---|---|
| `employee_mobile` | varchar(255) NOT NULL | `deli_staff.mobile` |
| `role` | enum('salesman','telecaller') default salesman | Which flow wrote the row |
| `account_id` | varchar(255) NOT NULL | Lead UUID or `user.userid` |
| `account_type` | enum('lead','customer') | |
| `beat_plan_id` | bigint unsigned | → `beat_plan_crm.id`, if the visit came from a plan |
| `check_in_at` / `check_out_at` | timestamp | Renamed from `visit_in_at`/`visit_out_at` |
| `check_in_lat/lng`, `check_out_lat/lng` | decimal(10,7) | Geofence evidence |
| `duration_seconds` | int unsigned | Derived at check-out |
| `outcome_slug` / `outcome_name` | varchar(100)/(150) | → `action_log_stage_crm.slug`/`.name`. Renamed from `funnel_slug`/`funnel_name` |
| `order_no` | varchar(50) | Set when the visit produced an order |
| `status` | enum('visited','missed','skipped') default visited | |
| `call_outcome`, `call_status` | varchar(30)/(60) | Telecaller path only |
| `is_invalid_call` | tinyint(1) default 0 | |
| `call_log_id` | bigint unsigned | → `call_log_crm.id` |
| `conversation_notes`, `discussion_points` | text | |
| `customer_stage`, `funnel_stage` | varchar(40) | Snapshot copied from the account at check-out |
| `payment_collected` | decimal(12,2) | Cash collected on the visit |
| `payment_mode` | varchar(30) | |
| `market_note` | text | Competitor/market intel |
| `follow_up_date`, `follow_up_note` | date/varchar(255) | Mirrors into `beat_plan_followup_crm` |
| `general_notes`, `notes_related_to` | text/varchar(150) | |
| `images` | json | Uploaded photo paths (merchandise logs use this) |
| `created_at`, `updated_at` | timestamp | |

`id` is the only unused column.

## action_log_stage_crm
Lookup of selectable outcomes shown at check-out. Used by `ActionLogController`.

| Column | Type | Notes |
|---|---|---|
| `id` | bigint unsigned **PK** | |
| `slug` | varchar(100) **UNI** | Stored on `action_log_crm.outcome_slug` |
| `name` | varchar(150) | Display label |
| `sort_order` | int unsigned default 0 | UI order |
| `is_active` | tinyint(1) default 1 | Hides retired outcomes without deleting history |

## area_crm
| Column | Type | Notes |
|---|---|---|
| `id` | bigint unsigned **PK** | |
| `area_name` | varchar(255) NOT NULL | |
| `pincodes` | json | Pincode list covered by this area |

## area_assign_crm
Which areas an employee covers. One row per employee (`employee_id` is **UNIQUE**), with
the areas denormalised into JSON arrays rather than a join table.

| Column | Type | Notes |
|---|---|---|
| `id` | bigint unsigned **PK** | |
| `employee_id` | bigint unsigned **UNI** | `deli_staff.deli_id` — one of the few places the numeric id is used instead of `mobile` |
| `area_ids` | json NOT NULL | `area_crm.id` list |
| `area_names` | json NOT NULL | Denormalised names; goes stale if an area is renamed |

## incharge_assign_crm
Same shape, one level up the hierarchy.

| Column | Type | Notes |
|---|---|---|
| `id` | bigint unsigned **PK** | |
| `head_incharge_id` | bigint unsigned **UNI** | `deli_staff.deli_id` |
| `incharge_ids` | json NOT NULL | Reporting incharges |
| `incharge_names` | json NOT NULL | Denormalised, same staleness caveat |

## attendance_crm
One row per employee per day. Used by `AttendanceController` and `TrackingController`.

| Column | Type | Notes |
|---|---|---|
| `employee_mobile` | varchar(20) NOT NULL | |
| `date` | date NOT NULL | IST calendar day |
| `punch_in_time`, `punch_out_time` | datetime | Naive IST |
| `punch_in_photo`, `punch_out_photo` | varchar(255) | Selfie paths |
| `punch_in_location`, `punch_out_location` | json | `{lat, lng}` |
| `last_ping_at` | datetime | Heartbeat; drives `auto_closed` |
| `was_interrupted` | tinyint(1) default 0 | Tracking gap detected |
| `total_distance_km` | double | Sum over the day's pings |
| `route_snapped` | json | OSRM map-matched polyline |
| `auto_closed` | tinyint(1) default 0 | Shift closed by the system, not the user |
| `break_details` | json | Break intervals |
| `total_work_minutes`, `total_break_minutes` | int | |
| `is_late`, `is_early_out`, `is_early_in` | tinyint(1) | Against `deli_staff.punch_in_time`/`punch_out_time` + `grace_minutes` |
| `late_reason`, `early_out_reason`, `early_in_reason` | text | Required when the matching flag is set |
| `status` | enum('on_time','pending','approved','rejected','early_in') | `pending` when an exception needs sign-off |
| `admin_notes` | text | |
| `approved_by`, `approved_at` | varchar(20)/datetime | `deli_staff.mobile` of the approver |

`id`, `created_at`, `updated_at` unused.

## location_pings_crm
GPS breadcrumbs, written only while punched in. Used by `TrackingController`.

| Column | Type | Notes |
|---|---|---|
| `employee_mobile` | varchar(20) NOT NULL | |
| `date` | date NOT NULL | Partition key for day queries |
| `lat`, `lng` | decimal(10,7) NOT NULL | |
| `accuracy`, `speed` | decimal(8,2) | Device-reported |
| `heading` | decimal(6,2) | Degrees |
| `battery` | tinyint unsigned | 0–100 |
| `is_mock` | tinyint(1) default 0 | **Any simulated/test ping must set this.** Never write synthetic tracking data with `is_mock = 0` |
| `recorded_at` | datetime NOT NULL | Device time, not server time |

## beat_plan_crm
Recurring visit schedule. Used by `BeatPlanController`.

| Column | Type | Notes |
|---|---|---|
| `id` | bigint unsigned **PK** | |
| `account_id` | varchar(255) NOT NULL | Lead UUID or `user.userid` |
| `account_type` | varchar(255) default `lead` | Plain varchar here, not an enum |
| `salesman_id` | varchar(20) NOT NULL | `deli_staff.mobile` |
| `frequency` | enum('weekly','monthly','n_days','specific_dates') | Selects which of the next five columns applies |
| `days` | json | `weekly` — weekday numbers |
| `week_anchor_date` | date | `weekly` — anchors the repeating week |
| `month_date` | tinyint unsigned | `monthly` — day of month |
| `specific_dates` | json | `specific_dates` — explicit date list |
| `interval_days` | smallint unsigned | `n_days` — gap between visits |
| `appointment_date` | datetime | One-off appointment |
| `start_date` | date | First eligible date |
| `is_active` | tinyint(1) default 1 | |

> Only the columns matching `frequency` are populated; the rest stay null. Read them
> through that switch, never unconditionally.

## beat_plan_followup_crm
A one-off follow-up scheduled from the check-out popup. Surfaces on the future day's Beat
Plan (salesman), Worklist (telecaller) and the Callbacks screen.

| Column | Type | Notes |
|---|---|---|
| `id` | bigint unsigned **PK** | |
| `account_id` | varchar(255) NOT NULL | |
| `account_type` | enum('lead','customer') | |
| `staff_id` | varchar(20) NOT NULL | `deli_staff.mobile` of whoever scheduled it |
| `due_date` | date NOT NULL | Indexed with `staff_id`/`done` |
| `note` | varchar(255) | |
| `source_action_log_id` | bigint unsigned | → `action_log_crm.id` |
| `done`, `done_at` | tinyint(1)/timestamp | |

## call_log_crm
Telecaller call records — manual entries and Knowlarity webhook rows in one table. Used
by `CallLogController`, `KnowlarityCallController`, `KnowlarityWebhookController`,
`TelecallerController`, `AccountHistoryController`.

| Column | Type | Notes |
|---|---|---|
| `id` | bigint unsigned **PK** | |
| `employee_mobile` | varchar(255) | `deli_staff.mobile`. Nullable — an unmatched inbound webhook has no agent yet |
| `source` | varchar(255) default `manual` | `manual` vs Knowlarity |
| `direction` | varchar(255) | inbound/outbound |
| `knowlarity_call_id` | varchar(255) **MUL** | Dedupe key for webhook replays |
| `duration_seconds` | int unsigned | |
| `recording_url` | varchar(255) | Playback gated by `canAccessCallLog()` — own call, admin, or a descendant's |
| `raw_payload` | json | Verbatim webhook body, kept for reconciliation |
| `account_id` | varchar(255) | |
| `account_type` | enum('lead','customer','unknown') default `unknown` | **`unknown` exists here only** — a call from an unrecognised number |
| `call_outcome` | enum(answered, busy, no_answer, switch_off, invalid, callback, pending, complaint) | |
| `notes` | text | |
| `follow_up_date` | date | |
| `callback_done` | tinyint(1) default 0 | |
| `called_at` | timestamp default CURRENT_TIMESTAMP | **Naive IST wall-clock.** Date-window filters resolve to `[00:00:00 … 23:59:59]` IST — no UTC clipping |

## call_scripts_crm
| Column | Type | Notes |
|---|---|---|
| `id` | bigint unsigned **PK** | |
| `employee_mobile` | varchar(255) NOT NULL | Scripts are per-telecaller, not global |
| `title` | varchar(255) NOT NULL | |
| `stage_label` | varchar(255) | Which funnel stage it suits |
| `lines` | json NOT NULL | Ordered script lines |
| `sort_order` | int default 0 | |

## complaint_crm
| Column | Type | Notes |
|---|---|---|
| `account_id` | varchar(255) NOT NULL | |
| `account_type` | enum('lead','customer') NOT NULL | |
| `source_channel` | enum('telecaller_call','salesman_visit') NOT NULL | Which flow raised it |
| `raised_by` | varchar(255) NOT NULL | `deli_staff.mobile` |
| `assigned_to`, `assigned_by`, `assigned_at` | varchar(255)/timestamp | |
| `call_log_id` | bigint unsigned | → `call_log_crm.id` when raised from a call |
| `beat_plan_id` | bigint unsigned | → `beat_plan_crm.id` when raised from a visit |
| `category` | varchar(255) NOT NULL | |
| `description` | text NOT NULL | |
| `status` | enum('open','in_progress','resolved','closed') default open | Indexed |
| `resolution_notes`, `resolved_by`, `resolved_at` | text/varchar/timestamp | |
| `created_at` | timestamp | |

`id` and `updated_at` unused.

## telecaller_label_crm
| Column | Type | Notes |
|---|---|---|
| `employee_mobile` | varchar(255) NOT NULL | Labels are private to the telecaller who set them |
| `account_id` | varchar(255) NOT NULL | |
| `account_type` | enum('lead','customer') NOT NULL | |
| `label` | varchar(50) NOT NULL | |

## role_crm
| Column | Type | Notes |
|---|---|---|
| `id` | bigint unsigned **PK** | |
| `role_name` | varchar(50) **UNI** | Lookup only — `deli_staff.role` is free text and does **not** FK to this |
| `created_at`, `updated_at` | timestamp | |

---

# Shared / parent-app tables — do not alter existing columns

## cart
Consumer-app cart table, now **also** the store for the un-submitted Create Sales Order
draft (product decision, 2026-09-05 — replaced `sales_order_draft_crm`). Used by
`SalesOrderDraftController` (`GET`/`PUT`/`DELETE /api/order-draft`).

One row per (staff member, account), `ctype_id = 'crm_sales_draft'`, whole draft in
`draft_payload`. A salesman's in-person draft and a telecaller's phone draft for the same
shop stay independent (`staff_id` is part of the key). The row is deleted on checkout; on
read each item's `max_qty` is re-resolved against live `vendor_products` stock.

**Only CRM-added columns may be written by the CRM. Never touch the consumer-app columns
of a non-CRM row.**

| Column | Type | Notes |
|---|---|---|
| `cart_id` | int **PK**, no AUTO_INCREMENT | Allocated `MAX(cart_id)+1` under `lockForUpdate()`, same pattern as `orders.order_id` |
| `userid` | bigint NOT NULL | Customer `user.userid`; **`0` for a lead draft** |
| `ctype_id` | varchar(250) default `vegetables_fruits` | CRM writes `crm_sales_draft` — a value no `cart_type` row maps to, so consumer cart queries (filter by `userid` + a real `ctype_id`) never return these rows |
| `product_id` | bigint NOT NULL | CRM writes `0` — placeholder only |
| `pack_id` | varchar(255) NOT NULL | CRM writes `crmdraft:{staff}|{type}|{ref}` so the pre-existing `UNIQUE(userid, product_id, pack_id, addressId)` stays unique per (staff, account) and can't collide with a real row (whose `product_id` is never 0) |
| `addressId` | int NOT NULL | CRM writes `0` — placeholder only |
| `vendor_product_id`, `quantity`, `total` | — | CRM writes `0` — placeholders |
| `created_at` | timestamp | CRM reuses this as **last-saved time**, touched on every autosave |
| `staff_id` | varchar(20) NULL — *CRM-added* | `deli_staff.mobile` of the draft owner |
| `account_ref` | varchar(64) NULL — *CRM-added* | Lead UUID or `user.userid` |
| `account_type` | varchar(16) NULL — *CRM-added* | `lead` / `customer` |
| `draft_payload` | longtext NULL — *CRM-added* | Whole draft JSON: `items[]` (incl. hand-typed lines), `addons[]`, `narration`, `document_date`, `expected_date`, `delivery_address` |

CRM-added `UNIQUE(staff_id, account_ref, account_type)` (`cart_crm_draft_unique`) — the
autosave upsert key. Consumer rows leave all three NULL; NULLs don't collide in a unique
index.

## deli_staff
**The core auth table** — every non-customer login (salesman, telecaller, incharge,
teleadmin, admin, driver), despite the delivery-oriented name. Used by nearly every
controller.

| Column | Type | Notes |
|---|---|---|
| `deli_id` | int unsigned **PK** | Referenced by `area_assign_crm.employee_id` and `incharge_assign_crm.head_incharge_id` — everywhere else staff are keyed by `mobile` |
| `admin_id` | int unsigned default 0 | **Which vendor this staff member sells for.** Scopes `vendor_products` pricing in `ProductController::search` |
| `role` | varchar(20) default `driver` | Free text, no FK. The 12 values live in the data today: `driver` (17), `telecaller` (6), `head_incharge` (5), `zonal_incharge` (5), `counter` (5), `salesman` (5), `teleadmin` (5), `area_incharge` (5), `dispatch_manager` (2), `cashier` (2), `billing_manager` (2), `admin` (1). There is no plain `incharge` role |
| `name` | text NOT NULL | |
| `mobile` | varchar(20) **UNI** | **The staff identity used across all CRM tables** |
| `password` | varchar(250) | **Doubles as the OTP code.** `OtpAuthController` verifies with `$staff->password === $request->otp` |
| `sess_id` | varchar(250) | |
| `lat`, `lng` | double(10,8)/(11,8) | Last known position |
| `pincode`, `city`, `state` | varchar | |
| `location_last_updated` | timestamp default CURRENT_TIMESTAMP | |
| `is_locked` | tinyint unsigned default 0 | Blocks login |
| `punch_in_time`, `punch_out_time` | time, defaults 09:00 / 18:00 | Expected shift, per employee |
| `grace_minutes` | int default 15 | Feeds `attendance_crm.is_late` |
| `approval_required` | tinyint(1) default 1 | Whether attendance exceptions need sign-off |

> **`otp` and `otp_expires_at` columns exist and are dead.** A CRM migration added them,
> but the OTP flow settled on reusing `password`. Don't write to them expecting an effect,
> and don't assume OTPs expire — nothing enforces `otp_expires_at`.

Also unused: `permissions`, `is_record_locked`.

## user
Registered customer accounts. Note the singular name — `users` (plural) is unused Laravel
scaffolding.

| Column | Type | Notes |
|---|---|---|
| `userid` | bigint unsigned | The customer id used as `account_id` when `account_type = 'customer'`, and as `orders.buyer_userid` |
| `email` | varchar(250) NOT NULL | Defaults to a single space, not `''` |
| `contactno` | varchar(250) NOT NULL | |
| `name` | text NOT NULL | |
| `account_state` | varchar(250) default `incomplete` | |
| `address`, `latitude`, `longitude` | text/float(10,6) | The account's own address, distinct from `user_addresses` |
| `shop_name`, `shop_address` | varchar(255) | What the CRM shows as the business title |
| `user_type` | enum('B2C','B2B') NOT NULL | |
| `is_approved` | enum('YES','NO','REQUESTED') default YES | String enum, not boolean |
| `session_id`, `push_notif_id` | text NOT NULL | |
| `password` | varchar(250) | |
| `pincode`, `city`, `state` | varchar | |
| `lead_account_id` | varchar(36) | → `LeadsAccount_crm.id`. **Added by a CRM migration** — the only link back to the lead a customer was converted from |

## user_addresses
The customer's saved address book. A customer can have several; `is_default` picks one.

| Column | Type | Notes |
|---|---|---|
| `id` | int | |
| `user_id` | int | → `user.userid` |
| `address` | varchar(255) NOT NULL | |
| `lat`, `lng` | double(10,8)/(11,8) NOT NULL | |
| `type` | enum('Home','Office') NOT NULL | |
| `is_default` | enum('0','1') NOT NULL | **String enum** — compare against `'1'`, not `1` or `true` |

> Not every customer has a row here: **22 of 2618** `user` rows have no saved address at
> all, falling back to the flat `user.address` column. Code that requires an address must
> handle that.

## orders
Real sales orders. Written by `SalesOrderController`, read by `OrderListController` and
`AccountHistoryController`. The CRM only ever creates orders in `order_state = 'pending'`
— no invoicing, no stock movement.

| Column | Type | Notes |
|---|---|---|
| `order_id` | bigint unsigned **PK** | **No AUTO_INCREMENT** — see the allocation note below |
| `master_order_id` | int default 0 | Set equal to `order_id`; the `master_orders` twin |
| `txn_id` | varchar(250) NOT NULL | CRM writes `CRM-{id}-{unix}`; consumer app writes a random hex hash |
| `buyer_userid` | bigint unsigned NOT NULL | → `user.userid` |
| `start_time`, `last_update_time` | int unsigned | **Unix timestamps**, not datetimes |
| `short_datetime` | text NOT NULL | Pre-formatted `d-M-y h:i A` display string |
| `order_state` | varchar(250) NOT NULL | CRM writes only `pending`; parent app moves it to `invoiced` etc. |
| `payment_method` | varchar(250) default `cod` | CRM hardcodes `cod` |
| `payment_status` | varchar(250) default `not_paid` | |
| `items_count` | int unsigned | |
| `delivery_charge` | decimal(10,0) | **Zero decimal places** — the CRM folds addon charges (Hamali/Transport/…) in here, so they round to whole rupees |
| `order_total` | decimal(12,2) unsigned | |
| `before_discount`, `discount` | decimal(10,2) | |
| `bill_amount` | int | |
| `delivery_info` | text NOT NULL | JSON `{name, address, latitude, longitude}` |
| `area_name` | text | |
| `feedback` | varchar(100) NOT NULL | |
| `admin_id` | bigint unsigned default 0 | CRM writes 0 |
| `amountReceivedInfo` | longtext | camelCase, unlike its neighbours |
| `time_slot` | varchar(250) default `Now` | CRM stores the **expected delivery date** as a `dd/MM/yyyy` string here |
| `bill_dt` | date | Document date (`Y-m-d`) |
| `department` | varchar(100) | |
| `bill_narration` | text | **Added by a CRM migration** |
| `invoice_pdf_url` | varchar(500) | Read-only for the CRM |
| `idempotency_key` | varchar(64) **UNI** | Pre-checked before insert so a retry replays instead of duplicating |

> **Id allocation.** `order_id` and `master_orders.id` come from one counter but live in
> two tables. Allocating from `MAX(orders.order_id)` alone is wrong: the consumer app
> writes its `master_orders` row first (at payment initiation) and the `orders` row only
> after payment clears, so an abandoned checkout leaves a `master_orders` id with no
> `orders` twin. `MAX(orders.order_id) + 1` then hits that orphan, the `master_orders`
> insert dies on a duplicate PK, the transaction rolls back, and the next attempt picks
> the same doomed id — CRM checkout wedges permanently. `SalesOrderController::nextFreeOrderId()`
> therefore takes the max **across both tables**, with a bounded retry for the residual race.

Unused: `bill_no`, `invoice_number`, `charges_json`, `expected_date`, `bill_roff`,
`doc_year`, the six `sales_return_*` columns, `salesman_id`, `ctype_id`, `trip_id`,
`delivered_time`, `deli_id`.

## master_orders
The order header twin. All 13 columns are written by the CRM.

| Column | Type | Notes |
|---|---|---|
| `id` | int **PK** | Same value as `orders.order_id`. No AUTO_INCREMENT |
| `user_id` | int NOT NULL | → `user.userid` |
| `txn_id` | varchar(255) NOT NULL | CRM writes `CRM-{id}` (no timestamp suffix, unlike `orders.txn_id`) |
| `payment_status` | varchar(255) NOT NULL | CRM `not_paid`; consumer app uses `pms` for pending payment |
| `order_count` | int NOT NULL | Item count |
| `payment_method` | varchar(255) NOT NULL | CRM `cod`; consumer app `pms` |
| `delivery_info` | text NOT NULL | JSON. Consumer-app rows also carry `couponCode`, `expressDelivery`, `driverName` — the CRM never writes those |
| `order_total`, `delivery_charge`, `discount`, `before_discount` | float(10,2) | `float`, unlike `orders`' `decimal` |
| `status` | enum('1','0') NOT NULL | String enum |
| `created_at` | datetime NOT NULL | |

## orders_item
| Column | Type | Notes |
|---|---|---|
| `item_id` | bigint unsigned **PK** | Global sequence across all orders. **No AUTO_INCREMENT** — `MAX + 1` |
| `order_id` | bigint unsigned NOT NULL | |
| `product_id` | bigint unsigned NOT NULL | **NOT NULL** — this is why the CRM refuses free-text items and every line must resolve to a real `product` row |
| `pinfo` | text NOT NULL | JSON: `{unit, ps, price_inclusive, unit_price_inclusive, tax_percent, sgst_percent, cgst_percent, discount_percent}`. `ps` is the catalog pack label, surfaced back as `pack_size` |
| `quantity` | mediumint unsigned | Integer only — no fractional quantities |
| `item_price`, `item_total` | decimal(12,2) unsigned | **Tax-inclusive** (`price_inclusive: true`); tax is extracted out, never added on top |
| `qty_delivered` | int | Written by the fulfilment side |
| `commission` | double(10,2) NOT NULL | CRM writes 0 |

## product
Read-only catalog access.

| Column | Type | Notes |
|---|---|---|
| `product_id` | bigint unsigned **PK** | Serialised to the client as a **string** |
| `name` | text NOT NULL | Collated `utf8mb4_bin` — **case-sensitive** (so are `short_name` and `keywords`). Search must force both sides through `LOWER()` or it silently returns nothing |
| `hsn_code` | varchar(10) NOT NULL | |
| `gst_percent` | decimal(5,2) NOT NULL | **Do not use as the tax source** — 0.00 for 6091 of 12659 live products (48%). Last-resort fallback inside `ProductTaxResolver` only |
| `stock_uom` | int | → `units_master.unit_id`. A numeric id, not a label; `ProductController` left-joins to return `unit_name` |
| `cat_id`, `parent_cat_id` | int unsigned | **Inverted from what the names suggest:** `parent_cat_id` is the top-level category and `cat_id` the subcategory |
| `is_published`, `is_deleted` | tinyint | Both must be filtered — published `= 1`, deleted `= 0` |

Pack pricing lives in `vendor_products`, **not** in `product.packs` (that column exists but
is unused here).

## vendor_products
Per-vendor pack pricing and stock. The same product is priced differently per vendor, so
which row applies depends on the logged-in staff member's `deli_staff.admin_id`.

| Column | Type | Notes |
|---|---|---|
| `id` | int | Surfaced to the client as `vendor_product_id` |
| `admin_vendor_id` | int NOT NULL | Matched against `deli_staff.admin_id` |
| `product_id` | int NOT NULL | |
| `packs` | text NOT NULL | JSON object **keyed by pack id**: `{"diGd": {"tx": "1 kg", "op": 90, "rp": 60, "ps": "1", "pu": "kg", "pi": "diGd", "stk": 42}}` — `tx` label, `op` MRP, `rp` selling price, `stk` stock |
| `default_pack_id` | varchar(255) | Key into `packs` |
| `status` | enum('1','0') NOT NULL | Filter on `'1'` (string) |

> Most `(product, vendor)` pairs have **no row at all**. A product with no listing for the
> current vendor has no price and can't be sold — callers must handle an empty result.
> Every pack of a product draws on the same physical stock pool, so any one pack's `stk`
> already reflects the shared figure.

## product_taxes
The authoritative GST source, via `ProductTaxResolver`.

| Column | Type | Notes |
|---|---|---|
| `id` | bigint unsigned **PK** | Ordering by it keeps the newest row per component |
| `product_id` | bigint unsigned | |
| `tax_id` | bigint unsigned | → `taxes.id` |
| `tax_percent` | decimal(5,2) | |
| `effective_from`, `effective_to` | date | Null means open-ended at that end |

> Two data hazards the resolver works around: **duplicate** `(product_id, tax_name)` rows
> from repeated backfills (summing them doubles the rate — it overwrites by `id` instead),
> and **orphaned** `tax_id` values with no `taxes` row (excluded by the inner join).

## taxes
| Column | Type | Notes |
|---|---|---|
| `id` | bigint unsigned | **Not a declared primary key** |
| `tax_name` | varchar(150) NOT NULL | `SGST` / `CGST` / `IGST` / `CESS`. Upper-cased before matching |
| `is_active` | tinyint(1) default 1 | Inactive components are ignored |

## units_master
| Column | Type | Notes |
|---|---|---|
| `unit_id` | int **UNI** | Target of `product.stock_uom` |
| `unit_name` | varchar(100) NOT NULL | `KG`, `NOS`, `PCS`, `BOX`, `DOZEN`… Note it's `DOZEN`, not `DOZ` |
| `serial_no` | int | Display order |
| `is_active` | tinyint(1) default 1 | The dropdown filters on this; name resolution for an existing product does not |

## admin
Vendor organisations. Only two columns are read, to label an order with its vendor.

| Column | Type | Notes |
|---|---|---|
| `userid` | int unsigned **PK** | Matches `deli_staff.admin_id` |
| `name` | text NOT NULL | |

The other 30 columns (org GST, bank details, QR/UPI, licences) are untouched.

---

# Deliberately not used

**`cart_type`** is the consumer app's registry of cart taxonomies (`vegetables_fruits`,
`balaji_grocery`, `in_store`, `fashion`) carrying express/min-total/delivery-charge rules.
`cart.ctype_id` is a taxonomy key into it. The CRM reads nothing from `cart_type`; its
`crm_sales_draft` sentinel deliberately has no row here, which is what keeps CRM draft
rows out of every consumer-app cart query.

**History:** the CRM once wrote `in_store` rows to `cart` as a real per-line cart — wrong
and destructive, because `cart`'s `UNIQUE KEY (userid, product_id, pack_id, addressId)`
omits `ctype_id`, so a CRM upsert matched (and a CRM clear deleted) the customer's own
consumer-app cart line for the same product+pack. That was replaced by
`sales_order_draft_crm` on 2026-09-03, which was in turn folded back into `cart` on
2026-09-05 — this time as a **single JSON row** with placeholder `product_id = 0`, so the
same unique key now guarantees isolation instead of breaking it. See the `cart` section.

---

# Relationships

```
deli_staff.mobile ──┬─→ action_log_crm.employee_mobile
                    ├─→ attendance_crm.employee_mobile ──→ location_pings_crm.employee_mobile
                    ├─→ call_log_crm.employee_mobile ──→ call_scripts_crm.employee_mobile
                    ├─→ beat_plan_crm.salesman_id
                    ├─→ beat_plan_followup_crm.staff_id
                    ├─→ cart.staff_id            (ctype_id = 'crm_sales_draft' rows)
                    ├─→ complaint_crm.raised_by / assigned_to / resolved_by
                    └─→ telecaller_label_crm.employee_mobile
deli_staff.deli_id ─┬─→ area_assign_crm.employee_id ──→ area_crm.id
                    └─→ incharge_assign_crm.head_incharge_id
deli_staff.admin_id ──→ admin.userid, vendor_products.admin_vendor_id

(account_id, account_type):
   'lead'     → LeadsAccount_crm.id (UUID)
   'customer' → user.userid
LeadsAccount_crm.id ←── user.lead_account_id        (conversion link)
LeadsAccount_crm.areaId ──→ area_crm.id

user.userid ──┬─→ user_addresses.user_id
              ├─→ orders.buyer_userid
              └─→ master_orders.user_id

orders.order_id ═╪═ master_orders.id          (same counter, two tables)
                 └─→ orders_item.order_id
orders_item.product_id ──→ product.product_id
product.product_id ──┬─→ product_taxes.product_id ──→ taxes.id
                     ├─→ vendor_products.product_id
                     └─→ product.stock_uom ──→ units_master.unit_id

action_log_crm.outcome_slug ──→ action_log_stage_crm.slug
action_log_crm.call_log_id  ──→ call_log_crm.id
action_log_crm.beat_plan_id ──→ beat_plan_crm.id
beat_plan_followup_crm.source_action_log_id ──→ action_log_crm.id
```

Almost none of these are enforced FK constraints — they are lookup conventions. Deleting a
parent row will not cascade or fail.

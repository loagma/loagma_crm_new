# Database — Full Understanding Guide

This explains the database from the point of view of **what this CRM did to it**:

1. **[Part 1 — Tables the CRM created](#part-1--tables-the-crm-created)** — our own `_crm`
   tables. Why each exists, how it's used, what its columns are for.
2. **[Part 2 — Pre-existing tables the CRM reuses as-is](#part-2--pre-existing-tables-the-crm-reuses-as-is)**
   — parent-app / ERP tables we read and write but never change. Why we reuse them instead
   of making our own, and how.
3. **[Part 3 — Pre-existing tables the CRM added columns to](#part-3--pre-existing-tables-the-crm-added-columns-to)**
   — the exact columns we bolted on, why, and how they're used.

For the plain column-by-column reference see [TABLES_SIMPLE.md](TABLES_SIMPLE.md); for
types, keys and edge-case gotchas see [TABLES.md](TABLES.md).

**Database:** `loagma_new` on TiDB Cloud, shared with the older ERP and the consumer app.
~123 tables exist; this CRM's Laravel backend (`server/`) touches **28** — 15 it created,
13 it borrows.

**Two facts that explain most of the design:**

- **The CRM does not own the customer, product, order or staff tables.** Those live in the
  parent system. The CRM was added *on top of* an existing grocery-distribution platform,
  so anything about a real shop, a real product price, a real order or a real login already
  had a home. The CRM only created tables for things the parent system had no concept of:
  leads, beat plans, visits, calls, attendance, complaints.
- **Staff are identified everywhere by `deli_staff.mobile`** (the phone number), not the
  numeric `deli_id`. Accounts are identified by a `(account_id, account_type)` pair —
  `'lead'` points at `LeadsAccount_crm.id` (a UUID), `'customer'` points at `user.userid`.
  Nothing is a real foreign key; they are lookup conventions.

---

# Part 1 — Tables the CRM created

All are suffixed `_crm` and owned by this repo's migrations — safe to alter. Grouped by
what they do.

## Leads

### LeadsAccount_crm — the prospect record
**Why it exists:** the parent system only knows *registered customers* (`user`). A shop
that a telecaller is still working on is not a customer yet, so it needs its own record.
On approval + conversion, a `user` row is created and pointed back here via
`user.lead_account_id`.
**How it's used:** created by a telecaller or field rep, goes through an approval flow
(`approval_status`), then is assigned to a salesman/telecaller (`assignedToId`) and visited
on a schedule (`assignedDays`). It is the account behind most `beat_plan_crm`,
`action_log_crm`, `call_log_crm` and `complaint_crm` rows.
**Column groups:**
- Identity — `id` (UUID), `accountCode`, `businessName`, `businessType`, `businessSize`
- Contact — `personName`, `contactNumber` (also the duplicate-check key), `dateOfBirth`
- Location — `pincode`, `state`, `district`, `city`, `area`, `address`, `latitude`,
  `longitude` (the lat/lng drives a 50 m geofence when a salesman checks in), `areaId`
- Compliance — `gstNumber`, `panCard`, `ownerImage`, `shopImage`
- Pipeline — `customerStage`, `funnelStage` (copied onto each visit's `action_log_crm` row
  so history survives even if the account moves stage later)
- Ownership — `assignedToId`, `assignedDays`, `createdById`
- Approval — `approval_status` is the real one; `approvedById` / `approvedAt` / `isApproved`
  are an older trio kept in sync; `verificationNotes`, `rejectionNotes`
- `isActive` — soft delete, so history rows keep pointing at something

> Odd one out: this is the only CRM table with a PascalCase name and camelCase columns.

## Field activity

### beat_plan_crm — the recurring visit schedule
**Why:** a salesman needs a repeatable "who do I visit and when". This stores the *rule*,
not the individual visits.
**How:** `frequency` picks one of weekly / monthly / every-N-days / specific-dates, and
only the columns matching that mode are filled (`days` + `week_anchor_date` for weekly,
`month_date` for monthly, `interval_days` for n_days, `specific_dates` for the list). The
daily beat list shown to the salesman is *computed* from these rows for today's date.
`appointment_date` is the one-off exception. `salesman_id` = `deli_staff.mobile`.

### beat_plan_followup_crm — a single dated follow-up
**Why:** distinct from a recurring plan — "call this shop back on Thursday" is a one-time
task, created from the check-out popup after a visit or call.
**How:** `staff_id` + `due_date` + `done` is the whole model. `source_action_log_id` links
back to the visit/call that spawned it. It surfaces on that future day's Beat Plan
(salesman), Worklist (telecaller) and the Callbacks screen. Replaced the dropped
`beat_plan_visit_crm`.

### action_log_crm — the activity spine
**Why:** one unified place for "what happened with this account" — whether it was a
salesman's physical visit or a telecaller's call. Before the 2026-09-01 rename this was
`order_funnel_response_crm`; it also absorbs standalone merchandise photo logs
(`outcome_slug = 'merchandise'`) so there is no separate merchandising table.
**How:** written at check-out. `role` says which flow wrote it. Visit columns
(`check_in_at`/`check_out_at`, the four lat/lng columns, `duration_seconds`, `status`,
`order_no`) and call columns (`call_outcome`, `call_status`, `is_invalid_call`,
`call_log_id`) are filled per `role`. `outcome_slug`/`outcome_name` snapshot the chosen
stage from `action_log_stage_crm`; `customer_stage`/`funnel_stage` snapshot the account's
pipeline position. `payment_collected`/`payment_mode`, `market_note`, `follow_up_date`,
`images` (JSON) capture the rest. Read back by the account history screen and the Team
Report.

### action_log_stage_crm — the outcome lookup
**Why:** the list of pickable visit/call outcomes has to be editable without a deploy, and
retiring one must not rewrite history.
**How:** `slug` is stored on `action_log_crm.outcome_slug`; `is_active = 0` hides an
option from the picker while old rows keep resolving. Formerly `order_funnel_crm`.

## Telecalling

### call_log_crm — every call
**Why:** the parent system has no telephony. This holds manual call entries and Knowlarity
cloud-call webhook rows in one table.
**How:** `source` distinguishes them; `knowlarity_call_id` dedupes webhook replays;
`raw_payload` (JSON) keeps the verbatim webhook for reconciliation; `recording_url`
playback is access-gated. `employee_mobile` is nullable because an inbound call from an
unknown number has no agent yet, and `account_type` can be `'unknown'` here (nowhere else).
`call_outcome` is the enum the telecaller picks. Feeds the account history and Team Report.

### call_scripts_crm — call scripts
**Why:** telecallers want saved talking points per funnel stage, and they are personal, not
global.
**How:** `employee_mobile` scopes them to one telecaller; `lines` (JSON) is the ordered
script; `stage_label` groups them; `sort_order` orders them.

### telecaller_label_crm — private account tags
**Why:** a lightweight "hot lead" / "do not call" sticky note, private to the telecaller.
**How:** `(employee_mobile, account_id, account_type)` + `label`. That's the whole table.

## Attendance & tracking

### attendance_crm — the daily shift record
**Why:** field staff punch in/out with a selfie and location; the parent system has nothing
like it.
**How:** one row per `(employee_mobile, date)`. Punch data (`punch_in_time`/`out_time`,
`_photo`, `_location` JSON), computed rollups (`total_distance_km` from the day's pings,
`route_snapped` = OSRM-matched polyline, `total_work_minutes`/`break_minutes`,
`break_details` JSON), exception flags (`is_late` / `is_early_out` / `is_early_in` vs the
staff member's expected shift + grace, each needing a `_reason`), and an approval workflow
(`status`, `admin_notes`, `approved_by`, `approved_at`). `last_ping_at` + `auto_closed`
handle a shift the app never closed.

### location_pings_crm — the GPS breadcrumb trail
**Why:** to draw the live map and compute route distance.
**How:** written only while punched in, many rows per day. `is_mock` flags a spoofed GPS
fix — **any synthetic/test ping must set it**. `recorded_at` is device time. `date` is the
partition key day queries filter on.

## Org structure

### area_crm — named service areas
**Why:** leads and staff are scoped geographically, and "area" is a business unit the
parent system doesn't model.
**How:** `area_name` + `pincodes` (JSON list). `LeadsAccount_crm.areaId` and
`area_assign_crm.area_ids` point here.

### area_assign_crm — which areas an employee covers
**Why / how:** one row per employee (`employee_id` = numeric `deli_staff.deli_id`, unique),
with `area_ids` / `area_names` as JSON arrays rather than a join table — it is only ever
read whole for one employee.

### incharge_assign_crm — the reporting hierarchy
**Why / how:** same shape one level up — `head_incharge_id` (unique) → `incharge_ids` /
`incharge_names` JSON. The Team Report walks this to build the team tree.

### role_crm — role-name lookup
**Why / how:** a dropdown source for valid role names. Note `deli_staff.role` is free text
and does **not** foreign-key to this — it is advisory only.

---

# Part 2 — Pre-existing tables the CRM reuses as-is

These belong to the parent ERP / consumer app. The CRM reads them, and for orders it also
writes them, but **it never changes their schema** (except the three in Part 3). The reason
to reuse rather than copy is always the same: **an order created in the CRM has to be a
real order the rest of the business can see, invoice and fulfil** — a private copy would be
invisible to the warehouse and the accounts team.

| Table | Why the CRM touches it | How |
|---|---|---|
| `user` | The customer an order/visit/complaint is *about*. | Read for name / shop / location; used as `account_id` when `account_type='customer'`; `userid` becomes `orders.buyer_userid`. (Also has one CRM-added column — see Part 3.) |
| `user_addresses` | A customer's real delivery addresses. | Read at checkout to fill `orders.delivery_info`; `is_default` picks one; falls back to `user.address` when the customer has no row. |
| `orders` | The real sales-order header. | The CRM **creates** rows here (always `order_state='pending'`, `payment_method='cod'`), and reads them back on the order-list and account-history screens. `order_id` has no AUTO_INCREMENT, so it is allocated `MAX+1` across `orders`+`master_orders` under a lock. (One CRM-added column — Part 3.) |
| `master_orders` | The consumer app's parallel header; the parent platform expects every `orders` row to have a twin here. | The CRM writes all 13 columns at checkout so the pair stays consistent; same `id` as `orders.order_id`. |
| `orders_item` | The real order line items. | Written at checkout, read on order-list / history. `product_id` is NOT NULL — this is why the CRM refuses free-text items and every line must resolve to a catalog product. |
| `product` | The product catalog the sales-order screen searches. | Read-only. Must filter `is_published=1` and `is_deleted=0`; `name` is a case-sensitive collation so search forces `LOWER()`; `stock_uom` joins to `units_master`. Pricing is **not** taken from here. |
| `vendor_products` | The actual per-vendor pack pricing and stock. | Read-only. The row that applies depends on the logged-in staff member's `deli_staff.admin_id` = `admin_vendor_id`. `packs` JSON carries label / MRP / selling price / stock per pack. No row ⇒ the product can't be sold for that vendor. Also re-checked when a draft is re-opened, to refresh stock. |
| `product_taxes` | The authoritative GST rate per product, with date history. | Read-only, via `ProductTaxResolver`. Used instead of `product.gst_percent` (which is 0 for ~half the catalog). |
| `taxes` | The tax-component names (SGST / CGST / IGST / CESS). | Read-only; resolves `product_taxes.tax_id` to a name. |
| `units_master` | Unit-of-measure labels (KG / NOS / BOX / DOZEN …). | Read-only; resolves the numeric `product.stock_uom`; also the unit dropdown. |
| `admin` | The vendor organisation. | Read-only, name only, to label an order with its vendor. `userid` = `deli_staff.admin_id`. |
| `deli_staff` | **The core auth table** — every non-customer login. | Read by almost every controller for identity, role, vendor and last position. The CRM added several columns to it — see Part 3. |

Not used at all: `cart_type` (consumer-app cart-rules registry) and the eight Laravel
scaffolding tables (`cache`, `jobs`, `sessions`, `users` plural, …).

---

# Part 3 — Pre-existing tables the CRM added columns to

Every addition here is **nullable and additive** — no existing row is rewritten, and each
migration guards with `hasColumn` in case the parent app adds the same name first. Existing
columns of these tables are still off-limits.

## deli_staff — turned a delivery-boy table into the CRM's staff table

`deli_staff` predates the CRM and was built for delivery drivers. The CRM reused it as the
single login table for salesmen, telecallers, incharges and admins, which meant adding
everything those roles need.

| Column(s) | Migration | Why added | How used |
|---|---|---|---|
| `otp`, `otp_expires_at` | `2026_05_11_...add_otp_columns` | Intended for an OTP login flow. | **Dead.** The OTP flow ended up reusing the `password` column as the code, so nothing reads or expires these. |
| `lat`, `lng` | `2026_05_23_...add_geo_password_admin` | Store each staff member's last known position. | Written by the tracking pings; read for the "where is everyone" view. |
| `password` | same | Give staff an actual credential (drivers didn't need one). | The login credential — and `OtpAuthController` also compares it against the submitted OTP code. |
| `admin_id` | same | Say which vendor org a staff member sells for. | Scopes `vendor_products` pricing in product search; joins to `admin` for the order's vendor name. |
| `punch_in_time`, `punch_out_time`, `grace_minutes` | `2026_05_27_...add_attendance_settings` | Per-employee expected shift + lateness tolerance. | `AttendanceController` compares the real punch against these to set `attendance_crm.is_late` / `is_early_*`. |
| `approval_required` | `2026_05_30_...add_approval_required` | Some staff's attendance exceptions need a manager sign-off, some don't. | Gates whether an exception row lands as `pending` vs auto-approved. |

*(Other columns the CRM reads on `deli_staff` — `pincode`, `city`, `state`, `sess_id`,
`is_locked`, `location_last_updated` — already existed on the parent table.)*

## user — one column, for the lead→customer link

| Column | Migration | Why added | How used |
|---|---|---|---|
| `lead_account_id` (varchar 36, nullable) | `2026_07_25_...add_lead_account_id_to_user_table` | When a `LeadsAccount_crm` is approved and converted, the new `user` row needs to remember which lead it came from. | The only link back from a customer to its originating lead; read by the account-history and conversion screens. |

## orders — one column, for the CRM's bill note

| Column | Migration | Why added | How used |
|---|---|---|---|
| `bill_narration` (varchar 500, nullable) | `2026_08_14_...add_bill_narration_to_orders` | The CRM's Create Sales Order sheet lets the rep type a free-text note for the bill; `orders` had no plain narration field the CRM was allowed to use. | Written at checkout from the sheet's narration box; shown on the order detail. |

## cart — four columns, to host the sales-order draft (2026-09-05)

`cart` is the consumer app's shopping cart. By product decision the CRM's un-submitted
Create Sales Order draft was moved onto it (replacing the dropped `sales_order_draft_crm`),
stored as **one JSON row per (staff, account)** rather than a row per line item.

| Column | Why added | How used |
|---|---|---|
| `staff_id` (varchar 20, nullable) | The draft belongs to a staff member; `cart` had no staff concept. | `deli_staff.mobile` of whoever is building the cart. Part of the new unique key. |
| `account_ref` (varchar 64, nullable) | The draft is for a specific lead or customer (a lead has no `userid` to use). | Lead UUID or `user.userid`. |
| `account_type` (varchar 16, nullable) | Distinguish the two. | `'lead'` / `'customer'`. |
| `draft_payload` (longtext, nullable) | `cart`'s per-line columns can't hold addons, narration, dates, a delivery address, or a hand-typed line (its `pack_id` is NOT NULL). | The entire draft as JSON: `items[]`, `addons[]`, `narration`, `document_date`, `expected_date`, `delivery_address`. |
| *new index* `cart_crm_draft_unique (staff_id, account_ref, account_type)` | The autosave needs a single-row upsert key. | Consumer rows leave all three NULL, and NULLs don't collide in a unique index. |

**How it stays out of the consumer app's way:**
- CRM rows carry `ctype_id = 'crm_sales_draft'`, a value no `cart_type` row maps to, so
  every consumer cart query (which filters by `userid` + a real `ctype_id`) skips them.
- The consumer-app NOT NULL columns are filled with inert placeholders on a CRM row:
  `product_id = 0`, `addressId = 0`,
  `pack_id = "crmdraft:{staff}|{type}|{ref}"`, `quantity = 0`, `total = 0`. The
  placeholder `pack_id` also keeps the pre-existing
  `UNIQUE(userid, product_id, pack_id, addressId)` unique per (staff, account), and it can
  never collide with a real consumer line because a real line's `product_id` is never 0.
- `cart.cart_id` has no AUTO_INCREMENT, so `SalesOrderDraftController` allocates
  `MAX(cart_id) + 1` under a row lock, the same pattern `orders.order_id` uses.

**API is unchanged:** `GET`/`PUT`/`DELETE /api/order-draft` behave exactly as before; only
the storage moved. Migration: `2026_09_05_000001_move_sales_order_draft_to_cart` (must be
run manually against production).

> **History / caution:** the CRM once wrote `in_store` rows to `cart` as a *real per-line
> cart*. That was destructive — the unique key omits `ctype_id`, so a CRM upsert matched
> and a CRM clear deleted the customer's own consumer-app cart line for the same
> product+pack. That path was replaced by `sales_order_draft_crm` (2026-09-03), then folded
> back into `cart` as the single-JSON-row design above (2026-09-05). The `product_id = 0`
> placeholder is exactly what makes the second attempt safe where the first wasn't.

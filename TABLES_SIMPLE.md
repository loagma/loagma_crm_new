# Database Tables — Loagma CRM (Simple Reference)

The database (`loagma_new`, TiDB Cloud) has ~123 tables. The Laravel backend in `server/`
only touches **28 real tables**: **15 created and owned by this CRM** (the `_crm` suffix)
and **13 shared with the older ERP / consumer app** (read, and mostly written, but the
schema is never altered here). Everything else in the DB belongs to other apps and is not
listed.

Only the tables and columns this codebase actually reads or writes are documented below,
with **what** each is for, **where** (which controller) it is used, and **why**.
For full column types, keys and gotchas see [TABLES.md](TABLES.md). For a narrative
"what the CRM created vs. borrowed vs. added-columns-to, and why" see
[DB_GUIDE.md](DB_GUIDE.md). Last verified 2026-09-05.

---

## Quick map

| Area | Tables |
|---|---|
| Auth / identity | `deli_staff` (staff), `user` (customers), `role_crm` |
| Leads & accounts | `LeadsAccount_crm`, `user`, `user_addresses` |
| Areas & hierarchy | `area_crm`, `area_assign_crm`, `incharge_assign_crm` |
| Field activity | `beat_plan_crm`, `beat_plan_followup_crm`, `action_log_crm`, `action_log_stage_crm` |
| Telecalling | `call_log_crm`, `call_scripts_crm`, `telecaller_label_crm` |
| Attendance & tracking | `attendance_crm`, `location_pings_crm` |
| Complaints | `complaint_crm` |
| Sales orders | `cart` (un-submitted draft), `orders`, `orders_item`, `master_orders` |
| Catalog & tax | `product`, `vendor_products`, `product_taxes`, `taxes`, `units_master` |
| Vendor | `admin` |

**Two cross-cutting rules:**

1. **Staff are keyed by phone number** (`deli_staff.mobile`), not `deli_id`. The column
   name changes per table: `employee_mobile`, `staff_id`, `salesman_id`, `raised_by`, …
   (Only `area_assign_crm` / `incharge_assign_crm` use the numeric `deli_id`.)
2. **Accounts are polymorphic** via `(account_id, account_type)`:
   `account_type='lead'` → `account_id` is a `LeadsAccount_crm.id` (UUID);
   `account_type='customer'` → it is a `user.userid`. No foreign keys anywhere.

---

# CRM-owned tables (15)

## LeadsAccount_crm — prospect / lead accounts
**Where:** `LeadsAccountController`, `BeatPlanController`, `ActionLogController`, `ComplaintController`, `AccountHistoryController`.
**Why:** every prospective shop starts here; on conversion a `user` row is created and linked back via `user.lead_account_id`. Drives the telecaller funnel and the salesman beat plan.
Note: PascalCase table name and camelCase columns (unlike every other CRM table).

| Column | Use |
|---|---|
| `id` | primary key, 36-char UUID |
| `accountCode` | human-facing account code (unique) |
| `businessName` | shop/business name — the account title in the UI |
| `businessType`, `businessSize` | list filters |
| `personName`, `contactNumber` | contact person; `contactNumber` is the dedupe key for `/check-contact` |
| `dateOfBirth` | contact DOB |
| `customerStage`, `funnelStage` | pipeline position; snapshotted onto `action_log_crm` at check-out |
| `gstNumber`, `panCard` | tax identifiers |
| `ownerImage`, `shopImage` | upload paths, served via `/lead-accounts/image/{file}` |
| `isActive` | soft-delete flag |
| `pincode`, `country`, `state`, `district`, `city`, `area`, `address` | location text |
| `latitude`, `longitude` | 50 m geofence check on visit check-in |
| `areaId` | → `area_crm.id` |
| `assignedToId` | `deli_staff.mobile` of the owning salesman/telecaller |
| `assignedDays` | JSON weekdays this account is visited |
| `createdById` | `deli_staff.mobile` of creator |
| `approvedById`, `approvedAt`, `isApproved` | legacy approval trio (kept in sync) |
| `approval_status` | **authoritative** approval state: pending / approved / rejected |
| `verificationNotes`, `rejectionNotes` | reviewer notes |
| `createdAt`, `updatedAt` | timestamps |

## action_log_crm — the activity spine
**Where:** `ActionLogController`, `BeatPlanController`, `AccountHistoryController`, `CallLogController`, `TeamReportController`.
**Why:** one row per salesman visit **or** telecaller call outcome — the single source for "what happened with this account". Also stores standalone merchandise photo logs (`outcome_slug='merchandise'`).
Formerly `order_funnel_response_crm`; `visit_in/out_at` renamed to `check_in/out_at`, `funnel_slug/name` to `outcome_slug/name`.

| Column | Use |
|---|---|
| `employee_mobile` | `deli_staff.mobile` |
| `role` | `salesman` or `telecaller` — which flow wrote the row |
| `account_id`, `account_type` | the visited/called account (lead or customer) |
| `beat_plan_id` | → `beat_plan_crm.id` if the visit came from a plan |
| `check_in_at`, `check_out_at` | visit start / end |
| `check_in_lat/lng`, `check_out_lat/lng` | geofence evidence |
| `duration_seconds` | derived at check-out |
| `outcome_slug`, `outcome_name` | → `action_log_stage_crm` |
| `order_no` | set when the visit produced an order |
| `status` | visited / missed / skipped |
| `call_outcome`, `call_status`, `is_invalid_call` | telecaller path only |
| `call_log_id` | → `call_log_crm.id` |
| `conversation_notes`, `discussion_points` | free text |
| `customer_stage`, `funnel_stage` | snapshot copied from the account at check-out |
| `payment_collected`, `payment_mode` | cash collected on the visit |
| `market_note` | competitor / market intel |
| `follow_up_date`, `follow_up_note` | mirrored into `beat_plan_followup_crm` |
| `general_notes`, `notes_related_to` | free text |
| `images` | JSON photo paths |
| `created_at`, `updated_at` | timestamps |

## action_log_stage_crm — outcome lookup
**Where:** `ActionLogController`.
**Why:** the selectable list of visit/call outcomes shown at check-out; `is_active` retires an option without deleting history.
Formerly `order_funnel_crm`.

| Column | Use |
|---|---|
| `id` | primary key |
| `slug` | stored on `action_log_crm.outcome_slug` |
| `name` | display label |
| `sort_order` | UI order |
| `is_active` | show / hide |

## beat_plan_crm — recurring visit schedule
**Where:** `BeatPlanController`.
**Why:** defines when a salesman should visit an account (weekly / monthly / every N days / specific dates). The daily beat list is generated from these rows.

| Column | Use |
|---|---|
| `id` | primary key |
| `account_id`, `account_type` | account to visit |
| `salesman_id` | `deli_staff.mobile` |
| `frequency` | weekly / monthly / n_days / specific_dates — selects which fields below apply |
| `days` | JSON weekday numbers (weekly) |
| `week_anchor_date` | anchors the repeating week (weekly) |
| `month_date` | day of month (monthly) |
| `specific_dates` | JSON explicit date list |
| `interval_days` | gap between visits (n_days) |
| `appointment_date` | one-off appointment |
| `start_date` | first eligible date |
| `is_active` | active flag |

## beat_plan_followup_crm — one-off follow-ups
**Where:** `BeatPlanController`, `TelecallerController`.
**Why:** a single dated follow-up scheduled from the check-out popup; surfaces on the future day's Beat Plan (salesman), Worklist (telecaller) and Callbacks screen.

| Column | Use |
|---|---|
| `id` | primary key |
| `account_id`, `account_type` | the account |
| `staff_id` | `deli_staff.mobile` of whoever scheduled it |
| `due_date` | when it is due |
| `note` | free text |
| `source_action_log_id` | → `action_log_crm.id` |
| `done`, `done_at` | completion |

## call_log_crm — telecaller call records
**Where:** `CallLogController`, `KnowlarityCallController`, `KnowlarityWebhookController`, `TelecallerController`, `AccountHistoryController`, `TeamReportController`.
**Why:** every call — manual entries and Knowlarity cloud-call webhook rows — in one table.

| Column | Use |
|---|---|
| `id` | primary key |
| `employee_mobile` | agent `deli_staff.mobile`; nullable for an unmatched inbound |
| `source` | `manual` or Knowlarity |
| `direction` | inbound / outbound |
| `knowlarity_call_id` | dedupe key for webhook replays |
| `duration_seconds` | call length |
| `recording_url` | playback, access-gated |
| `raw_payload` | verbatim webhook body |
| `account_id`, `account_type` | called account (`unknown` allowed here only) |
| `call_outcome` | answered / busy / no_answer / switch_off / invalid / callback / pending / complaint |
| `notes` | free text |
| `follow_up_date` | next follow-up |
| `callback_done` | flag |
| `called_at` | call time (naive IST) |

## call_scripts_crm — call scripts
**Where:** `CallScriptController`.
**Why:** per-telecaller canned scripts, grouped by funnel stage.

| Column | Use |
|---|---|
| `id` | primary key |
| `employee_mobile` | owner (scripts are per-telecaller) |
| `title` | script title |
| `stage_label` | which funnel stage it suits |
| `lines` | JSON ordered lines |
| `sort_order` | display order |

## telecaller_label_crm — private account labels
**Where:** `TelecallerController`.
**Why:** quick per-telecaller tags on an account (e.g. "hot lead", "do not call"); private to the telecaller who set them.

| Column | Use |
|---|---|
| `employee_mobile` | who set the label |
| `account_id`, `account_type` | the account |
| `label` | label text |

## complaint_crm — customer complaints
**Where:** `ComplaintController`.
**Why:** complaints raised from a call or a visit, with assignment and resolution tracking.

| Column | Use |
|---|---|
| `account_id`, `account_type` | the account |
| `source_channel` | telecaller_call / salesman_visit |
| `raised_by` | `deli_staff.mobile` |
| `assigned_to`, `assigned_by`, `assigned_at` | assignment |
| `call_log_id` | → `call_log_crm.id` if raised from a call |
| `beat_plan_id` | → `beat_plan_crm.id` if raised from a visit |
| `category` | complaint category |
| `description` | complaint text |
| `status` | open / in_progress / resolved / closed |
| `resolution_notes`, `resolved_by`, `resolved_at` | resolution |
| `created_at` | timestamp |

## attendance_crm — daily punch in/out
**Where:** `AttendanceController`, `TrackingController`, `TeamReportController`.
**Why:** one row per employee per day — punch in/out, breaks, route distance, late/early flags and approval.

| Column | Use |
|---|---|
| `employee_mobile` | staff |
| `date` | IST calendar day |
| `punch_in_time`, `punch_out_time` | shift times |
| `punch_in_photo`, `punch_out_photo` | selfies |
| `punch_in_location`, `punch_out_location` | JSON `{lat,lng}` |
| `last_ping_at` | heartbeat; drives `auto_closed` |
| `was_interrupted` | tracking gap detected |
| `total_distance_km` | sum over the day's pings |
| `route_snapped` | JSON map-matched polyline |
| `auto_closed` | shift closed by the system |
| `break_details` | JSON break intervals |
| `total_work_minutes`, `total_break_minutes` | totals |
| `is_late`, `is_early_out`, `is_early_in` | exception flags |
| `late_reason`, `early_out_reason`, `early_in_reason` | required when the flag is set |
| `status` | on_time / pending / approved / rejected / early_in |
| `admin_notes` | admin remarks |
| `approved_by`, `approved_at` | approver `deli_staff.mobile` |

## location_pings_crm — live GPS trail
**Where:** `TrackingController`.
**Why:** GPS breadcrumbs written only while punched in; feed the live map and `attendance_crm.total_distance_km` / `route_snapped`.

| Column | Use |
|---|---|
| `employee_mobile` | staff |
| `date` | partition key for day queries |
| `lat`, `lng` | position |
| `accuracy`, `speed`, `heading` | device-reported |
| `battery` | 0–100 |
| `is_mock` | fake-GPS flag — every synthetic ping must set this |
| `recorded_at` | device time |

## area_crm — service areas
**Where:** `AreaController`, `MastersController`, `PincodeController`.
**Why:** named areas and the pincodes they cover; leads and staff are scoped to areas.

| Column | Use |
|---|---|
| `id` | primary key |
| `area_name` | area name |
| `pincodes` | JSON list of pincodes covered |

## area_assign_crm — employee → areas
**Where:** `AreaAssignController`.
**Why:** which areas an employee covers; one row per employee, areas denormalised into JSON arrays.

| Column | Use |
|---|---|
| `id` | primary key |
| `employee_id` | `deli_staff.deli_id` (numeric id, unique) |
| `area_ids` | JSON `area_crm.id` list |
| `area_names` | JSON denormalised names |

## incharge_assign_crm — head-incharge → incharges
**Where:** `InchargeAssignController`, `TeamReportController`.
**Why:** one level up the hierarchy — which incharges report to a head incharge. Used to build the team tree for reporting.

| Column | Use |
|---|---|
| `id` | primary key |
| `head_incharge_id` | `deli_staff.deli_id` (unique) |
| `incharge_ids` | JSON reporting incharge ids |
| `incharge_names` | JSON denormalised names |

## role_crm — role name lookup
**Where:** `MastersController`.
**Why:** list of valid role names for dropdowns. `deli_staff.role` is free text and does **not** FK to this.

| Column | Use |
|---|---|
| `id` | primary key |
| `role_name` | role name (unique) |
| `created_at`, `updated_at` | timestamps |

---

# Shared / parent-app tables (13)

`cart` (below) is now **written** by the CRM — CRM-added columns only, never the
consumer-app columns. The other 12 stay read-only in schema.

## deli_staff — core auth table
**Where:** nearly every controller (`Auth`, `TrackingController`, `TeamReportController`, `ProductController`, …).
**Why:** every non-customer login — salesman, telecaller, incharge, teleadmin, admin, driver — despite the delivery-oriented name.

| Column | Use |
|---|---|
| `deli_id` | primary key; referenced by `area_assign_crm.employee_id`, `incharge_assign_crm.head_incharge_id` |
| `admin_id` | which vendor this staff sells for — scopes `vendor_products` pricing |
| `role` | free text, no FK (driver / telecaller / salesman / head_incharge / zonal_incharge / teleadmin / admin / …) |
| `name` | staff name |
| `mobile` | login id and **the staff identity used across all CRM tables** |
| `password` | login password — **also the OTP code** |
| `sess_id` | session id |
| `lat`, `lng`, `pincode`, `city`, `state` | last known position |
| `location_last_updated` | last GPS update |
| `is_locked` | blocks login |
| `punch_in_time`, `punch_out_time` | expected shift, per employee |
| `grace_minutes` | feeds `attendance_crm.is_late` |
| `approval_required` | whether attendance exceptions need sign-off |

*(Dead columns: `otp`, `otp_expires_at`, `permissions`, `is_record_locked`.)*

## user — registered customers
**Where:** `LeadsAccountController`, `AccountHistoryController`, `SalesOrderController`, `OrderListController`, `ComplaintController`.
**Why:** the customer account; used as `account_id` when `account_type='customer'` and as `orders.buyer_userid`. Singular name — `users` (plural) is unused Laravel scaffolding.

| Column | Use |
|---|---|
| `userid` | customer id |
| `email`, `contactno`, `name` | identity |
| `account_state` | account status |
| `address`, `latitude`, `longitude` | the account's own address |
| `shop_name`, `shop_address` | business title shown in the CRM |
| `user_type` | B2C / B2B |
| `is_approved` | YES / NO / REQUESTED (string enum) |
| `session_id`, `push_notif_id` | session / push token |
| `password` | login password |
| `pincode`, `city`, `state` | location |
| `lead_account_id` | → `LeadsAccount_crm.id` — link back to the converted lead |

## user_addresses — customer address book
**Where:** `SalesOrderController`, `AccountHistoryController`.
**Why:** a customer's saved delivery addresses; `is_default` picks one. Not every customer has a row — code falls back to `user.address`.

| Column | Use |
|---|---|
| `id` | primary key |
| `user_id` | → `user.userid` |
| `address` | address text |
| `lat`, `lng` | position |
| `type` | Home / Office |
| `is_default` | `'1'` / `'0'` (string enum — compare against `'1'`) |

## orders — sales order header
**Where:** written by `SalesOrderController`, read by `OrderListController`, `AccountHistoryController`.
**Why:** real sales orders. The CRM only ever creates them in `order_state='pending'` — no invoicing, no stock movement.

| Column | Use |
|---|---|
| `order_id` | primary key — **no AUTO_INCREMENT**, allocated as `MAX+1` across `orders`+`master_orders` |
| `master_order_id` | set equal to `order_id` |
| `txn_id` | CRM writes `CRM-{id}-{unix}` |
| `buyer_userid` | → `user.userid` |
| `start_time`, `last_update_time` | unix timestamps |
| `short_datetime` | pre-formatted display string |
| `order_state` | CRM writes only `pending` |
| `payment_method` | CRM hardcodes `cod` |
| `payment_status` | `not_paid` |
| `items_count` | line count |
| `delivery_charge` | whole rupees; CRM folds addon charges (Hamali/Transport) in here |
| `order_total`, `before_discount`, `discount`, `bill_amount` | amounts |
| `delivery_info` | JSON `{name,address,latitude,longitude}` |
| `area_name` | delivery area |
| `feedback` | customer feedback |
| `admin_id` | CRM writes 0 |
| `amountReceivedInfo` | payment collection info |
| `time_slot` | CRM stores the expected delivery date (`dd/MM/yyyy`) here |
| `bill_dt` | document date |
| `department` | department tag |
| `bill_narration` | bill remarks (added by CRM migration) |
| `invoice_pdf_url` | read-only for the CRM |
| `idempotency_key` | pre-checked so a retry replays instead of duplicating |

## master_orders — order header twin
**Where:** `SalesOrderController`.
**Why:** the consumer app's parallel header row; the CRM writes all 13 columns to keep the pair consistent. Same id counter as `orders.order_id`.

| Column | Use |
|---|---|
| `id` | same value as `orders.order_id`; no AUTO_INCREMENT |
| `user_id` | → `user.userid` |
| `txn_id` | CRM writes `CRM-{id}` |
| `payment_status` | `not_paid` |
| `order_count` | item count |
| `payment_method` | `cod` |
| `delivery_info` | JSON |
| `order_total`, `delivery_charge`, `discount`, `before_discount` | amounts (float) |
| `status` | `'1'` / `'0'` string enum |
| `created_at` | timestamp |

## orders_item — order line items
**Where:** `SalesOrderController`, `OrderListController`, `AccountHistoryController`.
**Why:** one row per product line. `product_id` is NOT NULL — every line must resolve to a real `product` row (no free-text items).

| Column | Use |
|---|---|
| `item_id` | primary key — global sequence, `MAX+1` |
| `order_id` | → `orders.order_id` |
| `product_id` | → `product.product_id` (required) |
| `pinfo` | JSON snapshot: unit, pack, prices, tax percentages |
| `quantity` | integer only |
| `item_price`, `item_total` | tax-inclusive amounts |
| `qty_delivered` | written by fulfilment |
| `commission` | CRM writes 0 |

## product — product catalog
**Where:** `ProductController` (read-only).
**Why:** the catalog the sales-order screen searches.

| Column | Use |
|---|---|
| `product_id` | primary key (serialised to client as string) |
| `name` | product name — `utf8mb4_bin`, **case-sensitive**, search via `LOWER()` |
| `hsn_code` | HSN tax code |
| `gst_percent` | last-resort tax fallback only (0.00 for ~48% of products) |
| `stock_uom` | → `units_master.unit_id` |
| `cat_id`, `parent_cat_id` | category — **inverted**: `parent_cat_id` is top-level |
| `is_published`, `is_deleted` | both must be filtered (published=1, deleted=0) |

*(Pricing is NOT in `product.packs` — it is in `vendor_products`.)*

## vendor_products — per-vendor pack pricing & stock
**Where:** `ProductController`, `SalesOrderController`, `SalesOrderDraftController`.
**Why:** the same product is priced differently per vendor; the applicable row depends on the staff member's `deli_staff.admin_id`. Many `(product, vendor)` pairs have no row — then the product can't be sold.

| Column | Use |
|---|---|
| `id` | surfaced as `vendor_product_id` |
| `admin_vendor_id` | matched against `deli_staff.admin_id` |
| `product_id` | → `product.product_id` |
| `packs` | JSON keyed by pack id: label `tx`, MRP `op`, selling price `rp`, stock `stk` |
| `default_pack_id` | key into `packs` |
| `status` | filter on `'1'` (string) |

## product_taxes — authoritative GST rates
**Where:** `ProductController` / `ProductTaxResolver`.
**Why:** the real per-product GST source (not `product.gst_percent`), with effective-date history.

| Column | Use |
|---|---|
| `id` | primary key; newest row per component wins |
| `product_id` | → `product.product_id` |
| `tax_id` | → `taxes.id` |
| `tax_percent` | rate |
| `effective_from`, `effective_to` | validity window (null = open-ended) |

## taxes — tax component names
**Where:** `ProductTaxResolver`.
**Why:** resolves `tax_id` to a component name (SGST / CGST / IGST / CESS).

| Column | Use |
|---|---|
| `id` | key (not a declared PK) |
| `tax_name` | SGST / CGST / IGST / CESS |
| `is_active` | inactive components ignored |

## units_master — unit of measure lookup
**Where:** `ProductController`, `MastersController`.
**Why:** resolves `product.stock_uom` (a numeric id) to a label; also the unit dropdown.

| Column | Use |
|---|---|
| `unit_id` | target of `product.stock_uom` |
| `unit_name` | KG / NOS / PCS / BOX / DOZEN … |
| `serial_no` | display order |
| `is_active` | dropdown filter |

## cart — un-submitted sales-order draft (CRM use)
**Where:** `SalesOrderDraftController` (`GET`/`PUT`/`DELETE /api/order-draft`).
**Why:** autosaves the Create Sales Order cart, one row per (staff, account), so a salesman's in-person draft and a telecaller's phone draft for the same shop stay separate. Deleted on checkout. Stored on the consumer app's `cart` table by product decision (2026-09-05), replacing the former `sales_order_draft_crm`.
**How it coexists with the consumer app:** CRM rows are tagged `ctype_id = 'crm_sales_draft'` (no `cart_type` maps to it, so consumer cart queries never see them); the whole draft sits in the new `draft_payload` JSON column; the consumer-app item columns are filled with inert placeholders (`product_id = 0`, `addressId = 0`, `pack_id = "crmdraft:{staff}|{type}|{ref}"`) purely to satisfy the existing `(userid, product_id, pack_id, addressId)` unique key.

| Column | Use |
|---|---|
| `cart_id` | primary key — **no AUTO_INCREMENT**, allocated `MAX+1` under a row lock |
| `userid` | customer `user.userid`, or `0` for a lead draft |
| `ctype_id` | `'crm_sales_draft'` for CRM rows |
| `staff_id` | *(CRM column)* `deli_staff.mobile` of the draft owner |
| `account_ref`, `account_type` | *(CRM columns)* the account (leads allowed) |
| `draft_payload` | *(CRM column)* whole draft as JSON: `items[]`, `addons[]`, `narration`, dates, `delivery_address` |
| `created_at` | last-saved time (touched on every autosave) |
| `product_id`, `vendor_product_id`, `pack_id`, `addressId`, `quantity`, `total` | placeholders on CRM rows — not read |

*CRM adds `cart_crm_draft_unique (staff_id, account_ref, account_type)`; consumer rows leave those NULL and do not collide.*

## admin — vendor organisation
**Where:** `OrderListController`, `SalesOrderController`.
**Why:** only the name is read, to label an order with its vendor.

| Column | Use |
|---|---|
| `userid` | matches `deli_staff.admin_id` |
| `name` | vendor / org name |

---

# Not used (deliberately)

- **`cart_type`** — consumer-app registry of cart taxonomies (express / min-total /
  delivery-charge rules). The CRM only reads nothing from it; its sentinel
  `crm_sales_draft` deliberately has no row here.
- **Laravel scaffolding** — `cache`, `cache_locks`, `failed_jobs`, `job_batches`, `jobs`,
  `password_reset_tokens`, `sessions`, `users` (plural). Present, unused by app code.

# Relationships (lookup conventions, not enforced FKs)

```
deli_staff.mobile  → action_log_crm / attendance_crm / call_log_crm / call_scripts_crm /
                     location_pings_crm / telecaller_label_crm  (employee_mobile)
                   → beat_plan_crm.salesman_id, beat_plan_followup_crm.staff_id,
                     cart.staff_id (crm_sales_draft rows),
                     complaint_crm.raised_by / assigned_to / resolved_by
deli_staff.deli_id → area_assign_crm.employee_id → area_crm.id
                   → incharge_assign_crm.head_incharge_id
deli_staff.admin_id → admin.userid, vendor_products.admin_vendor_id

(account_id, account_type):  'lead' → LeadsAccount_crm.id (UUID)
                             'customer' → user.userid
user.lead_account_id → LeadsAccount_crm.id            (conversion link)
LeadsAccount_crm.areaId → area_crm.id

user.userid → user_addresses.user_id, orders.buyer_userid, master_orders.user_id
orders.order_id ═ master_orders.id  (same counter) ;  orders.order_id → orders_item.order_id
orders_item.product_id → product.product_id
product.product_id → product_taxes.product_id → taxes.id
                   → vendor_products.product_id
product.stock_uom → units_master.unit_id

action_log_crm.outcome_slug → action_log_stage_crm.slug
action_log_crm.call_log_id  → call_log_crm.id
action_log_crm.beat_plan_id → beat_plan_crm.id
beat_plan_followup_crm.source_action_log_id → action_log_crm.id
```

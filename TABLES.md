# Database Tables — Loagma CRM

Only the tables the Laravel backend (`server/`) actually reads or writes. Columns and
types are pulled live from the production schema (`loagma_new`, TiDB Cloud), not from
migration files, so this reflects what's really deployed. The database has 118 tables
total — the other ~90 belong to the older shared ERP system and aren't touched by this
codebase at all (not listed here).

Legend: **PK** = primary key, **FK** = foreign key / lookup (not always a real DB constraint).

---

## 1. deli_staff
Every non-customer login — telecaller, delivery staff, incharge, teleadmin, admin. `role` is a free-text string, not a foreign key. **This is the core auth table**, not a delivery-only table despite the name.
- Used by: `OtpAuthController`, `AttendanceController`, `TrackingController`, `TelecallerController`, `ComplaintController`, `LeadsAccountController`, `BeatPlanController`, `MastersController`, `OrderListController`
- Endpoints: `/employees` (CRUD), `/send-otp`, `/verify-otp`, attendance & beat-plan routes
- Columns:
  | Column | Type | Notes |
  |---|---|---|
  | deli_id | int | PK |
  | admin_id | int | |
  | role | varchar | telecaller / deli_staff / incharge / zonal_incharge / head_incharge / teleadmin / admin |
  | name | text | |
  | mobile | varchar | login identifier |
  | password | varchar | **also doubles as the OTP code** — see note |
  | otp, otp_expires_at | varchar, datetime | unused columns, see note |
  | permissions | longtext | JSON |
  | sess_id | varchar | |
  | lat, lng | double | last known position |
  | pincode, city, state | varchar | |
  | location_last_updated | timestamp | |
  | is_locked | tinyint | account disabled |
  | punch_in_time, punch_out_time | time | shift window |
  | grace_minutes | int | late tolerance |
  | approval_required | tinyint | manual attendance approval |
- **Note:** OTP login (`OtpAuthController`) compares the incoming code straight against `password` — it does not use this table's own `otp`/`otp_expires_at` columns, and it never touches the separate `otp` table in the schema (10 rows, dead code as far as this app is concerned).

## 2. user
Customer accounts — the buyer side of the older ERP. Singular name, but holds customers, not staff.
- Used by: `SalesOrderController`, `BeatPlanController`, `ComplaintController`, `LeadsAccountController`, `TelecallerController`
- Endpoints: `/customers`
- Columns:
  | Column | Type | Notes |
  |---|---|---|
  | userid | bigint | PK |
  | name, contactno, email | text/varchar | |
  | shop_name, shop_address, shop_plot_no | varchar | |
  | user_type | enum | |
  | gst_no, party_code | varchar | |
  | latitude, longitude, pincode, city, state | float/varchar | |
  | is_approved | enum | |
  | lead_account_id | varchar | FK → `LeadsAccount_crm.id` once a lead converts |

## 3. user_addresses
Delivery addresses for a `user`, one-to-many.
- Used by: `BeatPlanController`, `LeadsAccountController`, `TelecallerController`, `OrderListController`
- Columns:
  | Column | Type | Notes |
  |---|---|---|
  | id | int | PK |
  | user_id | int | FK → `user.userid` |
  | full_name, phone_no, full_address, address | varchar | |
  | lat, lng, pincode, city_id, area_id | double/varchar | |
  | type | enum | home / shop / other |
  | is_default | enum | |

## 4. area_crm
Named areas, each holding the list of pincodes it covers.
- Used by: `AreaController`, `AreaAssignController`, `TelecallerController`
- Endpoints: `/areas` (CRUD)
- Columns: `id` (PK, bigint) · `area_name` (varchar) · `pincodes` (json)

## 5. area_assign_crm
Which areas a given telecaller/employee is responsible for.
- Used by: `AreaAssignController`, `AreaController`, `TelecallerController`
- Endpoints: `/area-assign`
- Columns: `id` (PK) · `employee_id` (FK → `deli_staff`) · `area_ids`, `area_names` (json, denormalised for fast reads)

## 6. incharge_assign_crm
Which incharges report up to a given head incharge.
- Used by: `InchargeAssignController`, `AttendanceController`, `ComplaintController`, `TelecallerController`
- Endpoints: `/incharge-assign`
- Columns: `id` (PK) · `head_incharge_id` (FK → `deli_staff`) · `incharge_ids`, `incharge_names` (json)

## 7. LeadsAccount_crm
Prospective accounts being worked through the telecaller funnel, before becoming a real `user`. **The one table that's camelCase, not snake_case** — `createdAt`, `assignedToId`, etc.
- Used by: `LeadsAccountController`, `BeatPlanController`, `ComplaintController`, `TelecallerController`, `ProcessKnowlarityCallCompleted` job
- Endpoints: `/lead-accounts`, `/customers`
- Columns:
  | Column | Type | Notes |
  |---|---|---|
  | id | char (uuid) | PK |
  | accountCode, businessName, personName, contactNumber | varchar | |
  | businessType, businessSize | varchar | |
  | customerStage, funnelStage | varchar | pipeline position |
  | gstNumber, panCard, ownerImage, shopImage | varchar | |
  | pincode, country, state, district, city, area, address, latitude, longitude | varchar/double | |
  | areaId | bigint | FK → `area_crm.id` |
  | assignedToId | varchar | FK → `deli_staff` (telecaller) |
  | assignedDays | json | |
  | isActive, isApproved, approval_status | tinyint/varchar | |
  | createdById, approvedById, approvedAt | varchar/datetime | |
  | verificationNotes, rejectionNotes | varchar | |

## 8. role_crm
The list of valid values for `deli_staff.role`.
- Used by: `MastersController`
- Endpoints: `/masters/roles` (CRUD)
- Columns: `id` (PK) · `role_name` (varchar)
- **Note:** still carries a couple of legacy role names (`incharge`, `manager`) that nothing actually checks for anymore — the real senior roles in use are `admin`, `head_incharge`, `zonal_incharge`, `teleadmin`.

## 9. units_master
Unit-of-measure lookup (kg, box, litre…) used in product pricing. Belongs to the shared/legacy schema, read-only here.
- Used by: `MastersController`
- Endpoints: `/masters/units`
- Columns: `unit_id` (PK) · `unit_name`, `dimension`, `base_unit_name` (varchar/enum) · `conversion_rate` (decimal) · `is_active` (tinyint)

## 10. attendance_crm
One row per employee per shift: punch in/out time, photo, GPS, distance travelled, break time, manager approval state.
- Used by: `AttendanceController`, `TrackingController`
- Endpoints: `/attendance/punch-in`, `/punch-out`, `/break`, `/today`, `/history`, `/confirm-punch`
- Columns:
  | Column | Type | Notes |
  |---|---|---|
  | id | bigint | PK |
  | employee_mobile | varchar | FK → `deli_staff.mobile` |
  | date | date | |
  | punch_in_time, punch_out_time | datetime | |
  | punch_in_photo, punch_out_photo | varchar | |
  | punch_in_location, punch_out_location | json | lat/lng snapshot |
  | last_ping_at | datetime | for auto-close detection |
  | was_interrupted, auto_closed | tinyint | app killed mid-shift |
  | total_distance_km, route_snapped | double/json | |
  | break_details, total_work_minutes, total_break_minutes | json/int | |
  | is_late, is_early_in, is_early_out (+ reasons) | tinyint/text | |
  | status | enum | pending / approved / rejected |
  | admin_notes, approved_by, approved_at | text/varchar/datetime | |
- **Note:** separate `attendances` and `attendance_breaks` tables also exist in the schema (1 and 4 rows) — leftovers from an earlier design, not used by this app.

## 11. location_pings_crm
One row per GPS ping while an employee is on shift — the trail behind the live map.
- Used by: `TrackingController`, `AttendanceController`
- Endpoints: `/live`, `/live-route`, `/route`
- Columns: `id` (PK) · `employee_mobile` (FK → `deli_staff.mobile`) · `date` · `lat, lng, accuracy, speed, heading` (decimal) · `battery` (tinyint) · `is_mock` (tinyint, fake-GPS detection) · `recorded_at`

## 12. beat_plan_crm
The recurrence rule — which salesman visits which account, how often.
- Used by: `BeatPlanController`
- Endpoints: `/beat-plan/assign`, `/my-plans`, `/today`, `/week`, `/stats`
- Columns:
  | Column | Type | Notes |
  |---|---|---|
  | id | bigint | PK |
  | account_id, account_type | varchar | FK → `user` or `LeadsAccount_crm` |
  | salesman_id | varchar | FK → `deli_staff` |
  | frequency | enum | daily / weekly / monthly / interval |
  | days, specific_dates, week_anchor_date, month_date, interval_days | json/date/int | recurrence rule fields |
  | appointment_date, start_date | datetime/date | |
  | is_active | tinyint | |

## 13. beat_plan_visit_crm
One concrete occurrence of a beat plan on a given day, with its completion status.
- Used by: `BeatPlanController`
- Endpoints: `/beat-plan/{id}/visit`
- Columns: `id` (PK) · `beat_plan_id` (FK → `beat_plan_crm.id`) · `account_id, salesman_id` (varchar) · `visit_date` (date) · `status` (enum: pending/done/missed) · `notes` (text)

## 14. call_log_crm
Every call made or received — outcome, recording, notes, follow-up date. Filled both directly by the app and by the Knowlarity webhook job.
- Used by: `CallLogController`, `KnowlarityCallController`, `TelecallerController`, `ProcessKnowlarityCallCompleted` job
- Endpoints: `/call-logs`, `/call-logs/{id}`, `/call-recording/{id}`, `/call-status/{id}`, `/telecaller/callbacks`, `/telecaller/call-history`
- Columns:
  | Column | Type | Notes |
  |---|---|---|
  | id | bigint | PK |
  | employee_mobile | varchar | FK → `deli_staff.mobile` |
  | source, direction | varchar | manual vs knowlarity; inbound/outbound |
  | knowlarity_call_id | varchar | webhook correlation id |
  | duration_seconds, recording_url, raw_payload | int/varchar/json | raw_payload = full webhook body |
  | account_id, account_type | varchar/enum | FK → `user` or `LeadsAccount_crm` |
  | call_outcome | enum | includes complaint, callback |
  | notes, follow_up_date, callback_done | text/date/tinyint | |
  | called_at | timestamp | |

## 15. call_scripts_crm
Canned talking points a telecaller can pull up mid-call.
- Used by: `CallScriptController`
- Endpoints: `/telecaller/scripts` (CRUD)
- Columns: `id` (PK) · `employee_mobile` (varchar, owner or shared if null) · `title, stage_label` (varchar) · `lines` (json, the script text) · `sort_order` (int)

## 16. complaint_crm
A complaint raised against an account, with an assignment and resolution workflow.
- Used by: `ComplaintController`, `CallLogController`
- Endpoints: `/complaints` (index/store), `/complaints/assigned-count`, `/complaints/{id}/status`, `/complaints/{id}/assign`
- Columns:
  | Column | Type | Notes |
  |---|---|---|
  | id | bigint | PK |
  | account_id, account_type | varchar/enum | |
  | source_channel | enum | call / visit / manual |
  | raised_by, assigned_to, assigned_by, assigned_at | varchar/timestamp | FK → `deli_staff` |
  | call_log_id, beat_plan_id | bigint | optional origin |
  | category, description | varchar/text | |
  | status | enum | open / in_progress / resolved |
  | resolution_notes, resolved_by, resolved_at | text/varchar/timestamp | |

## 17. incharge_assign_crm, area_assign_crm
(see #5 and #6 above)

## 18. order_funnel_crm
The fixed list of funnel stages a visit can be logged against (e.g. "interested", "ordered", "not interested") — a small lookup table.
- Used by: `OrderFunnelController`
- Endpoints: `/order-funnels` (`/`)
- Columns: `id` (PK) · `slug, name` (varchar) · `sort_order` (int) · `is_active` (tinyint)

## 19. order_funnel_response_crm
The actual form a telecaller/salesman submits for a visit: which funnel stage it landed on, notes, photos, visit duration.
- Used by: `OrderFunnelController`
- Endpoints: `/order-funnels/response`, `/order-funnels/responses`, `/upload-image`
- Columns:
  | Column | Type | Notes |
  |---|---|---|
  | id | bigint | PK |
  | employee_mobile, account_id, account_type | varchar | |
  | beat_plan_id | bigint | FK → `beat_plan_crm.id` |
  | visit_in_at, visit_out_at, duration_seconds | timestamp/int | |
  | funnel_slug, funnel_name | varchar | denormalised from `order_funnel_crm` |
  | general_notes, notes_related_to | text/varchar | |
  | images | json | |

## 20. telecaller_label_crm
Free-form label a telecaller can pin to an account (e.g. "hot lead", "not interested").
- Used by: `TelecallerController`
- Endpoints: `/telecaller/label`
- Columns: `id` (PK) · `employee_mobile, account_id, account_type` (varchar/enum) · `label` (varchar)

## 21. orders  *(shared/legacy table — this app writes to it directly)*
The order header: buyer, totals, payment, delivery, status.
- Used by: `SalesOrderController` (create/edit), `OrderListController` (delivery-staff views; joined to `user`, `admin`, `user_addresses`)
- Endpoints: `/orders`, `/orders/{orderId}`, `/sales-orders`, `/sales-orders/next-order-id`
- Columns:
  | Column | Type | Notes |
  |---|---|---|
  | order_id | bigint | PK |
  | bill_no, invoice_number, invoice_pdf_url | varchar/int | |
  | bill_dt, expected_date, delivered_time | date/int | |
  | bill_narration | text | |
  | buyer_userid | bigint | FK → `user.userid` |
  | admin_id | bigint | FK → `admin.userid` |
  | salesman_id, deli_id | varchar/int | FK → `deli_staff` |
  | master_order_id | int | FK → `master_orders.id` |
  | order_state, payment_status, payment_method | varchar | |
  | items_count, order_total, bill_amount, discount, before_discount, delivery_charge | int/decimal | |
  | sales_return_voucher_no, sales_return_dt, sales_return_status, sales_return_reason | varchar/date/text | returns handled on the same row |
  | trip_id, time_slot, area_name, delivery_info | int/varchar/text | |
  | idempotency_key | varchar | dedupes double-submits |
- **Note:** 36,566 rows — the largest table this app writes to. Not owned by this Laravel app (it belongs to the older ERP), but written to directly, so schema changes here affect that system too.

## 22. orders_item  *(shared/legacy)*
Line items of an order — product, quantity ordered/loaded/delivered/returned, price.
- Used by: `SalesOrderController`, `OrderListController` (joined to `product`)
- Endpoints: `/orders/{orderId}/items`
- Columns:
  | Column | Type | Notes |
  |---|---|---|
  | item_id | bigint | PK |
  | order_id | bigint | FK → `orders.order_id` |
  | product_id | bigint | FK → `product.product_id` |
  | vendor_product_id | int | |
  | pinfo, offers | text | snapshot of product info at order time |
  | quantity, qty_loaded, qty_delivered, qty_returned | mediumint/int | fulfilment tracked per stage |
  | return_reason | varchar | |
  | item_price, item_total, commission | decimal/double | |

## 23. master_orders  *(shared/legacy)*
Groups multiple `orders` rows from one checkout (a customer ordering from several vendors at once splits into one `orders` row per vendor, all under one `master_order`).
- Used by: `SalesOrderController`
- Columns: `id` (PK) · `user_id` (FK → `user.userid`) · `txn_id, payment_status, payment_method` (varchar) · `order_count, order_total, before_discount, discount, delivery_charge` (int/float) · `status` (enum)

## 24. product  *(shared/legacy, read-heavy)*
The catalog. Pack-level pricing lives inside the `packs` JSON blob on each row, not a separate table.
- Used by: `ProductController` (search), `SalesOrderController` (pricing), `ProductTaxResolver`
- Endpoints: `/products/search`, `/orders/owner/{buyerUserId}/products`
- Columns:
  | Column | Type | Notes |
  |---|---|---|
  | product_id | bigint | PK |
  | name, short_name, description, keywords | text/varchar | search fields |
  | cat_id, parent_cat_id, brand, ctype_id | int/text/varchar | |
  | display_photo, spec_params | text | |
  | packs, default_pack_id | text (json)/varchar | **real per-pack price — only ~3% of rows populate this, most fall back to a default price** |
  | hsn_code, gst_percent, is_taxable, exempt_from, exempt_to | varchar/decimal/tinyint/date | |
  | stock, in_stock, stock_uom, order_limit, buffer_limit | decimal/tinyint/varchar/int | |
  | is_published, is_used, is_deleted | tinyint | |

## 25. vendor_products  *(shared/legacy)*
Per-vendor override of a product: its own packs/pricing and stock status.
- Used by: `ProductController`
- Columns: `id` (PK) · `admin_vendor_id` (FK → `admin.userid`) · `product_id` (FK → `product.product_id`) · `packs, default_pack_id` (text/varchar) · `status, in_stock` (enum)

## 26. product_taxes & taxes  *(shared/legacy)*
Time-bounded tax rate per product, resolved against the `taxes` lookup table.
- Used by: `ProductTaxResolver` (joins `product_taxes.tax_id = taxes.id`)
- Columns:
  | Column | Type | Notes |
  |---|---|---|
  | product_taxes.product_id | bigint | FK → `product.product_id` |
  | product_taxes.tax_id | bigint | FK → `taxes.id` |
  | product_taxes.tax_percent | decimal | |
  | product_taxes.effective_from / effective_to | date | picks the row active "now" |
  | taxes.tax_category, tax_sub_category, tax_name | varchar | |
  | taxes.is_active | tinyint | |

## 27. admin  *(shared/legacy, read-only)*
Vendor/admin accounts from the older ERP. Only read here, to label who a placed order belongs to.
- Used by: joined in `OrderListController` (`orders.admin_id = admin.userid`)
- Columns: `userid` (PK) · `name, username` (text/varchar) · `org_name, org_email, org_contact_no, org_gst, org_address` (shown next to an order) · `commission` (int) · bank/payout fields (not read by this app)

---

## Infrastructure tables (Laravel defaults)
Not business logic — auto-managed by Laravel.

| Table | Purpose |
|-------|---------|
| `jobs` | Background job queue |
| `job_batches` | Batch job metadata |
| `failed_jobs` | Failed job records |
| `cache` | Application cache |
| `cache_locks` | Cache lock management |
| `sessions` | Web session storage |
| `migrations` | Migration history |

---

## Key relationships

- `deli_staff` is referenced by attendance_crm, location_pings_crm, call_log_crm, call_scripts_crm, area_assign_crm, incharge_assign_crm, complaint_crm, beat_plan_crm, orders
- `LeadsAccount_crm` is referenced by beat_plan_crm, call_log_crm, order_funnel_response_crm, telecaller_label_crm, complaint_crm, and `user.lead_account_id` once converted
- `user` is referenced by user_addresses, beat_plan_crm, orders (buyer_userid), master_orders
- `area_crm` is referenced by area_assign_crm and `LeadsAccount_crm.areaId`
- `beat_plan_crm` is referenced by beat_plan_visit_crm and order_funnel_response_crm
- `orders` is referenced by orders_item and links to master_orders, admin, user, deli_staff
- `product` is referenced by orders_item, vendor_products, product_taxes

## Corrections vs. the previous version of this doc
- Removed the `users` (plural, Laravel-default) entry — it has 0 rows and nothing in `server/app` queries it. `MastersController` does not touch it.
- `user` (singular) is the real customer table, actively used, not "legacy/minimal."
- Added: `user_addresses`, `units_master`, `complaint_crm`, and the whole Orders & Products group (`orders`, `orders_item`, `master_orders`, `product`, `vendor_products`, `product_taxes`, `taxes`, `admin`) — these are shared/legacy tables the sales-order and product-search flows read and write directly, and were missing entirely from the previous list.

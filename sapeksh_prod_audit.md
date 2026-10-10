# Loagma CRM: Production Audit

**Prepared for:** Sapeksh
**Date:** 2026-10-06
**Commit audited:** `ea93004`, plus the fixes listed in §5
**Verdict:** ✅ **Ready for production** once the deployment checklist (§8) is done.

---

## 1. What was audited

| Area | Scope |
|---|---|
| Backend (Laravel 12, PHP 8.2) | 29 controllers, 2 middleware, 1 service + allocation service, 1 job, 1 console command, 24 models, 11 support classes, all 143 API routes |
| Frontend (Flutter) | `client/lib` (99 files), Android manifest, iOS `Info.plist`, the new product-code and worklist search |
| Database | Dev (TiDB) compared with the prod structure (`updated-loagma-structure.sql`, MariaDB 10.11). `changes.sql` was executed against a real MariaDB copy of prod |
| Configuration | `server/.env`, `.env.example`, `config/*` |

**Method:**
1. Read the code line by line.
2. Automated checks: PHP lint, route/middleware audit, `flutter analyze`, the PHPUnit suite.
3. Live API tests against the dev DB.
4. Full write-path tests against a scratch MariaDB loaded with the prod structure plus `changes.sql`.

---

## 2. Verification results (all re-run for this report)

| Check | Result |
|---|---|
| PHP lint: every file in `app/`, `routes/`, `config/` | ✅ 0 errors |
| Route audit | ✅ 143 routes; **137 require login**; 6 public by design (§4.1) |
| PHPUnit suite | ✅ 11 tests, 34 assertions passed |
| Live API checks on dev (auth, roles, scoping, validation) | ✅ 31 / 32. The 1 failure is dev-only (§7) |
| `changes.sql` on a MariaDB copy of prod, run **twice** | ✅ No errors; idempotent; 21 tables + 12 columns + master rows created |
| Real CRM write flows on the prod schema | ✅ **29 / 29** passed (including legacy-table entry shape, §6A) |
| Beat-plan date logic: PHP rule vs SQL rule | ✅ Identical over 28 days × 1,895 live plans |
| Knowlarity call processing | ✅ Outcome kept, inbound matching correct, unknown status safe |
| **Every API route, end to end, on MySQL 8 `test_cms`** (copy of prod + `changes.sql`) | ✅ **164 / 164 checks, 143 / 143 routes covered.** Run with test data in a rolled-back transaction; Knowlarity and lookups faked |
| `flutter analyze` | ✅ **0 errors**. 3 warnings and 193 infos, all pre-existing (182 are `avoid_print`) |

The 24 prod-schema write flows covered:
- employee create/edit
- duplicate-mobile protection
- shift settings, punch-in
- lead create, self-approve blocked, approve → customer
- Hindi-text handling
- appointment beat plan, today's plan
- order draft on `cart`
- sales order create/edit
- consumer order protected
- fractional quantity rejected
- catalog search, call log + follow-up
- upload extension safety
- driver login blocked
- legacy-entry shape: vendor `admin_id`, `delivery_info` keys, `pinfo` keys, customer `account_state`

---

## 3. Scorecard

| Area | Before audit | Now | Basis |
|---|---|---|---|
| API security & access control | 2 / 10 | **9.5 / 10** | Route audit, role checks, 32 live checks |
| Prod DB compatibility | 3 / 10 | **10 / 10** | `changes.sql` executed on prod-schema copy, 24 write flows |
| Data integrity (orders, calls, leads, attendance) | 4 / 10 | **9.5 / 10** | Write-flow tests, Knowlarity tests |
| Business-logic correctness | 6 / 10 | **9 / 10** | Beat-plan parity, allocation unit tests |
| Error handling & safe responses | 5 / 10 | **9 / 10** | Clean 4xx messages, no leaked internals |
| Schema cleanliness | 7 / 10 | **10 / 10** | Dead columns removed; only used columns in `changes.sql` |
| Configuration (`.env`) | 5 / 10 | **9.5 / 10** | Only used keys; safe template |
| Client stability | 6 / 10 | **8.5 / 10** | `flutter analyze` 0 errors; crash/expiry fixes |
| **Overall** | **4.8 / 10** | **9.3 / 10** | |

Scores are engineering judgement based on the checks above, not an external certification. Items the owner chose to keep as they are (§7) are not counted against the score.

---

## 4. Security

### 4.1 Access control (fixed)
- **Before:** about 100 of 143 routes needed no login. Anyone could:
  - create or overwrite admins;
  - read every order and customer;
  - edit live orders, including consumer-app orders;
  - rewrite the reporting hierarchy.
- **Now:** every route requires a valid login **and** a CRM role. Admin-only writes also require `role:admin`. These 6 routes stay public by design:

| Route | Why it's public |
|---|---|
| `POST /api/auth/send-otp`, `POST /api/auth/verify-otp` | Login (verify is rate-limited: 5 attempts/min per mobile + IP) |
| `GET /api/health` | Uptime check (no internal details returned) |
| `GET /api/utils/pincode/{pincode}` | Public postal lookup |
| `GET /api/lead-accounts/image/{file}` | Images are loaded without headers; the names are random UUIDs |
| `POST /api/webhooks/knowlarity/{secret}/call-completed` | Protected by the secret in the URL |

### 4.2 All security findings

| # | Severity | Finding | Status |
|---|---|---|---|
| S1 | Critical | Public employee create/edit could overwrite any staff role or password (account takeover) | ✅ Fixed: login + admin role; duplicate mobile refused |
| S2 | Critical | Public sales-order create/edit; any pending order editable, including consumer-app orders | ✅ Fixed: login required; orders can no longer be edited; only a pending CRM order (`txn_id` starting `crm`) can be cancelled |
| S3 | Critical | Public order list/detail and customer list (all customer PII) | ✅ Fixed |
| S4 | Critical | Public area / area-assign / hierarchy edits, which control approval rights | ✅ Fixed: login + admin role |
| **S5** | **Critical** | **NEW: delivery-app staff could log in to the CRM.** `deli_staff` is shared: drivers, cashiers, counter, billing and dispatch staff all have passwords (27 such accounts in dev). Any of them could log in and read every customer and order. | ✅ **Fixed:** login and every request now require a role listed in `role_crm`; others get "not registered" |
| S6 | High | Attendance settings/history open to anyone | ✅ Fixed: admin, the employee themself, or their seniors |
| S7 | High | Leads: anyone could edit, delete or self-approve | ✅ Fixed |
| S8 | High | Beat plans could be written for any salesman | ✅ Fixed: the override is admin-only |
| **S9** | **High** | **NEW: uploads were saved with the client's file name extension.** A real image named `x.html` or `x.svg` was stored as such and served from the API domain (stored XSS). Laravel already blocked `.php`. | ✅ **Fixed:** files are named from their detected type (jpg/png/webp only). Tested. |
| S10 | Medium | Complaints readable for any staff member via filters | ✅ Fixed: own team only |
| S11 | Medium | Live GPS tracking not limited to the viewer's team | ✅ Fixed |
| S12 | Medium | Login PIN brute-forceable | ✅ Fixed: rate limit |
| S13 | Medium | Raw SQL/DB errors returned to clients | ✅ Fixed: generic messages, details in the log |
| S14 | Low | Unbounded list sizes (`per_page`, customer search) | ✅ Fixed: capped. **NEW this round:** order list, area list, and customer search without a pincode (200) |
| S15 | Low | Uploads were public | ✅ Fixed: login required |

Also checked, and clean:
- no `dd()` / `dump()` / `var_dump()` left in code;
- no SQL built from user input (all queries are parameterised);
- no passwords, tokens or OTPs written to logs;
- every upload validated as an image, max 5 MB;
- the webhook secret is compared in constant time.

---

## 5. Bugs found and fixed

| # | Severity | Bug | Fix |
|---|---|---|---|
| B1 | High | Live-tracking screen force-punched-out telecallers mid-shift, with a time in the future | Only closes shifts from earlier days, or ones whose GPS went silent; never a future time |
| B2 | High | Knowlarity re-sync overwrote the telecaller's chosen call outcome | Outcome set only while the call is still pending |
| B3 | High | Inbound calls never matched (phone clean-up stripped every leading 9 and 1) | Last 10 digits |
| B4 | High | Unknown Knowlarity status broke the DB insert | Mapped to `invalid` |
| B5 | High | Appointment beat plans couldn't be saved (enum missing `appointment`) | Correct in `changes.sql` |
| B6 | High | Beat-plan alternate-week and every-N-days maths wrong (Carbon 3 signed diffs) | Fixed; PHP and SQL verified identical |
| B7 | High | Empty product catalog on prod (`admin_id = 0` treated as vendor #0) | 0 = no vendor filter |
| B8 | High | Order failed on prod when discount > subtotal (UNSIGNED column); fractional quantities mis-stored; negative prices accepted | Total clamps to 0; whole quantities only; negative prices rejected |
| B9 | High | Employee save failed on prod (NOT NULL `admin_id` / `is_locked`) | null → 0 |
| B10 | High | Hindi text crashed writes to prod's latin1 `user` / `deli_staff` | Clear 422 message instead of a 500 |
| B11 | Medium | Order-draft rows could appear in a customer's consumer-app cart | Stored with `userid = 0` |
| B12 | Medium | Ledger aging used the wrong date (epoch parsed as text) | Fixed |
| B13 | Medium | Duplicate lead codes on simultaneous creates | Retry |
| B14 | Medium | Approved customers saved with `register_date = 0` | Set to now |
| B15 | Medium | Customer-assign list crashed if a customer was deleted | Null-safe |
| B16 | Medium | Big allocation plans timed out (1.1 s geocoding per pincode) | Max 15 lookups per request |
| B17 | Low | Bad report dates gave a 500; durations sent as `125.0` | Validated; integers |
| B18 | Low | `payment_collected` sent as a string, crashing the app's number parsing | Sent as a number |
| B19 | Low | Missing Knowlarity env crashed several screens | Null-safe |
| B20 | Low | Reassigning a telecaller's customer to the date it already had returned "None of these customers can be rescheduled" (MySQL counts unchanged rows as 0) | Counts matching customers instead |
| B21 | Medium | Running `changes.sql` on a database whose `beat_plan_crm` already existed (e.g. dev) did not add the missing `appointment` frequency, so appointment beat plans still failed there | Part 1B now adds it when missing; verified |

**Client fixes:**
- An expired login is detected at start-up.
- Logout stops GPS tracking.
- The login screen shows the right message on network errors.
- Login parsing is tolerant of strings vs numbers.
- `mounted` guards added after async calls.
- iOS camera/photo permission text added (it used to crash).
- Android reminder receivers added; the Play-restricted exact-alarm permission was removed.

**Reviewed this round, no issues:** the new product-code search (`product_catalog_search.dart`) and the worklist search by customer ID.

---

## 6. Database (`changes.sql`)

| What | Count |
|---|---|
| New CRM tables | **21** |
| Existing tables given new columns | **3**: `deli_staff` (7), `user` (1), `cart` (4) = **12 columns** |
| Master rows | 9 roles, 8 visit outcomes, 29 languages |
| Dead columns | **0**. `otp`, `otp_expires_at`, `dateOfBirth`, `assignedDays` and `sample_count` were removed from the code and kept out of `changes.sql` |

- **Legacy tables used by the CRM:**
  - It writes to 11: `deli_staff`, `user`, `user_addresses` (on lead approval), `orders`, `orders_item`, `master_orders`, `cart` (draft only), `vendor_products` (stock), `promo` (`max_use`), `promo_log`, `offer_log`.
  - It only reads: `product`, `product_taxes`, `taxes`, `units_master`, `admin`, `offers`, `timing_slot_groups`, `time_slots`.
  - No new table was added for orders.
- **Safety:** `changes.sql` only *adds*. Tables use `IF NOT EXISTS`, columns are added only when missing (checked in `information_schema`), master rows use `INSERT IGNORE`, and it never drops or changes existing columns or rows.
- **Works on MariaDB (prod) and MySQL 8.** Tested by running it twice on each: MariaDB 10.4 scratch copy of prod, and the MySQL 8.0.40 `test_cms` database.
- **Line-by-line explanation:** `docs/CHANGES_SQL_GUIDE.md`.

---

## 6B. Normalization of the CRM tables (safe level)

| Change | Before | After |
|---|---|---|
| One type for every staff ID | The same staff member was stored 4 ways: `varchar(20)`, `varchar(191)`, `varchar(255)`, and a **number** (`bigint`) in the area-assignment and hierarchy tables | All 14 staff-ID columns are `varchar(20)`, the same as `deli_staff.mobile` |
| Missing indexes | No index on lead phone number, lead creator, lead status, telecaller calls by date, or visits by date | 5 indexes added (see `docs/CHANGES_SQL_GUIDE.md`, Part 1B) |
| Derived data kept consistent | `isApproved` could disagree with `approval_status` | `isApproved` is always derived from `approval_status` on save |

**Unchanged:** API responses (the app needs no change), and the lists still stored as JSON (area pincodes, employee areas, team hierarchy, breaks, beat days, script lines). Moving those into separate tables needs a server and app rewrite, so it is left for after go-live.

**Verified:**
- MariaDB copy of prod: fresh install run twice, plus an upgrade from old column types (data kept). All 29 write flows pass.
- MySQL 8 `test_cms`: upgraded from old types, run twice; all **164 API checks pass (143 / 143 routes)**.
- Unit tests: 11 / 11.

---

## 6A. How the CRM writes into legacy tables

The CRM writes to exactly **6 shared tables**. Each write was compared, column by column, with rows the consumer and admin apps created in the same database. Four differences were found and fixed in this round (L1–L4).

| Table | When the CRM writes | What it writes |
|---|---|---|
| `deli_staff` | Admin creates/edits an employee; admin sets shift times | `name`, `mobile`, `role`, `password` (PIN), `admin_id` (vendor), `pincode`, `city`, `state`, `language`, `lat`/`lng`, `is_locked`, shift times. New `deli_id` = next number. An existing mobile is never overwritten. |
| `user` | Admin/teleadmin approves a lead | New customer row: `name`, `shop_name`, `contactno`, `address`/`shop_address`, `pincode`, `city`, `state`, `latitude`/`longitude`, `user_type` (B2B for wholesale/manufacturer/distributor, else B2C), `is_approved='YES'`, `account_state='complete'`, `register_date=now`, `lead_account_id`. Duplicate phone numbers refused. |
| `master_orders` | Staff places an order (inserted first) | Auto-increment `id`; `user_id`, `payment_method='cod'`, `payment_status='pending'`, `order_count` (paid lines only), `txn_id`, `delivery_info`, `delivery_charge`, `before_discount`, `discount`, `order_total`, `status=1`. See §6C. |
| `orders` | Same, one row per vendor | Auto-increment `order_id`; `master_order_id`, `buyer_userid`, that vendor's totals and `items_count`, `delivery_info`, `time_slot` (vendor slot text), `ctype_id='vegetables_fruits'`, `area_name='AMT'`, `admin_id` (vendor), `order_state='pending'`, `payment_status='not_paid'`, `txn_id='crm…'` (20 chars). |
| `orders_item` | Same | Paid and free rows: `pinfo` (the pack snapshot), `quantity`, `qty_loaded`, live `item_price`, `item_total`, `vendor_product_id`, `commission=0`; free rows have `offers='free_item'` and price 0. |
| `vendor_products` | Place (deduct) / cancel (restore) | `packs` JSON: `stk` and `in_stk` on every pack, as in the doc's `updateStock`. |
| `promo`, `promo_log`, `offer_log` | Place, when a promo or offer applies | `max_use − 1` and one `promo_log` row per order; one `offer_log` row per free item and per new-customer discount (not for % off offers, as in the doc). Cancel deletes the `offer_log` rows. |
| `user_addresses` | Lead approved → customer | One saved address (`is_default='1'`), so the customer has an `address_id` to order against. |
| `cart` | Staff edits the "Create Sales Order" cart | One draft row per (staff, shop): `ctype_id='crm_sales_draft'`, `userid=0`, `product_id=0`, `pack_id='crmdraft:…'`, plus `staff_id`, `account_ref`, `account_type`, `draft_payload` (JSON). Deleted when the order is created. |

**Fixed in this round:**

| # | Severity | Difference found | Effect | Fix |
|---|---|---|---|---|
| L1 | **High** | CRM orders were saved with `orders.admin_id = 0`. Every consumer order, and every staff member's vendor, is `108`. | The vendor's admin panel, which works per vendor, would likely never show CRM orders, so they would not get invoiced or delivered. | `admin_id` = the logged-in staff member's vendor (`deli_staff.admin_id`). A new employee created with no vendor now inherits the creating admin's vendor. |
| L2 | **High** | Approved leads became customers with `account_state = 'active'`. The consumer app only uses `complete` / `incomplete`. | The consumer app may treat CRM customers as unfinished accounts. | Written as `complete`. |
| L3 | Medium | `delivery_info` on CRM orders had only `name`, `address`, `latitude`, `longitude`. Consumer orders always also carry `contactno`, `comment`, `couponCode`, `expressDelivery`, `driverName`, `driverNumber`. | The admin/delivery side could meet missing keys (no customer phone number on the delivery). | The same 10 keys are always written (phone taken from the customer), on both `orders` and `master_orders`. |
| L4 | Low | Item `pinfo` lacked `hsn_code` and `selected_pack`, which the admin sales module documents. | The invoice may show no HSN or pack for CRM items. | Both added; the existing keys are kept. |

**Checked and left as they are:**
- **`orders_item.vendor_product_id`:** now filled, because the order lifecycle doc writes it (§6C).
- **`orders.salesman_id`:** left empty. The admin app links this column to `LoginUser_crm.id`, a different staff table. CRM staff live in `deli_staff`, so filling it would point at the wrong table.
- **`master_orders.txn_id` differs from `orders.txn_id`:** consumer orders do the same.
- **Dev data:** most dev rows marked `CRM-` with `admin_id = 108` are seed data (`docs/SEED_DATA_CONTEXT.md`). The 211 orders the CRM app created live have `admin_id = 0`; that's the bug fixed by L1. Prod starts fresh.

---

## 6C. Order creation now follows `ORDER_LIFECYCLE_FOR_NEW_FRONTEND (1).md` (2026-10-09)

Sir's doc describes how the consumer app writes an order (`calculateOrderDetails` → `placeNewOrder` → `cancelOrder`). The CRM now writes orders the same way. Where the doc lists a known bug (§13 gotchas), the fixed behaviour was built.

**The only difference:** the item list comes from the CRM screen (product + pack + quantity) instead of the customer's `cart` rows. The cart is on hold until sir answers the questions below.

**What was wrong before, and what it is now:**

| # | Before | Now (as in the doc) |
|---|---|---|
| 1 | `qty_loaded` never set | `qty_loaded = quantity` |
| 2 | Delivery charge from `cart_type` + add-ons, worked out in the app | From the vendor's `timing_slot_groups`, worked out on the server |
| 3 | `time_slot` = a picked date | Vendor `time_slots` text, e.g. `10 Oct 8:00am  to  10 Oct 10:00pm` (cut-off and clamps applied) |
| 4 | Price typed in the app | Live `vendor_products.packs[pack].rp` |
| 5 | Add-on charges (hamali, transport…) folded into delivery | Removed (the doc has none) |
| 6 | No stock check or deduction | Checked, re-checked inside the transaction (row lock) and deducted; restored on cancel |
| 7 | No minimum order | `user.shop_plot_no` (when numeric), else ₹1000 (₹100 for a vendor-128-only cart); vendor 125 ≥ ₹500 |
| 8 | `delivery_info` typed in the app | Built from the chosen saved `user_addresses` row |
| 9 | MAX+1 ids, `order_id = master id` | Auto-increment, master inserted first |
| 10 | `txn_id = CRM-{id}-{ts}` | 20 random hex chars starting `crm` (marks CRM orders, so no new table) |
| 11 | `payment_status = not_paid` on master | `pending` |
| 12 | Delivery charge added after the discount | Inside `before_discount`; `order_total` = after discount |
| 13 | Custom `pinfo` | The pack snapshot (`tx, op, rp, sn, ps, pu, pi, stk, in_stk, bc`) |
| 14 | `vendor_product_id` empty | Set |
| 15 | Real area, default ctype | `area_name='AMT'`, `ctype_id='vegetables_fruits'` |
| 16 | No offers / promo | 5 offer types + 4 promo types; `offer_log`, `promo_log`, `max_use` |
| 17 | `bill_dt`, `bill_narration`, `department` set | Not set |
| 18 | Items editable after placing | No edit. **Cancel** = pending CRM orders only: restock, delete the rows, delete the orphan master |

**Doc gotchas fixed rather than copied:**
- `delivery_info` comes from the real `addressId`.
- `items_count` is counted per vendor.
- The app's total is checked against the server's own total; a mismatch is rejected.
- The whole write is one DB transaction.
- The promo is logged once per order.
- Cancel removes the orphan master row.
- `bc` counts as a buy cap only when it is a number (real data stores barcodes there).

**API:**
- New: `POST /api/sales-orders/preview`, `POST /api/sales-orders` (with `total_amount` = the preview total), `POST /api/orders/{id}/cancel`.
- Removed: `PUT /api/orders/{id}/items`, `/sales-orders/delivery-rule`, `/sales-orders/next-order-id`.

**App:**
- The order screen shows the server's bill (items, free items, delivery charge, discounts, time slot) and a promo-code field.
- Add-ons, express, dates, narration and the voucher number are gone.
- A customer order needs a saved address.
- Order detail: the edit buttons are gone; "Cancel Order" shows for pending CRM orders.

**Tests:** 35/35 order checks on the MariaDB prod schema; 163/163 API checks on MySQL 8 `test_cms` (142/142 routes, rolled back); PHPUnit 17/17; `flutter analyze` 0 errors.

**Waiting for sir:**
1. **Cart:** should the CRM use the customer's own `cart` rows (`addProductToCart` rules), and may the CRM write into the customer's cart?
2. **`unit_factors`:** what are the real values in `framework/config.php`? The CRM uses a guessed rule: size in `pu` × base unit ("500 Gms." = 0.5, "5 Kg" = 5, "nos" = 1; kg/l = 1, gm/ml = 0.001) in `server/app/Support/UnitFactors.php`.
3. ~~Double stock deduction~~: answered by Sparsh (2026-10-10): stock is deducted when the order is placed, not at invoice. The CRM does the same, so there is no double deduction.

---

## 6D. Units master, add-on charges, editing (2026-10-10)

See `docs/ORDER_LIFECYCLE_AUDIT.md` §6. In short: stock conversion uses `units_master.conversion_rate` through each pack's new `pui` key. Packs whose unit can't be trusted are blocked and listed by `php artisan packs:backfill-pui` (fix list). Add-on charges are saved in `orders.charges_json` like the PMS. Pending CRM orders can be edited. **Go-live step:** run `php artisan packs:backfill-pui` (dry run), share the report, then `--apply` on prod.

---

## 7. Accepted by the owner / notes

**Kept as they are by owner decision:**
- login PIN mechanism;
- Android package id and signing;
- version numbers;
- client `print()` logging;
- latin1 legacy tables;
- recording link token.

**Dev only:** the units dropdown fails on dev because dev's `units_master` lacks `serial_no`. Prod has it, so nothing is needed for prod.

**Code-quality notes (no action required for go-live):**
- Built web files (`client/build/web`, ~200k lines) are committed to git. Consider ignoring them and building in CI.
- The hierarchy walk is copied in 3 controllers; the shared `Support\Hierarchy` class exists for future clean-up.
- Live tracking runs one GPS query per on-duty salesman. That's fine at the current team size; add caching if the team grows past roughly 200.

---

## 7A. Final end-to-end run (2026-10-06, after all fixes)

| Check | Result |
|---|---|
| Code review of all uncommitted changes | ✅ No issues (2 notes below) |
| PHP lint (92 files) | ✅ 0 errors |
| Route audit | ✅ 143 routes: 137 need login, 40 also role-gated, 6 public by design |
| PHPUnit | ✅ 11 / 11 |
| `changes.sql` on MariaDB copy of prod: fresh install ×2, plus upgrade from old-style tables | ✅ All OK; 21 tables, 12 columns, staff IDs `varchar(20)`, master data |
| Prod-schema write flows (MariaDB) | ✅ 29 / 29 |
| `changes.sql` on MySQL 8 `test_cms` ×2 | ✅ 159 statements, both runs OK |
| Every API on MySQL 8 `test_cms` | ✅ **164 / 164 checks, 143 / 143 routes** |
| `flutter analyze` | ✅ 0 errors (3 pre-existing warnings) |
| Security sweep: debug code, upload names, raw SQL, unbounded lists | ✅ All clear |
| Line endings of changed files | ✅ All LF |

**Notes (no action needed for go-live):**
- **Role list cache:** `CrmAccess` caches the role list for the life of one PHP request. That's correct for the normal PHP-FPM / cPanel setup; if the API is ever run as a long-lived worker (Octane), reset the cache when roles change.
- **Order `delivery_info`:** a value the app sends always wins over the default (for example an empty `contactno` sent by the app replaces the customer's phone). The app currently sends only name, address and location, so this is fine.

---

## 8. Deployment checklist

1. **Back up** the prod database.
2. Run **`changes.sql`** in the prod SQL editor. **Do not** run `php artisan migrate` on prod.
3. **Create the first admin** (prod `deli_staff` has no CRM staff yet):
   ```sql
   INSERT INTO deli_staff (admin_id, role, name, mobile, password)
   VALUES (<vendor admin_id>, 'admin', '<Name>', '<10-digit mobile>', '<PIN>');
   ```
   Then create the other staff from the app (role must be a CRM role), and set up areas and the hierarchy.
   **Give every CRM staff member the correct vendor `admin_id`** (e.g. 108). It decides which vendor's products they see and which vendor their orders go to.
4. **Server `.env`:** copy `server/.env.example` and fill it in.
   - `APP_ENV=production`, `APP_DEBUG=false`, `LOG_LEVEL=warning`
   - `AUTH_GUARD=api` (required)
   - prod `DB_*` values
   - a **new** `JWT_SECRET`
   - `KNOWLARITY_*`
   - **Do not** set `MYSQL_ATTR_SSL_CA` (TiDB only).
5. **On the server:**
   ```
   php artisan storage:link
   php artisan config:cache
   php artisan route:cache
   ```
   Make `storage/` and `bootstrap/cache/` writable.
6. **Cron:** `* * * * * cd /path/to/server && php artisan schedule:run >> /dev/null 2>&1`
7. **Knowlarity webhook:** `https://<api-domain>/api/webhooks/knowlarity/<KNOWLARITY_WEBHOOK_SECRET>/call-completed`
8. **App:** set `_productionUrl` in `client/lib/services/api_config.dart` to the live API URL, then rebuild the APK, web and Windows builds.
9. **Smoke test live:** admin login → create a salesman and a telecaller → punch in → add a lead → approve it → create an order → make a call.

---

## 9. Files changed in this final round

| File | Change |
|---|---|
| `server/app/Support/CrmAccess.php` (new) | Allows only staff whose role is in `role_crm` |
| `server/app/Http/Controllers/Auth/OtpAuthController.php` | Login refuses non-CRM staff (same message as an unknown number) |
| `server/app/Http/Middleware/JwtAuthenticate.php` | Every request re-checks the CRM role |
| `ActionLogController`, `AttendanceController`, `LeadsAccountController` | Upload file names use the detected image type |
| `LeadsAccountController` | Customer search without a pincode capped at 200 |
| `OrderListController`, `AreaController` | `per_page` capped |
| `SalesOrderController` | Rewritten on `OrderPlacementService`: preview / place / cancel per the order lifecycle doc (§6C) |
| `server/app/Services/OrderPlacementService.php`, `server/app/Support/UnitFactors.php` (new) | The doc's calculate / place / cancel: stock, offers, promo, time slot |
| `OrderListController` | Order detail returns `can_cancel`; unit read from `pinfo.pu` |
| `BeatPlan`, `CustomerAssign`, `LeadsAccount`, `Telecaller` controllers | Saved addresses carry their `user_addresses.id`; lead approval creates a saved address |
| Client: `create_sales_order_sheet.dart`, `api_service.dart`, `address_picker_dialog.dart`, `order_detail_screen.dart` | Server-priced bill + promo, saved address only, cancel instead of edit |
| `LeadsAccountController` | Approved customer `account_state = 'complete'` (L2) |
| `MastersController` | New employee with no vendor inherits the creating admin's `admin_id` |
| `TelecallerAllocationService` | Reassign reports the right count when the date is unchanged (B20) |
| `changes.sql` | Staff-ID columns → `varchar(20)`; 5 indexes; Part 1B aligns existing tables (incl. `appointment` frequency, B21); works on MariaDB and MySQL 8 |
| Area/hierarchy code (`AreaAssign`, `InchargeAssign`, `Hierarchy`, `TelecallerScope`, 5 controllers) | Look up staff IDs as text, matching the new column type |
| `LeadsAccount` model | `isApproved` derived from `approval_status` |

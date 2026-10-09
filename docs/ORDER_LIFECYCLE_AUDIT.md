# Order creation audit: sir's doc vs what the CRM builds

**Reference:** `ORDER_LIFECYCLE_FOR_NEW_FRONTEND (1).md` (the consumer app's `calculateOrderDetails` → `placeNewOrder` → `cancelOrder`).
**Code audited:** `server/app/Services/OrderPlacementService.php`, `server/app/Support/UnitFactors.php`, `SalesOrderController`, `OrderListController::show`, and the app's order screen.
**Date:** 2026-10-09

**Overall match: about 90%.** Every table and column the doc writes is written the same way. The gaps are the cart (on hold), two push notifications, and the serviceability check.

---

## 1. How it was checked

| Check | Result |
|---|---|
| Doc read section by section against the code | Done (this document) |
| Order flow test on a MariaDB copy of the prod schema (every doc column, promo, offer, stock, cancel, transactions) | **38 / 38 passed** |
| Full API run on MySQL 8 `test_cms` (rolled back) | **167 / 167 passed**, 142 / 142 routes |
| Unit tests (time slot, unit factors) | **17 / 17 passed** |
| Real order #280396 placed on the dev DB (salesman 9000400001, customer 19601) and compared with a real consumer-app order (#279571) | Same columns, formats and `pinfo` keys |

---

## 2. Section by section

| Doc section | What the doc says | What we build | Match |
|---|---|---|---|
| §1 step 2 | Server recomputes everything; client totals never trusted | Same: `place()` calls `calculate()` first | ✅ |
| §1 step 3 | Reject if client total ≠ server total | Same, compared with the real master total (the doc's version compares a key that doesn't exist: gotcha 4) | ✅ fixed |
| §1 step 4 | `user.shop_plot_no` = personal minimum | Same (only when it is a number; dev data stores text there) | ✅ |
| §1 step 5 | ₹1000 minimum; ₹100 if the cart is only vendor 128 | Same | ✅ |
| §1 step 6 | Vendor 125 subtotal ≥ ₹500 | Same | ✅ |
| §1 step 7 | Re-check stock for paid and free lines: in-stock flags, published, `in_stk`, stock ≥ qty × ps × unit factor, buy cap `bc` | Same, under a row lock (`bc` used only when it is a number; real data stores barcodes there) | ✅ |
| §1 step 8 | `delivery_info` from `user_addresses` (doc reads `is_default = 2`, ignoring the chosen address: gotcha 1) | From the chosen `address_id`, 8 keys | ✅ fixed |
| §1 step 9 | `txn_id` = random 20-char hex | Random 20 chars, prefixed `crm` (marks CRM orders, so no new table) | ✅ on purpose |
| §1 steps 11–13 | master first, then per vendor: `orders`, `promo_log` + `max_use`, `orders_item` (paid + free), `offer_log`, stock | Same order | ✅ |
| §1 step 13.8 | Out-of-stock push notification when a pack runs out | **Not built** | ❌ |
| §1 step 14 | Push notification to vendor 128 | **Not built** | ❌ |
| §1 step 16 / §2.7 | Clear the customer's `cart` on success | **On hold**: items come from the CRM screen, not `cart` | ⏸ |
| §2.1 `master_orders` | All columns listed | All set the same way (IST `created_at`, cod, pending, `order_count` without free items, totals, `status = 1`) | ✅ |
| §2.2 `orders` | All columns listed | All set the same way; `items_count` per vendor (gotchas 2/3 fixed) | ✅ |
| §2.3 `orders_item` | `pinfo` = pack snapshot, `qty_loaded` = qty, live `rp`, `vendor_product_id`, commission 0; free rows `offers = free_item`, price 0 | Same | ✅ |
| §2.4 `promo_log` | One row and one `max_use` per vendor (gotcha 6) | Once per order | ✅ fixed |
| §2.5 `offer_log` | One row per free item and per new-customer discount, IST dates | Same | ✅ |
| §2.6 stock | Same delta on every pack; `in_stk` = stk > factor × ps | Same | ✅ |
| §3 time slot | Vendor `time_slots`, cut-off bump, clamps, `"j M g:ia  to  j M g:ia"` | Same; matches real stored values | ✅ |
| §4 delivery charge | Vendor `timing_slot_groups`: charge if subtotal < min | Same (vendor 108: ₹35 under ₹4000) | ✅ |
| §5 preview | Offers (5 types), new customer, promo, discount split (108 first) | Same; split is deterministic | ✅ |
| §5 step 5 | `City::isProductServiceableInArea` per item | **Not built**: the doc doesn't describe the check | ❌ |
| §6 cancel | Pending only; restock; delete `orders_item`, `orders`, `offer_log` | Same, plus the orphan master is deleted (gotcha 8); CRM orders only | ✅ fixed |
| §7 payment | cod / pending (master) / not_paid (order) | Same | ✅ |
| §8 add-ons | None exist | Removed from the CRM | ✅ |
| §9 promo | Upper-cased title, `status = 1`, `max_use > 0`, `min_user_id`, not used before; 4 types | Same | ✅ |
| §10 unit factors | `framework/config.php` | **Guessed**: size in `pu` × base unit ("500 Gms." = 0.5, "5 Kg" = 5, "nos" = 1). Fits every `pu` value in the DB | ⚠ confirm |
| §13 gotcha 11 | Preview writes `offer_log` | Preview writes nothing | ✅ fixed |

---

## 3. Transactions

The doc's code has **no DB transaction** (gotcha 5). It does a manual best-effort rollback, so a failure halfway can leave a master without orders, or orders without a stock deduction. Ours runs the whole write in one transaction, and this was tested by forcing failures:

| Test | Result |
|---|---|
| Force the **last** step (stock update) to fail while placing an order | Nothing left behind: no `master_orders`, `orders`, `orders_item` or `offer_log` row, and stock unchanged ✅ |
| Force **cancel** to fail at its last step | Order, items, `offer_log` and stock all unchanged ✅ |
| Another connection holds the product's stock row while an order is placed | The order waits for the lock, then gives up without writing anything, so two orders can't sell the same last stock ✅ |
| Wrong total, below minimum, not enough stock, used promo | Rejected before any write ✅ |

The same applies to cancel: it locks the order and the stock rows, and either everything happens (restock and delete) or nothing does.

---

## 4. Found and fixed during this audit

| # | Problem | Fix |
|---|---|---|
| 1 | `offer_log` was also written for "% off total" offers, and one row per offer instead of one per free item | Now only free items (one row each) and the new-customer discount, as in §2.5 |
| 2 | Unit factor ignored the size inside `pu` ("500 Gms." counted as 0.001 instead of 0.5), so stock for about 2% of packs would be deducted wrongly | Factor = size × base unit |
| 3 | Approved leads still opened as leads, so no order could be placed for them | They now open as their customer (`user.lead_account_id`) on the worklist and beat plan |

---

## 5. Open questions for sir

1. **Cart:** should the CRM use the customer's own `cart` rows (`addProductToCart`), and may the CRM write into a customer's cart?
2. **unit_factors:** what are the real values in `framework/config.php`?
3. **Double stock deduction:** the doc deducts stock at placement. Does the admin PMS deduct again when it invoices?
4. **Serviceability:** how does `City::isProductServiceableInArea` decide? Which tables does it read?
5. **Notifications:** should CRM orders also send the out-of-stock alert and the vendor-128 push?
6. **Offer data keys:** every offer in the dev DB is inactive. Can we get one real active offer of each type to confirm the `off_data` key names?

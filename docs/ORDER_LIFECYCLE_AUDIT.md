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
| §10 unit factors | `framework/config.php` | **`units_master.conversion_rate` by the pack's `pui`** (sir's decision, see §6) | ✅ |
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

## 6. Units master as source of truth, add-on charges, editing (2026-10-10, after sir's review)

**Sir's decisions:** `units_master` is the source of truth for stock conversion; packs get a `pui` key (= `units_master.unit_id`); add-on charges and order editing come back; `shop_plot_no` stays as the second minimum; items keep coming in the API body.

**Stock conversion now:** `qty × extractFirstNumber(ps) × units_master.conversion_rate[pui] ÷ conversion_rate[product.stock_uom]`. This is the doc's formula with the factor read from `units_master` by id. For KG / NOS stock (rate 1) it is exactly the doc's formula; the division only matters for the 15 products whose stock is kept in GM.

| Where | What changed |
|---|---|
| `app/Support/UnitConversion.php` (new) | Reads `units_master`. Works out stock per pack, and gives the reason a pack can't be sold: no `pui`; unit missing or inactive; pack unit of a different kind than the product's stock unit (KG vs NOS); size written in the pack text ("1 Pack of 5 Kg") disagreeing with ps × unit; ps "0" |
| `OrderPlacementService` | Order check, locked re-check, stock deduction, `in_stk`, cancel restock and edit all use it. A pack with a problem is refused with the reason. Old orders whose pinfo has no `pui` restock with the previous text rule |
| `orders_item.pinfo` | Still the raw pack snapshot, so it now carries `pui` |
| Catalog (`ProductController::parsePacks`, app catalog) | Stock in whole packs from the same conversion. The app shares the product's pool between its packs in real units (1 × 5 kg leaves 10 fewer 500 g packs). Blocked packs show the reason |
| Order detail / invoice | Unit name from `units_master` via `pinfo.pui` (pack text for old orders) |
| `GET /api/masters/units` | Also returns `conversion_rate`; no longer breaks on the dev copy, which has no `serial_no` |

**`pui` backfill:** `php artisan packs:backfill-pui` (dry run) / `--apply`. Matches each pack's `pu` text to a unit name ("500 Gms." → `500 GM`, "1 kg" → `KG`, "nos" → `NOS`). For a count unit (nos/PCS) on a KG product, it takes the weight unit from the pack's own text when that gives the exact size ("10 Kg x 495" → `KG`, "1 pack 250 g" → `250 GM`); these are marked `set_from_text` for review. A pack only gets a `pui` when the conversion is trustworthy. Everything else is left without one, so the CRM can't sell it, and is listed with the reason in `storage/app/pui_backfill_report.csv`, which is **the fix list for the PMS**. On dev (10,028 packs): 9,811 matched by name + 30 from text; 59 unmapped (`pack`, `WEIGHT`, empty, `test`); 115 with a real problem; 13 already had a `pui` (11 of them with a problem). Dev `units_master` row 90 "5 kg" was stored as COUNT/NOS and was corrected to MASS/KG (prod has no `dimension` column).

**Add-on charges** (rules confirmed by Sparsh from the PMS code): stored in `orders.charges_json` as `[{"name","amount","remarks"?}]` with the PMS names **Hamali, Freight, Others, Discount** (exact case). Amounts are JSON numbers. Discount is stored negative, because the PMS normaliser doesn't run on CRM rows. "Packing" has no PMS name, so it is saved as Others with remarks "Packing". **Round off goes to `orders.bill_roff`**, never `charges_json` (the invoice adds both). Delivery charge stays in `delivery_charge`. None of it is added to `order_total`: the PMS invoice and outstanding totals add the charges themselves. Charges go on the vendor-108 order, else the first.

**Editing:** `POST /api/orders/{id}/edit-preview`, `PUT /api/orders/{id}`. Pending CRM orders only. Everything is re-priced like placing (live price, units_master stock, offers, delivery charge, the order's own promo re-applied) in one transaction. Stock moves by the difference only. Items and offer_log are replaced; order and master totals are updated; total mismatch is rejected. Address and time slot stay. App: "Edit" on the order detail screen.

**Tests:** MariaDB prod schema 55/55 (conversion, blocked packs, charges in PMS form + bill_roff, edit, transactions); MySQL 8 `test_cms` 170/170, 144/144 routes (rolled back); PHPUnit 19/19; `flutter analyze` 0 errors.

---

## 6E. Customer cart, as in the doc (2026-10-10)

Customer orders now go through the customer's **cart**, as in doc §15:
- **Filling the cart:** every quantity change in the order screen writes to `cart` through `PUT /api/cart/item` (≈ `addProductToCart`). There is one row per pack, keyed by the customer's `userid` + saved `addressId` (prod's unique key `userid, product_id, pack_id, addressId`). Each row holds `vendor_product_id`, `quantity`, `total` = live `rp` × qty and `ctype_id = 'vegetables_fruits'`, the same as the consumer app's rows. A pack is checked like an order line before it goes in (for sale, in stock, `units_master` unit, buy cap). Quantity 0 removes the row.
- **Reading it:** `GET /api/cart?userid=&address_id=` returns the rows with live price, unit name and maximum quantity.
- **Bill and order from the cart:** `POST /api/sales-orders/preview` and `POST /api/sales-orders` without `items` read the cart rows (≈ `calculateOrderDetails` / `placeNewOrder`).
- **Clearing:** the cart for that user + address is cleared **inside the order's transaction** (≈ `clearCart`), so a failed order keeps its cart. A double-tap retry still returns the first order.
- **Shared with the consumer app:** it is the same cart, so items added in the customer's app show in the CRM and the other way round.
- **Leads** have no `user` row, so they keep the CRM draft (`ctype_id = 'crm_sales_draft'`, `userid = 0`). For customers, that draft now keeps only the add-ons and the address.
- **Inserts:** `cart_id` uses AUTO_INCREMENT where the column has it (prod), and MAX+1 only on dev.
- **Body path kept:** sending `items` in the body still works (backup / edit).
- **Reorder** (doc §1.8 `addOrdersItemsToCart`): `POST /api/orders/{id}/reorder {address_id}` empties the customer's cart for that address, then re-adds every paid item of the past order that can still be sold, with the same checks as adding to the cart. Free items aren't copied, because offers recompute them. Items that are no longer available are returned so staff can be told. The app has a Reorder button on the order detail screen.
- **Not buildable from what we have:**
  - Serviceability (`City::isProductServiceableInArea`, a point-in-polygon check): no table in the prod schema stores area boundaries.
  - The out-of-stock and vendor-128 push notifications: they need the consumer backend's Firebase credentials, which aren't in this repo.

Tests: 15 cart checks on the MariaDB prod schema (88/88 in total); 174/174 API checks, 147/147 routes.

---

## 6F. Sir's answers (2026-10-10)

- **Offers, promo code, notifications:** ignore for now. They stay as built (offers and promo as in the doc; no push notifications).
- **Shared customer cart:** confirmed.
  - The CRM uses the customer's own cart; items show on both sides.
  - Placing an order clears the whole cart for that address.
  - A salesman and a telecaller share one cart.
- **Delivery area check:** important. Sir will share where the area boundaries are stored. Until then it is marked `PENDING — delivery area check` in `OrderPlacementService.php`, in two places:
  - `setCartItem()`, when a pack is added to the cart;
  - `resolveLines()`, where every line is checked for the bill and for placing.

---

## 7. Open questions for sir

1. **Cart:** should the CRM use the customer's own `cart` rows (`addProductToCart`), and may the CRM write into a customer's cart?
2. ~~unit_factors~~: answered: `units_master` is the source of truth (§6).
3. ~~Double stock deduction~~: answered by Sparsh (2026-10-10): stock is deducted when the order is placed, not at invoice. The CRM does the same, so there is no double deduction.
4. **Serviceability:** how does `City::isProductServiceableInArea` decide? Which tables does it read?
5. **Notifications:** should CRM orders also send the out-of-stock alert and the vendor-128 push?
6. **Offer data keys:** every offer in the dev DB is inactive. Can we get one real active offer of each type to confirm the `off_data` key names?

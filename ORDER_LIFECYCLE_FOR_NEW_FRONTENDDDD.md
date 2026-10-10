# Loagma Backend — Order Lifecycle Reference (for new frontend engineers)

> Audience: an engineer who has never seen this codebase and is building a new
> app that will place orders into the **same database** using the existing PHP
> endpoints under `loagmaForArnav/`. Everything below is grounded in the current
> code with file paths and line numbers so claims can be verified by jumping to
> the source.
>
> All paths are absolute, rooted at `/Applications/XAMPP/xamppfiles/htdocs/loagma.com/`.

---

## 0. The four endpoints at a glance

| Endpoint (POST) | File | Purpose |
|---|---|---|
| `calculateOrderDetails.php` | `loagmaForArnav/order/calculateOrderDetails.php` | Previews the price breakdown (per-vendor sub-totals, delivery charge, discounts, free items, time slot text). Does **not** write anything to the DB (except see Gotcha #11). |
| `placeNewOrder.php` | `loagmaForArnav/order/placeNewOrder.php` | Places the order. Writes `master_orders`, `orders`, `orders_item`, `promo_log`, `offer_log`; mutates `vendor_products.packs` (stock); deletes `cart` rows on success. |
| `cancelOrder.php` | `loagmaForArnav/order/cancelOrder.php` | Cancels a `pending` order. **Hard-deletes** rows from `orders_item` and `orders`, restores stock in `vendor_products.packs`, deletes `offer_log` rows for that order. **No "cancelled" status is persisted** — the rows are gone. |
| `fetchDeliveryCharges.php` | `loagmaForArnav/cart/fetchDeliveryCharges.php` | Returns a per-vendor delivery-info blob (`min_total`, `delivery_charge`, slot timing config). Does not do any distance math. |

All PHP-side date/time math is IST; the MySQL server (prod) is on MST, so whenever `DEFAULT CURRENT_TIMESTAMP` would fire, the PHP code tends to set the column explicitly in IST instead — see `loagmaForArnav/classes/cart.php:79`, `loagmaForArnav/classes/offer.php:150-154`.

---

## 1. The cart — upstream of every order endpoint

Nothing about an order (not its totals, not its line items, not its vendor split, not its delivery slot, not its discounts) is sent to `calculateOrderDetails.php` or `placeNewOrder.php` as a list of items. **Both endpoints read the live state of the `cart` table for `(userId, addressId)` and derive everything from there.** The frontend's job for building an order is therefore:

1. Populate `cart` by calling `cart/addProductToCart.php` once per item.
2. Call `order/calculateOrderDetails.php` to preview totals + per-vendor split + free items + delivery slot text.
3. Call `order/placeNewOrder.php` with the exact `afterDiscount` figure from step 2 as `totalAmount`.

If the cart is empty when `placeNewOrder` runs, it returns `"Error 171: Please add items to your cart before placing an order..."` (`order.php:190`).

### 1.1 The `cart` table — write path

Four endpoints touch `cart`:

| Endpoint | File | Operation |
|---|---|---|
| `cart/addProductToCart.php` | `loagmaForArnav/cart/addProductToCart.php` | **INSERT** one row per item. |
| `cart/updateCartedProductQuantity.php` | `loagmaForArnav/cart/updateCartedProductQuantity.php` | **UPDATE** `quantity, total` for an existing row. |
| `cart/removeProductFromCart.php` | `loagmaForArnav/cart/removeProductFromCart.php` | **DELETE** one row by `(userid, pack_id, product_id)`. |
| `cart/fetchCartedProducts.php` | `loagmaForArnav/cart/fetchCartedProducts.php` | **READ** — returns the cart segregated by vendor (same shape `calculateOrderDetails` uses internally). |

### 1.2 `addProductToCart.php` — exact write

Endpoint: `loagmaForArnav/cart/addProductToCart.php`. Delegates to `Cart::addProductToCart` (`loagmaForArnav/classes/cart.php:53-102`).

**Required POST fields** (`addProductToCart.php:14-23`):
- `userId` (int)
- `productId` (int) — `product.product_id`
- `vendorProductsId` (int) — `vendor_products.id`
- `packId` (string) — the key inside `vendor_products.packs` JSON (e.g. the pack's `pi`)
- `vendorId` (int) — admin/vendor id (same value used as `vendor_products.admin_vendor_id`)
- `newQuantity` (int) — bound into `cart.quantity`
- `total` (double) — client-sent price snapshot (⚠ this is the user-visible price at add-time; the server does **not** use it for billing — the real price is re-fetched from `vendor_products.packs[pack_id].rp` at order-placement time, see §3.3's `item_price` row)
- `ctype_id` (string) — historical column, stored as-is (typically `"vegetables_fruits"`)
- `addressId` (int, > 0) — `user_addresses.id`
- `catId` (int) — category id used only for serviceability check (`product.parent_cat_id` in practice)

**Validation gates before INSERT** (`cart.php:54-76`):
1. `addressId` must be numeric and > 0, else returns `{"status":"error","code":"ADDRESS_REQUIRED",...}` (JSON shape — different from the plain-text/boolean returns elsewhere; the frontend has to handle both).
2. All of `userId, packId, vendorId, catId, productId, vendorProductsId, quantity, total, ctype_id` must be non-empty, else returns `false`.
3. `City::isProductServiceableInArea($addressId, $vendorId, $catId)` — point-in-polygon check against the serviceability area. Returns `false` if not serviceable.
4. `Product::doesProductHaveStock($vendorProductsId, $quantity, $packId)` — checks against `vendor_products.packs[packId].stk` (converted via `extractFirstNumber(ps) * unit_factors[pu]`). Returns `false` if the item is OOS.

**INSERT** (`cart.php:80-85`):

```php
$createdAtIst = date('Y-m-d H:i:s');  // explicit IST so the DB's MST default doesn't fire
$query = "INSERT INTO cart
    (userid, addressId, product_id, vendor_product_id, pack_id, quantity, total, ctype_id, created_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)";
$stmt->bind_param("iiiisidss",
    $userId, $addressId, $productId, $vendorProductsId, $packId,
    $quantity, $total, $ctype_id, $createdAtIst);
```

**Column-by-column source for `cart`**:

| Column | Value source | Notes |
|---|---|---|
| `id` | auto-increment | PHP never sets. |
| `userid` | POST `userId` | `cart.php:85` |
| `addressId` | POST `addressId` | `cart.php:85`. Required and > 0. |
| `product_id` | POST `productId` → `product.product_id` | |
| `vendor_product_id` | POST `vendorProductsId` → `vendor_products.id` | |
| `pack_id` | POST `packId` → key inside `vendor_products.packs` JSON | Stored as string (`s` in bind_param). |
| `quantity` | POST `newQuantity` | int. |
| `total` | POST `total` | double. ⚠ Client-sent, **not re-validated server-side**. Server bills from live `vendor_products.packs[pack_id].rp` at order time regardless. |
| `ctype_id` | POST `ctype_id` | Historical. Usually `"vegetables_fruits"`. |
| `created_at` | PHP `date('Y-m-d H:i:s')` IST | Explicit — bypasses the MST `DEFAULT CURRENT_TIMESTAMP`. |
| *anything else on the DB schema* | **DB default — NOT set by PHP** | — |

**Return values**:
- `true` — row inserted.
- `false` — any validation failure or SQL failure. The caller (`addProductToCart.php:28`) does `echo json_encode($response)` → the client sees literal `true`, `false`, or the structured `ADDRESS_REQUIRED` object.

**No duplicate detection.** If the user adds the same `(userId, addressId, product_id, vendor_product_id, pack_id)` tuple twice, you'll get **two rows** in `cart`. The frontend is expected to either call `updateCartedProductQuantity` to bump the existing row, or `removeProductFromCart` first.

### 1.3 `updateCartedProductQuantity.php` — exact write

`loagmaForArnav/cart/updateCartedProductQuantity.php:19`:

```sql
UPDATE cart SET quantity = ?, total = ? WHERE userid = ? AND pack_id = ?
```

POST: `userId, packId, newQuantity, total`. ⚠ Note the `WHERE` is **not scoped to `addressId` or `product_id`** — if the same `pack_id` exists for the user across addresses or (edge case) across products, all those rows are updated at once. Also, `total` is the client-sent value and is not re-validated.

### 1.4 `removeProductFromCart.php` — exact write

`loagmaForArnav/cart/removeProductFromCart.php:19`:

```sql
DELETE FROM cart WHERE userid = ? AND pack_id = ? AND product_id = ?
```

POST: `userId, packId, productId`. ⚠ Also not scoped to `addressId` — removing a product-pack while the user has two addresses would clear it from both carts.

### 1.5 `fetchCartedProducts.php` — exact read

Endpoint delegates to `Cart::getCartData($userId, $addressId)` (`cart.php:11-50`). The query:

```sql
SELECT cart.*,
       product.product_id, product.name, product.cat_id, product.parent_cat_id, brand AS infoText,
       product.is_published, product.is_used, product.is_deleted,
       product.in_stock AS product_in_stock, product.display_photo,
       vendor_products.admin_vendor_id, vendor_products.id AS vendor_product_id,
       vendor_products.in_stock AS vendor_in_stock, vendor_products.status,
       vendor_products.default_pack_id, vendor_products.packs,
       product.inventory_type, product.inventory_unit_type
FROM cart
JOIN vendor_products ON cart.vendor_product_id = vendor_products.id
JOIN product         ON cart.product_id        = product.product_id
WHERE cart.userid = ? AND cart.addressId = ?;
```

The PHP then groups rows by `admin_vendor_id` into a `$cartSegregatedByVendor` map (`cart.php:33-42`). **Every downstream order endpoint consumes exactly this shape.**

Comment on `cart.php:23-24` warns that the `JOIN product` is buggy for multi-vendor scenarios where multiple vendor_products share a product_id — one add can appear as two rows after the join. Flag this to the backend team.

### 1.6 How `calculateOrderDetails` and `placeNewOrder` read the cart

Both endpoints follow the same first step:

```php
// order.php:138 (calculateOrderDetails) and order.php:924 (placeNewOrder-via-recalc)
$cartSegregatedByVendor = $cart->getCartData($userId, $addressId);
```

In **`calculateOrderDetails`** (`order.php:205-576`), the outer loop iterates each vendor; the inner loop (`order.php:231-313`) walks each cart row and uses these columns:

| Column read from `cart.*` / join | Used for |
|---|---|
| `product_id`, `vendor_product_id`, `pack_id`, `quantity` | Core identity + requested qty. |
| `cat_id`, `parent_cat_id` | Serviceability (`City::isProductServiceableInArea($addressId, $vendorId, $itemInfo['parent_cat_id'])` at `order.php:257`); offer category matching. |
| `packs` (JSON) | Decoded (`order.php:272`); pack row must exist for `pack_id`. Used for `rp` (price), `ps` (pack size string), `pu` (pack unit), `stk` (available stock), `bc` (buy cap), `in_stk`. |
| `vendor_in_stock`, `product_in_stock`, `is_published`, `status` | `Product::isProductForSell` sanity gate (`order.php:265`). |
| `admin_vendor_id` | Used by `getCartData` itself to key the vendor group. |

The per-item total is computed by `Product::getProductPrice($itemInfo, {pack_id, quantity})` (`order.php:300`), which reads `packs[pack_id].rp` live from the already-joined row. Accumulators:

- `$orderTotal` — per-vendor subtotal (sum of all `itemTotalPrice`).
- `$orderTotalSegratedByCategoryId[cat_id]` — subtotal per product category inside this vendor, used by `off_on_total` and `prod_on_total` offer matching.
- `$itemCount` — count of lines (used elsewhere; see Gotcha #2 for how this interacts with `orders.items_count`).

The result shape stored at `$mainReturnData[$vendorId]`:

```
{
  "deliveryInfo":        { timeSlotText, freeDeliMinTotal, deliCharge, ... },
  "cartList":            [ ...the raw cart rows for this vendor... ],   // ← this is what placeNewOrder re-reads
  "freeItems":           [ ...offer-granted free items... ],
  "beforeDiscount":      <per-vendor subtotal + delivery_charge if below min>,
  "afterDiscount":       <before - promo - offer - newCustomer>,
  "promoCodeDiscount":   <per-vendor slice>,
  "offerDiscount":       <per-vendor %-off total>,
  "newCustomerDiscount": <per-vendor slice>,
  "deliveryCharge":      <0 or timing_slot_groups.delivery_charge>
}
```

In **`placeNewOrder`** (`order.php:919-1306`), the first thing the method does is call `calculateOrderDetails(...)` again on the server side to get this exact map (`order.php:919`). The cart is **not** re-queried directly — placeNewOrder trusts the shape above. Then, inside the per-vendor loop at `order.php:1109`, it iterates `$vendorWiseDetails['cartList']` to build `orders_item` rows (`order.php:1210-1246`):

| What placeNewOrder reads from each `cartList` row | Where it goes |
|---|---|
| `product_id` | `orders_item.product_id` (`order.php:1235`) |
| `pack_id` | key used to re-fetch live `vendor_products.packs[pack_id]`; also key into `packs` JSON for the `pinfo` snapshot |
| `quantity` | `orders_item.quantity`, and `orders_item.qty_loaded` (`order.php:1237-1238`) |
| `vendor_product_id` | `orders_item.vendor_product_id` (`order.php:1242`); stock-decrement key |
| `packs` (JSON on the row) | Decoded for pack snapshot → `orders_item.pinfo` (`order.php:1232, 1236`) |

Note the price is **re-fetched live** from the database at order-place time (`order.php:1220: fetchOneValue("packs", "vendor_products", "id = '$vendor_product_id'")`), not taken from `cart.total`. The client-sent `cart.total` is never used for billing — it's a UI breadcrumb only. See Gotcha #17.

### 1.7 Cart ↔ order cardinality

- One cart row (`userId, addressId, product_id, vendor_product_id, pack_id`) → one `orders_item` row per vendor's `orders` row.
- All cart rows for a given vendor roll up into one `orders` row for that vendor.
- All vendors in the cart roll up into one `master_orders` row.
- Free items appear as extra `orders_item` rows (flagged `offers = "free_item"`); they do **not** have a corresponding `cart` row.

### 1.8 When the cart is cleared

On a successful `placeNewOrder`, the endpoint wrapper calls `Cart::clearCart($userId, $addressId)` (`loagmaForArnav/order/placeNewOrder.php:29` → `cart.php:104-128`) which runs `DELETE FROM cart WHERE userid = ? AND addressId = ?`. **If `placeNewOrder` returned a string error, the cart is NOT cleared.**

Reorder-to-cart is also supported via `Cart::addOrdersItemsToCart($userId, $addressId, $orderId)` (`cart.php:134-178`), which clears the current cart and re-adds every item from a past order whose stock is still available. Returns an array of names that were unavailable so the UI can tell the user. (⚠ Note: because `cancelOrder` hard-deletes `orders_item` rows, reorder-to-cart will **not** work for a cancelled order id.)

---

## 2. End-to-end call flow: `placeNewOrder.php`

Entry: `loagmaForArnav/order/placeNewOrder.php` (lines 1-32).

**Required POST fields**:
- `userId` (int)
- `addressId` (int, > 0 — this is the row id in `user_addresses`, **not** a free-text address)
- `promoCode` (string, may be empty)
- `totalAmount` (number — must match the server's re-computed total; see step 3)

Numbered flow (file:line references into `loagmaForArnav/classes/order.php` unless noted):

1. **Entry wrapper** (`loagmaForArnav/order/placeNewOrder.php:14`) — calls `$order->placeNewOrder($userId, $addressId, $promoCode, $totalAmount)`.
2. **Server-side recalculation** (`order.php:919`) — `placeNewOrder` immediately calls `calculateOrderDetails($userId, $addressId, $promoCode)` to recompute everything from scratch. **Client-side totals are not trusted for any INSERT** — they are only compared.
3. **Amount check** (`order.php:925-928`) — if `$result["afterDiscount"] != $amountReceived`, returns `"Error 581: ..."`.
   - ⚠ The compared key doesn't actually exist on the top level of what `calculateOrderDetails` returns — see Gotcha #4.
4. **User minimum-order-value gate** (`order.php:930-936`, delegating to `user.php:611-627`) — reads `user.shop_plot_no` as the user's personal minimum. If present and `amountReceived` < that value, reject.
5. **Temporary global minimum** (`order.php:939-955`) — vendor 128-only cart → min **₹100**; otherwise min **₹1000**.
6. **Per-vendor FMCG minimum** (`order.php:964-968`) — if vendor id `125` is in the cart with `afterDiscount < 500`, reject.
7. **Stock re-validation loop** (`order.php:970-1040`) — walks every `cartList` and `freeItems` row, re-checks `vendor_in_stock`, `product_in_stock`, `is_published`, `packs[packId].in_stk == 1`, available `stk` versus required (quantity × `extractFirstNumber(ps)` × `unit_factors[pu]`), and `bc` (buy cap). Builds `$mapOfStockToRemove` keyed by `vendor_product_id`.
8. **Fetch delivery info** for the user (`order.php:1059` → `user.php:472-496`) — reads from `user_addresses` the row with `is_default = 2 LIMIT 1` (⚠ not `addressId` — see Gotcha #1). Encoded as JSON.
9. **Generate master txn id** (`order.php:1067`) — `substr(hash('sha256', mt_rand().microtime()), 0, 20)`.
10. **Compute master totals** (`order.php:1068`, `fetchMasterOrderDetails` at 1351) — sums per-vendor numbers.
11. **INSERT `master_orders`** (`order.php:1095` → `insertIntoMasterTable` at 1554 → `Database::insert`).
12. **Fetch master id back** (`order.php:1100`) via `txn_id`.
13. **Per-vendor loop** (`order.php:1109-1306`), for each vendor:
    1. Build `$insert_fields` for the `orders` row.
    2. **INSERT `orders`** (`insertIntoOrderTable` at 1561).
    3. Fetch the new `order_id` via `txn_id`.
    4. If `promoCodeDiscount > 0` → **INSERT `promo_log`** (1183) and **UPDATE `promo.max_use` -= 1** (1201).
    5. Build line-item rows from `cartList` + append free-item rows from `freeItems`.
    6. **INSERT `orders_item`** rows one at a time (`insertIntoOrderItemsTable` at 1567).
    7. For every free item that originated from an offer, **INSERT `offer_log`** (`order.php:1283` → `offer.php:146`).
    8. **UPDATE `vendor_products.packs`** to subtract stock (`order.php:1300` → `database.php:351-391`). If the new stock drops below `unit_factor * ps`, flips `in_stk = 0` and forks `php ../notif/sendOOSNotif.php $vendorProductId` in the background.
14. **Vendor-128 push notification** (`order.php:1312-1340`) — hard-codes contact `8019500007`, sends FCM push via `Notif::sendNotif`.
15. **Return JSON** `{"orderId": <master_orders.id>}` (`order.php:1342-1345`).
16. **Clear cart** (`loagmaForArnav/order/placeNewOrder.php:29`) — the endpoint wrapper, on success, calls `Cart::clearCart($userId, $addressId)` which **deletes** all `cart` rows for that user+address.

If any step inside the vendor loop fails, there is a manual best-effort rollback via `deleteMasterOrder($masterTxnid)` / `deleteOrder($orderTableLastId)` / `deleteOrderItems(...)` (`order.php:1163-1167, 1291-1294`). **There is no DB transaction** — a partial failure between `master_orders` INSERT and the stock UPDATE can leave the DB inconsistent. See Gotcha #5.

---

## 3. Table-by-table write map

Every table that `placeNewOrder` or `cancelOrder` touches is listed below with every column the PHP code sets. **Columns not listed = DB default fires or column is left untouched by PHP.**

### 3.1 Table `master_orders` — INSERTed once per `placeNewOrder` call

Built in `order.php:1069-1082` and inserted via `Database::insert` (`database.php:15-86`).

| Column | Value source | Notes |
|---|---|---|
| `id` | auto-increment | Fetched back via `fetchMasterTableLastId($txnId)` using the just-inserted `txn_id`. Returned to the client as `orderId`. |
| `user_id` | `$userId` from POST | `order.php:1070` |
| `created_at` | PHP `date("Y-m-d H:i:s")` (IST) | `order.php:1071`. Explicit so the MST DB clock does not fire. |
| `payment_method` | Hard-coded `"cod"` | `order.php:1072`. Comment: "this must be updated once payment gateway is set up." |
| `payment_status` | Hard-coded `"pending"` | `order.php:1073` |
| `order_count` | `fetchMasterOrderDetails(...)['order_count']` — sum of `count(cartList)` across all vendors | `order.php:1074`, computed in `order.php:1365-1376`. **Does NOT include free items.** |
| `txn_id` | `substr(hash('sha256', mt_rand().microtime()), 0, 20)` | `order.php:1067`. Used immediately to look up the auto-inc id. |
| `delivery_info` | JSON string built from `user_addresses` where `is_default = 2 LIMIT 1` (not `addressId`!) via `User::getDeliveryInfo` (`user.php:472-496`). Keys: `name`, `address` (full_address + address concatenation), `contactno`, `comment=""`, `couponCode=""`, `latitude`, `longitude`, `expressDelivery="0"` | `order.php:1076`. Falls back to literal `"-"` if the user has no `is_default = 2` row. ⚠ Does **not** use POST `$addressId` — see Gotcha #1. |
| `delivery_charge` | Sum of `deliveryCharge` across vendors | `order.php:1077` |
| `order_total` | Sum of `afterDiscount` across vendors | `order.php:1078` |
| `before_discount` | Sum of `beforeDiscount` across vendors | `order.php:1079` |
| `discount` | Sum of `promoCodeDiscount + offerDiscount + newCustomerDiscount` across vendors | `order.php:1080` |
| `status` | Hard-coded `1` | `order.php:1081`. Code comment reads "what is the point of this?" |
| *everything else* | **DB default — NOT set by PHP** | Any `is_deleted`, trailing timestamps, etc. rely on the schema. |

### 3.2 Table `orders` — INSERTed once per vendor in the cart

Built in `order.php:1124-1147` inside the per-vendor loop and inserted via `insertIntoOrderTable` (`order.php:1561-1564`).

| Column | Value source | Notes |
|---|---|---|
| `order_id` | auto-increment | Fetched back via `fetchOrderTableLastId($orderTxnid)` using `txn_id`. |
| `master_order_id` | FK → `master_orders.id`, from `$masterTableLastId` | `order.php:1127` |
| `buyer_userid` | `$userId` from POST | `order.php:1128` |
| `before_discount` | `$vendorWiseDetails['beforeDiscount']` — per-vendor subtotal before any discount, after per-vendor delivery charge is added if below min | `order.php:1126`; set in `order.php:568`. |
| `discount` | `promoCodeDiscount + offerDiscount + newCustomerDiscount` for this vendor | `order.php:1129` |
| `items_count` | `count($cartList)` — ⚠ this is the **last vendor's `$cartList`** because `$cartList` was leaked from the earlier validation loop | `order.php:1130`. See Gotcha #2. |
| `delivery_info` | Same JSON string as `master_orders.delivery_info` | `order.php:1131` |
| `order_total` | `$vendorWiseDetails['afterDiscount']` for this vendor | `order.php:1132` |
| `delivery_charge` | `$vendorWiseDetails['deliveryCharge']` — 0 if `beforeDiscount` ≥ `min_total`, else `timing_slot_groups.delivery_charge` | `order.php:1133`; computed at `order.php:531-538`. |
| `time_slot` | STRING, built by `DeliveryDetails::generateTimeSlotText(...)` — see §4 for the exact algorithm. Example: `"9 Oct 10:00am  to  10 Oct 06:00pm"` | `order.php:1135`. The date is embedded in this string — **there is no separate `delivery_date` column** written by PHP. |
| `short_datetime` | PHP `date('d-M-y h:i A', time())` (IST) | `order.php:1136` → `get_indian_short_datetime` at 1688-1698. Example: `"09-Oct-25 03:45 PM"`. |
| `ctype_id` | Hard-coded `"vegetables_fruits"` | `order.php:1137`. Historical column. |
| `feedback` | Empty string `""` | `order.php:1138` |
| `admin_id` | `$vendorId` (the admin/vendor id, outer loop key) | `order.php:1139` |
| `area_name` | Hard-coded `"AMT"` | `order.php:1140`. Historical column. |
| `payment_method` | Hard-coded `"cod"` | `order.php:1141` |
| `payment_status` | Hard-coded `"not_paid"` | `order.php:1142`. **Note the inconsistency with `master_orders.payment_status = "pending"`** — see Gotcha #12. |
| `txn_id` | `substr(hash('sha256', mt_rand().microtime()), 0, 20)` — a fresh one per vendor | `order.php:1125` |
| `start_time` | PHP `time()` (unix epoch int, IST-captured) | `order.php:1144` |
| `last_update_time` | PHP `time()` | `order.php:1145` |
| `order_state` | Hard-coded `"pending"` | `order.php:1146`. This is the field `cancelOrder` keys off — only `pending` orders are cancellable. |
| `delivered_date` | **DB default — NOT set by PHP** | `order.php:1149` comment. |
| `deli_id` | **DB default — NOT set by PHP** | `order.php:1150` |
| `delivery_start` | **DB default — NOT set by PHP** | `order.php:1151` |
| `delivered_time` | **DB default — NOT set by PHP** | `order.php:1152` |
| `trip_id` | **DB default — NOT set by PHP** (assigned later by the trip system) | — |
| `bill_number` | **DB default — NOT set by PHP** | Read later in `fetchOrdersItemsDetails`. |
| `amountReceivedInfo` | **DB default — NOT set by PHP** (filled on delivery/payment capture) | Read-only here. |

### 3.3 Table `orders_item` — one row per carted item + one row per free item, per vendor

Built in `order.php:1211-1285` and bulk-inserted row-by-row via `insertIntoOrderItemsTable` (`order.php:1567-1577`).

**Paid line item** (`order.php:1211-1246`):

| Column | Value source | Notes |
|---|---|---|
| `item_id` | auto-increment | PHP never sets it. |
| `order_id` | `$orderTableLastId` (FK → `orders.order_id`) | `order.php:1233` |
| `product_id` | `$item_info['product_id']` from the cart row | `order.php:1235` |
| `pinfo` | JSON-encoded single pack blob — `json_encode(json_decode(cart.packs, true)[$pack_id])`. Keys: `tx`, `op`, `rp`, `sn`, `ps`, `pu`, `pi`, `stk`, `in_stk`, `bc` | `order.php:1232, 1236`. Snapshots pack details at order time. |
| `quantity` | `$item_info['quantity']` from the cart row | `order.php:1237` |
| `qty_loaded` | Mirrors `quantity` at insert time (driver updates later) | `order.php:1238` |
| `qty_delivered` | **DB default — NOT set by PHP** | Filled by delivery flow. |
| `qty_returned` | **DB default — NOT set by PHP** | Filled by delivery flow. |
| `item_price` | Re-fetched LIVE from `vendor_products.packs[pack_id].rp` just before insert (not from cart row's `total`) | `order.php:1220-1227, 1240`. If the vendor's RP changed between cart-add and order-place, the order uses the newer price. |
| `item_total` | `item_price * quantity` | `order.php:1228, 1241`. ⚠ Does **not** apply any per-item discount — discount is tracked only at the order level. |
| `vendor_product_id` | `$item_info['vendor_product_id']` | `order.php:1242` |
| `commission` | Hard-coded `0` | `order.php:1243`. Commission calc is commented out. |
| `op_id` | **DB default — NOT set by PHP** (defaults to 0 per comment) | `order.php:1244` |
| `offers` | **Not set for paid items** — takes DB default. Set to `"free_item"` only for free rows. | — |

**Free item (offer-granted)** (`order.php:1250-1285`) — same columns, plus `offers = "free_item"`, with these differences:

| Column | Value source | Notes |
|---|---|---|
| `product_id` | `$item_info['offer_product_id']` | `order.php:1254, 1267` |
| `pinfo` | `json_encode($item_info['offerProductInfo']['packs'])` with `rp` forced to `0` | `order.php:1259-1262`. Keeps the printed bill at ₹0 for free items. |
| `quantity` | `$item_info['offer_product_quantity']` | `order.php:1256` |
| `qty_loaded` | Mirrors `quantity` | `order.php:1270` |
| `item_price` | `0` | `order.php:1258, 1271` |
| `item_total` | `0` | `order.php:1257, 1272` |
| `vendor_product_id` | `$item_info['offerProductInfo']['vendor_product_id']` | `order.php:1260, 1273` |
| `commission` | `0` | `order.php:1274` |
| `offers` | `"free_item"` | `order.php:1275` |

### 3.4 Table `promo_log` — INSERTed only if `promoCodeDiscount > 0` for that vendor

`order.php:1171-1203`.

| Column | Value source | Notes |
|---|---|---|
| `id` | auto-increment | PHP never sets. |
| `order_id` | `$orderTableLastId` (per-vendor `orders.order_id`) | `order.php:1180`. ⚠ Written **once per vendor that received any slice of the promo discount**, so a single promo can log multiple rows for one master order. |
| `userid` | `$userId` from POST | `order.php:1181`. ⚠ `global $userId;` on 1178 refers to class scope, but `$userId` is a method local; the preceding `global` statement is effectively a no-op. |
| `promo_id` | `promo.promo_id` looked up by `promo.title = '$promoCode'` | `order.php:1174-1182` |
| *everything else* | **DB default — NOT set by PHP** | `created_at` etc. |

**Side-effect in the same block**: **UPDATE `promo` SET `max_use` = max(0, max_use - 1)** where `promo_id = <id>` (`order.php:1186-1201`).

### 3.5 Table `offer_log` — INSERTed once per free-item offer applied, and once per new-customer-discount offer applied

`offer.php:146-157`. Called from two places:
- `order.php:1283` — for each `free_item` row inserted (looped over `freeItems`).
- `order.php:775` — for new-customer discount offers (⚠ but `$masterTableLastId` is used here even though it's inside `calculateOrderDetails` where that variable is **not defined** → always `null`. See Gotcha #11).

| Column | Value source | Notes |
|---|---|---|
| `id` | auto-increment | — |
| `user_id` | `$userId` | `offer.php:154` |
| `order_id` | `$orderTableLastId` (per-vendor `orders.order_id`) — or `null` from the broken `calculateOrderDetails` path | `offer.php:154` |
| `offer_id` | `offers.off_id` from the matched offer | `offer.php:154` |
| `used_date` | PHP `date('Y-m-d')` IST | `offer.php:150, 154` |
| `created_at` | PHP `date('Y-m-d H:i:s')` IST — explicit so the MST default does not fire | `offer.php:151, 154` |

### 3.6 Table `vendor_products` — UPDATE on the `packs` JSON column

`database.php:351-391`, called from `order.php:1300` with `addStock = false`.

- Entire `packs` JSON is read, every pack's `stk` is decremented by the quantity being deducted (⚠ **the loop updates every pack** of that `vendor_product_id` with the same delta — see Gotcha #9), `in_stk` is recomputed to `1` if `stk > unit_factor * ps` else `0`, and the whole JSON is written back via `updateOneValue`.
- If any pack goes OOS, a background `exec("php ../notif/sendOOSNotif.php $vendorProductId ...")` fires.

| Column | Value source | Notes |
|---|---|---|
| `packs` | Mutated JSON (see above) | Only this one column is updated. |

### 3.7 Table `cart` — DELETE (not during order insert, but on wrapper success)

`loagmaForArnav/order/placeNewOrder.php:29` → `Cart::clearCart($userId, $addressId)` (`cart.php:104-128`): `DELETE FROM cart WHERE userid = ? AND addressId = ?`. All rows for the user+address are wiped. `clearCart` runs **only on success** — if `placeNewOrder` returned a string error, the cart is left intact.

---

## 4. `time_slot` construction — the exact algorithm

### Where it comes from

Built by `DeliveryDetails::generateTimeSlotText($deliveryInfoMap)` in `loagmaForArnav/classes/deliveryDetails.php:70-112`. Called from `order.php:562`; result lands in `$mainReturnData[$vendorId]['deliveryInfo']['timeSlotText']` and is later written into `orders.time_slot` on `order.php:1135`.

### Inputs (per-vendor)

Loaded by `DeliveryDetails::getCategoryDetails($adminVendorId)` (`deliveryDetails.php:13-55`) via:

```sql
SELECT timing_slot_groups.min_amount AS min_total,
       timing_slot_groups.delivery_charge,
       timing_slot_groups.admin_id,
       time_slots.start_date AS num_days_gap,
       time_slots.interval    AS delivery_interval,
       time_slots.order_time_end,
       time_slots.delivery_time_start,
       time_slots.delivery_time_end
FROM timing_slot_groups
JOIN time_slots ON timing_slot_groups.id = time_slots.time_slot_group_id
WHERE is_active = 1 AND timing_slot_groups.admin_id = ?
LIMIT 0,1
```

Keys passed into `generateTimeSlotText`:
- `numDaysGap` — the window width (end date is start + gap)
- `deliveryInterval` — days from today to the start of the delivery window
- `deliveryTimeStart`, `deliveryTimeEnd` — HHMM ints (e.g. `1000`, `1800`)
- `orderTimeEnd` — HHMM int; if "now" is past this time, the order is treated as if placed tomorrow (so `deliveryInterval += 1`)

### The exact PHP

```php
// deliveryDetails.php:81-110
$currentTime = (int)date('Hi');                            // e.g. 1530 for 3:30 PM IST
$orderTimeEnd      = (int)$deliveryInfoMap['orderTimeEnd'];
$deliveryInterval  = (int)$deliveryInfoMap['deliveryInterval'];
$numDaysGap        = (int)$deliveryInfoMap['numDaysGap'];

if ($currentTime > $orderTimeEnd) {
    $deliveryInterval += 1;   // bump by one day — "cut-off" logic
}

$deliveryStartDate = date('j M', strtotime('+' . $deliveryInterval . ' day'));
$deliveryEndDate   = date('j M', strtotime('+' . ($deliveryInterval + $numDaysGap) . ' day'));

$deliveryTimeStart = (int)$deliveryInfoMap['deliveryTimeStart'];
$deliveryTimeEnd   = (int)$deliveryInfoMap['deliveryTimeEnd'];

if ($deliveryTimeEnd   > 2400) { $deliveryTimeEnd   = 2400; }
if ($deliveryTimeStart > 2300) { $deliveryTimeStart = 2300; }

$timeSlotString = $deliveryStartDate . ' ' . $this->convertTime($deliveryTimeStart)
                . '  to  '
                . $deliveryEndDate   . ' ' . $this->convertTime($deliveryTimeEnd);
return $timeSlotString;
```

`convertTime($hhmm)` (`deliveryDetails.php:114-131`) zero-pads to 4 digits, splits hours/minutes, picks `am`/`pm`, converts to 12-hour. Example: `1000 → "10:00am"`, `1800 → "6:00pm"`.

### What gets stored

A **plain string** like `"10 Oct 10:00am  to  11 Oct 06:00pm"` (note the double space around `to`). Date and time are concatenated into one column. There is **no separate `delivery_date` column** written by PHP.

### What is NOT present
- No holiday skipping.
- No per-user slot picker — the frontend cannot ask for "11 am–noon tomorrow"; the vendor's `time_slots` row dictates the whole window.
- No "next available slot" scanning — only the single cut-off bump.
- Timezone is IST (set in `conn.php:7`).

### Downstream parsing

`Order::fetchActiveOrdersStatus` (`order.php:1731`) parses this back as `trim(explode('to', $order['time_slot'])[0])` for the "delivery date" shown in the active-orders UI. **If the format ever changes, that split breaks.**

---

## 5. Delivery charge — the real formula

Short answer: **no distance, no Haversine, no zones, no "free delivery over X" promo**. It's just a per-vendor min-total threshold.

### Per-vendor lookup

`fetchDeliveryCharges.php` (`loagmaForArnav/cart/fetchDeliveryCharges.php`) takes POST `categoryTypeId` (poorly named — the value is actually the vendor's admin id) and returns the JSON array from `getCategoryDetails`:
- `min_total` ← `timing_slot_groups.min_amount`
- `delivery_charge` ← `timing_slot_groups.delivery_charge`
- `admin_id`
- `num_days_gap`, `delivery_interval`, `order_time_end`, `delivery_time_start`, `delivery_time_end` (used for slot text only)

### The branch that decides the actual charge on the order

`order.php:531-538`:

```php
$delivery_charge  = 0;
$before_discount  = $orderTotal;              // per-vendor subtotal before offer/promo discounts
if (($cart_info['min_total'] + 0) > 0 && $before_discount < ($cart_info['min_total'] + 0)) {
    $delivery_charge = $cart_info['delivery_charge'] + 0;
    $orderTotal      = $orderTotal + $delivery_charge;
}
```

Rules:
- If vendor's `min_total` > 0 **and** cart subtotal for that vendor < `min_total` → delivery charge applies.
- Otherwise delivery charge is **0**.
- Charge is compared against the **before-discount** subtotal, not after. Applying a promo doesn't retroactively add delivery.
- The charge is **per vendor**. `master_orders.delivery_charge` is the sum across all vendors.

### Writes
- `orders.delivery_charge` — per vendor (`order.php:1133`).
- `master_orders.delivery_charge` — sum (`order.php:1077`).

### What's NOT there
- No lat/lng Haversine. `City::isProductServiceableInArea` does point-in-polygon serviceability only.
- No per-order "free delivery" promo code type. Promo codes affect `discount`, not `delivery_charge`.

---

## 6. `calculateOrderDetails.php` — what it computes

Entry: `loagmaForArnav/order/calculateOrderDetails.php` (lines 1-25). POST: `userId`, `addressId`, `promoCode`.

Delegates to `Order::calculateOrderDetails` (`order.php:54-857`):

1. Validate `userId` + `addressId` (`order.php:66-71`). Returns `"Error ADDRESS_REQUIRED..."` if `addressId` is missing/0 — the frontend endpoint maps this to a special JSON code (`calculateOrderDetails.php:15-16`).
2. Detect "new customer" (`order.php:131` → `isNewCustomer` at 1665 — true iff `COUNT(*) FROM orders WHERE buyer_userid = $userId` is 0).
3. Fetch active offers (`Offer::fetchAllOffers`, `offer.php:96-142`). Reads `offers` + `offer_log` (daily usage filter via `dailyLimit` key in `off_data`). Supported `off_type` values: `prod_on_prod`, `off_on_total`, `prod_on_total`, `new_customer_product`, `new_customer_discount`.
4. Fetch cart segregated by vendor (`Cart::getCartData`, `cart.php:11-50`). Joins `cart`, `vendor_products`, `product`.
5. **Per-vendor loop** (`order.php:205-576`):
   - Fetch delivery/slot config via `DeliveryDetails::getCategoryDetails($vendorId)`.
   - Validate each item: serviceability (`City::isProductServiceableInArea`), `isProductForSell`, pack exists, stock-check logic.
   - Compute `itemTotalPrice = pack.rp * quantity` via `Product::getProductPrice`.
   - Accumulate `orderTotal` + `orderTotalSegratedByCategoryId[cat_id]`.
   - Apply `prod_on_prod` offers → push to `$freeItems` (`order.php:320-368`).
   - Apply `new_customer_product` offers (if new customer) → push to `$freeItems` (`order.php:376-418`).
   - Apply `off_on_total` and `prod_on_total` offers (`order.php:423-529`). Both consider cat-specific `ctype` or `all`. For `off_on_total`, picks the highest discount % per ctype.
   - Compute `delivery_charge` per the rule in §5.
   - Compute `total_offer_discount` from the %-based `off_on_total` discounts (`order.php:541-553`).
   - Store per-vendor result in `$mainReturnData[$vendorId]` with keys: `deliveryInfo`, `cartList`, `freeItems`, `beforeDiscount`, `afterDiscount`, `promoCodeDiscount` (0 for now), `offerDiscount`, `newCustomerDiscount` (0 for now), `deliveryCharge`.
6. **Promo code** (`order.php:595-700`) — resolves via `Promo::fetchPromoWithPromoID` (looks up `promo` row where `title = ? AND status = 1 LIMIT 1`). Four promo types:
   - `amount` — fixed ₹ if subtotal ≥ `min_amount`
   - `amount_ladder` — reads `ladderPromo` map `{threshold: discount}`, picks the best
   - `percentage` — same but percentage-based
   - `percentage_up_to` — percentage capped at `max_amount`
7. **New-customer discount** (`order.php:702-722`) — fixed or percentage, respects `min_order_value`.
8. **Discount distribution across vendors** (`order.php:725-816`) — tries to charge all discount to vendor 108 first, then spills to other vendors in iteration order. ⚠ Non-deterministic beyond 108 depending on PHP array iteration order.
9. Return `json_encode($mainReturnData)`.

The wrapper (`calculateOrderDetails.php:22`) then calls `Order::fetchMasterOrderDetails(..., $isForFrontEnd=true)` (`order.php:1351-1416`) which reshapes the data into:

```json
{
  "deliveryInfo":   { "<vendorId>": { "timeSlotText":..., "freeDeliMinTotal":..., "deliCharge":... }, ... },
  "cartList":       { "<vendorId>": [...], ... },
  "freeItems":      { "<vendorId>": [...], ... },
  "deliveryCharge": <total>,
  "order_count":    <sum of cart items>,
  "afterDiscount":  <total>,
  "beforeDiscount": <total>,
  "promoCodeDiscount": { "discount": <amount>, "description": <string> },
  "offerDiscount": <offer + new-customer>
}
```

**Nothing is written to the DB in this endpoint.** It's a pure preview — but `Offer::fetchAllOffers` and the per-user offer-limit filter *read* `offer_log`.

---

## 7. `cancelOrder.php` — what happens, what's reversible

Entry: `loagmaForArnav/order/cancelOrder.php` (lines 1-43). POST: `orderId` (the `orders.order_id`, **not** master id), `userId`.

Flow:

1. **Authorization** (`cancelOrder.php:16-22`) — fetches `orders.buyer_userid` and refuses if it ≠ POST `userId`. ⚠ No session/token check; the frontend must trust its own `$userId`.
2. **State check** (`cancelOrder.php:24-28`) — fetches `orders.order_state`; **only `"pending"` orders are cancellable**. Any other state (`registered`, `dispatched`, `delivered`, etc.) returns `"Only pending orders can be deleted."`.
3. **No time-window restriction** beyond the state check. If the backend hasn't advanced the state yet, the order is cancellable regardless of how long ago it was placed.
4. Delegate to `Order::cancelOrder($orderId)` (`order.php:1606-1649`).

### What `Order::cancelOrder` does

```php
// order.php:1612
$rowsData = $this->database->fetchMultipleValues(
    'vendor_product_id, pinfo, quantity', 'orders_item', "order_id = '$orderId'"
);

// Build mapOfStockToAdd = { vendor_product_id: qty * extractFirstNumber(ps) * unit_factors[pu] }
// (order.php:1616-1632)

$this->database->updateStock($mapOfStockToAdd, true);     // $addStock = true → increments packs.stk, flips in_stk back

$res = $this->database->delete("orders_item", "order_id = '$orderId'");
if ($res) {
    $res = $this->database->delete("orders", "order_id = '$orderId'");
    $offer = new Offer($this->conn);
    $offer->removeOfferUsageForCancelledOrder($orderId);  // DELETE FROM offer_log WHERE order_id = ?
    return true;
}
return false;
```

### Table-by-table effects on cancel

| Table | Effect |
|---|---|
| `orders` | **DELETEd** by `order_id`. The row is **gone**, not flipped to `order_state = 'cancelled'`. |
| `orders_item` | **DELETEd** (all rows for that `order_id`). |
| `offer_log` | **DELETEd** (all rows for that `order_id`). |
| `vendor_products.packs` | `stk` is **incremented**; `in_stk` may flip 0→1 if above threshold. |
| `master_orders` | **NOT touched.** The parent row is left orphaned if the cancelled order was the only child of its master. ⚠ Big gotcha. |
| `promo_log` | **NOT touched.** The promo-usage row survives, so the user can't re-use a one-time promo after cancelling. ⚠ |
| `promo.max_use` | **NOT restored.** The decrement from `placeNewOrder` is permanent. ⚠ |
| `cart` | Not restored. The user needs to re-add items manually (`addOrdersItemsToCart.php` also no longer works for this order because `orders_item` is gone). |

### Not reversible
- Push notifications already sent.
- Any trip/driver assignment side-effects (but `pending` orders shouldn't have any).

### Return / notifications
- No refund row inserted anywhere. `payment_method` was `cod` and `payment_status` was `not_paid`/`pending`, so there is nothing to refund.
- No notification is sent on cancel.

---

## 8. Payment

As of this repo, there is **no real payment integration**. Hard-coded values:

| Field | `master_orders` | `orders` |
|---|---|---|
| `payment_method` | `"cod"` (`order.php:1072`) | `"cod"` (`order.php:1141`) |
| `payment_status` | `"pending"` (`order.php:1073`) | `"not_paid"` (`order.php:1142`) |
| `txn_id` | random 20-char sha256 hex slice (`order.php:1067`) | random 20-char sha256 hex slice (`order.php:1125`) — different per vendor |

There is **no `payments` or `transactions` table write** in these files. The `txn_id` column is used purely to look up the just-inserted auto-inc id (`fetchMasterTableLastId`, `fetchOrderTableLastId`). Comments repeatedly flag "will need to change this after integration of payment gateway" (lines 1072, 1073, 1141, 1142) — when a real PG is integrated, these need updating.

---

## 9. Order items / add-ons / modifiers

- Line items live in `orders_item`. One row per cart line. Free items are also rows in `orders_item`, flagged by `offers = "free_item"`.
- **There is no add-on / modifier / variant table in `loagmaForArnav` or `loagmaPMS`.** See §13 below — this was investigated explicitly in `loagmaPMS` and no such feature exists in the current schema (~125 tables).
- Pack variations (sizes, units) are embedded in the `pinfo` JSON column snapshot taken from `vendor_products.packs[pack_id]` at order time. Keys inside `pinfo`:
  - `tx` — display text
  - `op` — original price / MRP
  - `rp` — retail/selling price
  - `sn` — sequence number
  - `ps` — pack size, e.g. `"1 kg"`
  - `pu` — pack unit (looked up in `config['unit_factors']` at `/Applications/XAMPP/xamppfiles/htdocs/loagma.com/framework/config.php:197-219`)
  - `pi` — pack id
  - `stk` — stock
  - `in_stk` — in-stock flag
  - `bc` — buy cap / max purchasable units
- A single `orders_item` row carries one pack. The same product in two different packs = two separate rows in `cart` → two rows in `orders_item`.

---

## 10. Promo / coupon handling

### Lookup
- Promo input is the plain text `title` (uppercased in `Promo::fetchPromoWithPromoID`, `promo.php:28`). Row must have `status = 1`.
- Validation in `Promo::validatePromo` (`promo.php:56-92`): `max_use > 0`, optional `min_user_id` check, and **not already used by this user** (`promo_log` lookup).

### Discount split across vendors
`order.php:783-816`:
1. Entire `promoDiscount` is first charged to vendor 108 if present.
2. If 108's `afterDiscount` is less than the discount, the leftover (`carryForwardPromoDiscount`) is applied to each remaining vendor in iteration order until exhausted.

The per-vendor `promoCodeDiscount` is written into `orders.discount` as part of `promoCodeDiscount + offerDiscount + newCustomerDiscount`.

### Writes
- **`promo_log` INSERT** (`order.php:1183`) — one row per vendor whose order received any slice of the promo. Columns: `order_id` (per-vendor), `userid`, `promo_id`.
- **`promo.max_use` UPDATE** (`order.php:1201`) — decrement by 1 per vendor insert. ⚠ Means a 2-vendor order consumes 2 `max_use` slots. See Gotcha #6.

### Reads during preview (`calculateOrderDetails`)
- `promo` row by `title`.
- Does **not** write anything.

---

## 11. Config helpers you'll touch

| What | Where |
|---|---|
| MySQL connection, timezone | `loagmaForArnav/conn.php` |
| `unit_factors` map (unit string → kg/qty multiplier) | `/Applications/XAMPP/xamppfiles/htdocs/loagma.com/framework/config.php:197-219` |
| Error log file paths | `loagmaForArnav/classes/error.php` → writes to `loagmaForArnav/logging/errorLogged.txt` / `errorLoggedBackEnd.txt` |
| FCM notification creds | `loagmaForArnav/classes/loagmaFirebaseContents.php` (loaded in `notif.php:37`) |

---

## 12. Dependency chain of includes

Starting from `placeNewOrder.php`:

```
placeNewOrder.php
├── ../conn.php
├── ../classes/order.php
│   ├── ../classes/deliveryDetails.php
│   │   ├── error.php
│   │   └── databaseCopy.php
│   ├── ../classes/cart.php
│   │   ├── ../classes/city.php
│   │   └── ../classes/product.php
│   ├── ../classes/product.php
│   ├── ../classes/offer.php
│   ├── ../classes/promo.php
│   │   └── ../classes/database.php
│   ├── ../classes/user.php
│   ├── ../../framework/config.php      // provides $config['unit_factors']
│   ├── ../classes/notif.php
│   │   └── databaseCopy.php
│   └── ../classes/driver.php
└── ../classes/error.php
```

Note: `databaseCopy.php` is a near-duplicate of `database.php` used by `deliveryDetails.php` and `notif.php`.

---

## 13. Where add-ons live (and why this matters for the new app)

The brief for this reference originally asked how add-on charges are stored in `loagmaPMS`. **Investigation outcome: there is no add-on feature in the current `loagmaPMS` codebase.** Specifically:

- Grep for `addon`, `add_on`, `modifier`, `variant`, `option_group`, `product_option`, `product_extra` across `loagmaPMS/app`, `loagmaPMS/routes`, `loagmaPMS/database`, `loagmaPMS/resources`, `loagmaPMS/config` → **zero** matches.
- The authoritative schema dump at `/Applications/XAMPP/xamppfiles/htdocs/loagma.com/loagmaPMS/docs/loagma_new.sql` lists ~125 tables; **none** is for add-ons.
- `loagmaPMS/database/migrations/` is empty (only `.DS_Store` and `.gitignore`). Schema is managed via raw SQL dumps in `docs/` and `database/manual_sql/`, not Laravel migrations.
- Controller list under `loagmaPMS/app/Http/Controllers/` has no `AddonController`, `ModifierController`, or `OptionController`. `ProductPackageController` sounds adjacent but contains zero mentions of "addon".
- Grep across `loagmaForArnav` also returns zero.

The closest conceptual neighbour is `vendor_products.packs` — a JSON column holding size/weight tiers (e.g. 500 g / 1 kg / 5 kg of the same product) with their own price, stock, and MRP. That is a **product packaging dimension**, not an orthogonal add-on with a separate charge. See `pinfo` keys in §9.

**Implication for the new app**: either the feature has not been built yet, or the add-ons live in a different system that was not named in the original brief. Confirm with the PMS owner before writing any reader that assumes add-on tables exist.

---

## 14. Gotchas — call out before building on them

1. **`delivery_info` ignores POST `addressId`.** `User::getDeliveryInfo($userId)` (`user.php:472-496`) always picks the row with `is_default = 2` for that user, regardless of which `addressId` the frontend posted. If the user has a different address selected in-app, the order ships to the default-2 address on the server. Fix would be to pass `addressId` into `getDeliveryInfo`. — `order.php:1059, 1076, 1131`.
2. **`items_count` on `orders` uses a leaked variable.** `order.php:1130` uses `count($cartList)` where `$cartList` is the one from the validation loop (`order.php:970-1013`), not the current vendor's cart list. In a multi-vendor order, every per-vendor `orders` row ends up with the same `items_count` (that of whichever vendor the validation loop processed last). The current vendor's list is reassigned at `order.php:1210` **after** this insert.
3. **`items_count` does not count free items** — just paid cart lines. Non-trivial if the UI shows "N items".
4. **Server-side amount check compares a non-existent key.** `order.php:926` reads `$result["afterDiscount"]`, but `$result` is the per-vendor map keyed by vendor id; the real total is `fetchMasterOrderDetails(...)['afterDiscount']`. In practice this check is a no-op for most orders.
5. **No DB transaction wrapping the inserts.** If `vendor_products.packs` update fails after `master_orders` + `orders` + `orders_item` have been inserted, the code logs and returns but leaves the DB inconsistent. Rollback is manual and incomplete. — `order.php:1300-1305`.
6. **Promo discount decrements `max_use` once per vendor**, not once per use. A 3-vendor order burns 3 slots. — `order.php:1183-1201`.
7. **`promo_log` is not rolled back on cancel**, nor is `promo.max_use` restored. Users who cancel lose both the promo and the slot. — `order.php:1606-1649`.
8. **Cancel hard-deletes `orders` and `orders_item` rows but leaves `master_orders`.** You lose the historical record of the cancelled order and get an orphaned master. There is no "cancelled" `order_state` persisted anywhere (even though `determineOrderStatus` at `order.php:1774-1799` references `cancelled`).
9. **`Database::updateStock` applies the same `stk` delta to every pack of a `vendor_product_id`.** Loop at `database.php:362-375` iterates every key in `packagesInfo` and uses the same `$stockToUpdate`. For a product with multiple pack sizes, ordering a 1 kg pack would also decrement a 5 kg pack's `stk`. May be intentional if `stk` is a shared canonical pool (kg), but the `in_stk` flip then does the same comparison against every pack's `ps`, which doesn't match that model. Verify with the DB owner.
10. **`echo "I'm here"` in production path** — `order.php:454`. Will corrupt JSON responses when the matching `off_on_total` branch triggers.
11. **New-customer offer-usage log at `order.php:775` references `$masterTableLastId`** inside `calculateOrderDetails`, but that variable is only ever defined in `placeNewOrder`. In `calculateOrderDetails` it is `null`, so these `offer_log` rows get a NULL `order_id` — or fail bind depending on strict mode. Also, `calculateOrderDetails` should probably not be writing to `offer_log` at all (it's a preview endpoint).
12. **Payment status inconsistency.** `master_orders.payment_status = "pending"` but child `orders.payment_status = "not_paid"`. Downstream UI code must normalise.
13. **SQL injection surface area.** `cancelOrder.php` (and much of `Database::*`) build conditions via string concatenation (e.g., `cancelOrder.php:16`, `database.php:151, 211, 238, 312`). All POST values flow into these conditions. If the new frontend doesn't sanitise `userId`/`orderId`, this is exploitable. Mitigate at the HTTP layer or add real parameterisation.
14. **`fetchDeliveryCharges.php` POST name is misleading.** The param is called `categoryTypeId` but the value expected is the vendor's admin id (e.g., `108`). The query inside is also commented as deceptive — see `deliveryDetails.php:12`.
15. **Timezone drift.** Prod MySQL is MST; PHP is forced to IST (`conn.php:7`). Any column that still relies on `DEFAULT CURRENT_TIMESTAMP` (e.g., all the "DB default" columns above) will store MST times. Only columns the code sets explicitly (`master_orders.created_at`, `offer_log.created_at`, `cart.created_at`) are IST.
16. **PHP 7.3 target.** No arrow functions / match / typed enums / nullsafe operator. The code already uses closure-style callbacks (e.g., `notif.php` uses `function(...) use (...)`); stick to that.
17. **`cart.total` is a client-sent breadcrumb; the server bills from the live `vendor_products.packs[pack_id].rp`.** `addProductToCart` writes whatever `total` the client POSTs (`cart.php:85`) and does not validate it against the catalog. `placeNewOrder` re-fetches the price live when building `orders_item` (`order.php:1220-1227`). Net effect: a tampered client total cannot inflate billing — but it can mislead the UI preview if the UI relies on `cart.total` after a price change. Always prefer `calculateOrderDetails`'s output over the raw cart `total`.
18. **`addProductToCart` has no duplicate detection.** Adding `(userId, addressId, product_id, vendor_product_id, pack_id)` twice creates two `cart` rows. The frontend must either call `updateCartedProductQuantity` to bump the existing row or `removeProductFromCart` first.
19. **`updateCartedProductQuantity` and `removeProductFromCart` are not scoped to `addressId`.** The `WHERE` clauses are `userid = ? AND pack_id = ?` (update) and `userid = ? AND pack_id = ? AND product_id = ?` (remove) — `cart/updateCartedProductQuantity.php:19`, `cart/removeProductFromCart.php:19`. If the same user has carts across addresses, both carts are mutated.
20. **`Cart::getCartData`'s `JOIN product` can duplicate rows.** Comment on `cart.php:23-24` warns that for multi-vendor scenarios where multiple `vendor_products` rows share a `product_id`, one carted item can surface as two rows after the join. If the new frontend sees phantom duplicates, this is the suspect.

---

## 15. TL;DR tables that get written per endpoint

| Endpoint | INSERTs into | UPDATEs | DELETEs from |
|---|---|---|---|
| `calculateOrderDetails.php` | (none) | (none) | (none) |
| `placeNewOrder.php` | `master_orders` ×1, `orders` ×N (N = #vendors), `orders_item` ×M (M = all paid + free items), `promo_log` ×K (K = #vendors with promo slice), `offer_log` ×F (F = #free-item rows) | `vendor_products.packs` for each distinct `vendor_product_id`; `promo.max_use` per promo-receiving vendor | `cart` (all rows for user+address, on wrapper success at `placeNewOrder.php:29`) |
| `cancelOrder.php` | (none) | `vendor_products.packs` (restock) | `orders_item`, `orders`, `offer_log` |
| `fetchDeliveryCharges.php` | (none) | (none) | (none) |

---

## 16. Minimum build checklist for the new frontend

To place an order from the new app, the client must:

1. **Populate `cart`** by calling `loagmaForArnav/cart/addProductToCart.php` for each item the user adds. See §1.2 for the required POST shape and §1.1 for all four cart endpoints. The order endpoints derive everything from the current `cart` state — no line-item array is passed to `calculateOrderDetails` or `placeNewOrder`.
2. **Preview the breakdown** by calling `calculateOrderDetails.php` with `userId`, `addressId`, `promoCode`. Display the returned `afterDiscount` as the "pay now" total. §6 covers the computation; §1.6 covers which cart columns feed it.
3. **Place the order** by calling `placeNewOrder.php` with `userId`, `addressId`, `promoCode`, and the exact `afterDiscount` as `totalAmount`. On success the response is `{"orderId": <master_orders.id>}` and the cart for that `(userId, addressId)` is cleared.
4. **Cancel (optional)** by calling `cancelOrder.php` with `userId` and the per-vendor `orders.order_id` — note this is **not** the master id returned above; the client must retrieve it from `fetchOrderList.php` / `fetchOrderDetails.php`.

Open items that need backend fixes before the new app can safely rely on them (list is non-exhaustive — see §14 for the full set):
- Pass `addressId` into `getDeliveryInfo` so orders ship to the user's actually-selected address.
- Wrap the vendor-loop writes in a DB transaction.
- Decide the real "cancelled" semantics (soft-delete + `order_state = cancelled`, refund `promo.max_use`, delete `promo_log` row).
- Parameterise all `Database::*` condition builders (SQL injection).
- Add a real payment gateway path and stop hard-coding `cod` / `not_paid` / `pending`.

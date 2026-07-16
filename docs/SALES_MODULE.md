# Sales Module — Sales Order, Sales Voucher/Invoice, Sales Return

**Status: authoritative, verified against live code on 2026-07-16.**
Older docs in this folder (`SALES_MODULE_HLD.md`, `sales_module_summary.md`, `invoice-generation-workflow.md`, `SALES_MODULE_COMPARISON.md`) predate the current implementation and disagree with it in places (see "Known drift from older docs" at the end). Where they conflict, this document wins.

## 0. The one thing to understand first

There is **no separate Sales Order table, Sales Invoice table, or Sales Return table**, and no Eloquent models for any of them. All three business concepts are the **same two legacy tables**:

- `loagma_new.orders` — one row per document family (header)
- `loagma_new.orders_item` — line items for that row

They're manipulated directly with Laravel's `DB::table()` query builder, not Eloquent. "Sales Order", "Sales Voucher/Invoice" and "Sales Return" are just different **states and column-sets** on the same row, not different documents. A dormant, fully-normalized schema (`sales_invoices` / `sales_invoice_items`, from migration `2026_04_25_000001_create_sales_invoices_tables.php`) exists for a possible future rewrite but nothing writes to it today — ignore it unless you're planning that migration.

Code lives in:

| File | Role |
|---|---|
| `app/Http/Controllers/SalesOrderController.php` | Sales Order create/edit/list/delete + Invoice generation + PDF |
| `app/Http/Controllers/SalesReturnController.php` | Sales Return create/edit/delete |
| `app/Services/InventoryLedgerService.php` | Shared stock mutation + ledger write, used by both controllers |
| `app/Services/InvoicePdfService.php` | Tax calculation + PDF rendering for the invoice |
| `resources/views/pdf/sales-invoice.blade.php` | Single-invoice PDF template |
| `resources/views/pdf/bulk-invoices.blade.php` | Multi-invoice combined PDF (e.g. per delivery trip) |

## 1. Data model

### `orders` (header)

Acts as the PK-less "PK" is `order_id` (see §6 — no real AUTO_INCREMENT, IDs are computed by the app).

| Column | Meaning |
|---|---|
| `order_id` | Row identity |
| `buyer_userid` | Customer FK → `user.userid` |
| `salesman_id` | FK → `LoginUser_crm.id` (joined with an explicit collation cast — the two tables don't share a collation) |
| `master_order_id` | 1:1 mirror row kept in sync in legacy `master_orders` (CRM/reporting) |
| `order_state` | Status field — **overloaded**, see §3 |
| `order_total`, `discount`, `delivery_charge` | Header money fields (pre-tax roll-up, see §5) |
| `bill_no` | Human invoice number string, e.g. `INV/25-26/007` |
| `invoice_number` | Integer sequence counterpart of `bill_no`, used for race-safe number generation |
| `Bill_Dt`, `Doc_Year`, `Bill_Narration`, `Bill_Vehicle`, `Bill_Statement`, `Department` | Invoice metadata |
| `bill_roff` | Manual round-off applied at PDF/grand-total stage |
| `charges_json` | JSON array of extra charges (freight, handling, etc.) |
| `Sales_Return_VoucherNo`, `Sales_Return_Dt`, `Sales_Return_Reason` | Populated once a return is filed against this order |
| `sales_return_charges_json` | Extra charges tied to the return |
| `invoice_pdf_url` | Cached public URL of the last-rendered PDF |
| `idempotency_key` | Dedup key for retried `POST /sales-orders` |

### `orders_item` (line items)

| Column | Meaning |
|---|---|
| `item_id` | Row identity (no real AUTO_INCREMENT, same as `order_id`) |
| `order_id` | FK → `orders.order_id` |
| `product_id` | FK → `product.product_id` |
| `quantity` | Originally ordered qty |
| `qty_loaded` | Set by driver/dispatch app — **this is the quantity that actually prints on the invoice PDF**, not `qty_delivered` (see §5, gotcha) |
| `qty_delivered` | Quantity delivered/billed, set at invoicing time from the request |
| `qty_returned` | Cumulative returned quantity — only ever written by the Sales Return flow; preserved across Sales Order edits |
| `item_price` | Unit price |
| `item_total` | Server-computed `quantity × item_price`, never independently editable |
| `pinfo` (JSON) | Everything else: `hsn_code`, `unit`, `selected_pack`, `description`, `discount_percent`, `tax_percent`, `sgst_percent`/`cgst_percent`/`igst_percent`, `price_inclusive`, `unit_price_inclusive` |
| `return_reason` | Per-line return reason |

No `vendor_product_id` is persisted on the item row by the current flow — the vendor/stock pool is re-resolved at invoicing time via `InventoryLedgerService::resolveVendorProduct()`.

## 2. Order → Invoice → Return, conceptually

```
POST /sales-orders (status: pending)         -> draft Sales Order, no stock movement
PUT  /sales-orders/{id} (status: invoiced)    -> same row becomes the Invoice/Voucher
                                                  bill_no assigned, stock decremented (DEBIT)
POST /sales-returns (source_order_id: {id})   -> return recorded on the SAME row
                                                  qty_returned incremented, stock incremented (CREDIT)
```

- **Invoicing is a state mutation, not a new document.** One order has at most one `bill_no` at a time.
- **A "direct sale" with no prior draft order is supported**: `POST /sales-orders` with `status: "invoiced"` in one call creates the row already invoiced (stock decremented, PDF generated). It still lives in the `orders` table — there's no invoicing path that bypasses the order object.
- **Partial fulfillment is modeled per line item** via `qty_delivered` vs `quantity`, not by splitting into multiple invoices. One order can only ever have one active invoice number.
- **Re-invoicing** (editing an already-invoiced order) reuses the same `bill_no` unless the caller supplies a different manual override.
- **Cancelling an invoice** (`PUT .../{id}` with `cancel_invoice: true`) is the only way to un-invoice: clears `bill_no`/`Bill_Dt`, reverts `order_state` to `pending` — but see §5 for the stock gap this leaves.
- **Editing is blocked (422)** once any item has `qty_returned > 0` — resolve/delete the return first.
- **Deleting an order is blocked** once `bill_no` is set — cancel the invoice first.
- **Idempotency**: `store()` honors an `Idempotency-Key` field/header; a retried submission with the same key returns the original order instead of double-creating/double-decrementing stock.

## 3. Status field (`orders.order_state`)

This column is **overloaded across two different vocabularies** depending on which flow last touched the row — a real subtlety, not a typo:

- **Sales Order/Invoice lifecycle** (current code, lowercase): `pending`, `dispatched`, `delivered`, `invoiced`, `cancelled`, `rejected`, `returned`.
  - `CLOSED_STATES = ['cancelled', 'rejected', 'returned']` — edits blocked (422) once in one of these.
  - The "returnable" list filter matches `delivered`, `dispatched`, `invoiced`.
- **Sales Return's own status** (uppercase, written into the *same* column once a return is filed): `DRAFT`, `POSTED`, `CANCELLED`.

So after a return is created, `order_state` no longer holds an order-lifecycle value — it holds the return's own status until the return is deleted, at which point the controller explicitly resets it back to `invoiced`.

> Older docs describe the billed state as `'billed'`/`BILLED`. The live controller code uses lowercase `'invoiced'`. Trust the code.

## 4. Controllers — endpoints and responsibilities

### `SalesOrderController`

| Method | Route | Notes |
|---|---|---|
| `series()` | `GET /sales-orders/invoice-series` | Non-authoritative preview of the next invoice number |
| `index()` | `GET /sales-orders` | Paginated/filterable list |
| `store()` | `POST /sales-orders` | Creates order; if `status=invoiced`, also decrements stock, writes ledger, generates PDF |
| `storeBulk()` | `POST /sales-orders/bulk` | Bulk create; **does not touch the stock ledger at all** |
| `bulkInvoice()` | `POST /sales-orders/bulk-invoice` | Bulk-transitions existing orders to `invoiced`; **also skips the stock ledger**; public route, no auth |
| `update()` | `PUT /sales-orders/{id}` | Full delete+reinsert of items; handles `cancel_invoice`; reverses+reapplies stock ledger for billed orders |
| `destroy()` | `DELETE /sales-orders/{id}` | Blocked if `bill_no` is set |
| `show()` | `GET /sales-orders/{id}` | Full detail with computed `left_qty`/`available_to_return` |
| `generatePdf()` | `GET /sales-orders/{id}/pdf` | Lazy PDF render fallback; public route, no auth |
| `bulkPdf()` | `POST /sales-orders/bulk-pdf` | Combined multi-order PDF (e.g. per trip); public route, no auth |

### `SalesReturnController`

| Method | Route | Notes |
|---|---|---|
| `series()` | `GET /sales-returns/series` | Preview of next return voucher number (not lock-protected, see §6) |
| `index()` | `GET /sales-returns` | Orders where `Sales_Return_VoucherNo IS NOT NULL` |
| `show()` | `GET /sales-returns/{id}` | `{id}` is the source `order_id`, not a separate return ID |
| `store()` | `POST /sales-returns` | Creates a return against `source_order_id`; one active return per order |
| `update()` | `PUT /sales-returns/{id}` | Delta-based: resets all items' `qty_returned` then re-applies per-item deltas |
| `destroy()` | `DELETE /sales-returns/{id}` | Clears return columns, zeroes `qty_returned`, reverts `order_state` to `invoiced` — **does not reverse stock** |

Full route list is in `routes/api.php`. Note that `bulk-invoice`, `bulk-pdf`, and the single-order PDF `GET` are registered **outside** the authenticated `module:sales` group — they're publicly reachable with no auth. `bulk-invoice` mutates data, so this is worth treating as a security gap if it isn't already tracked.

## 5. Pricing and tax — two separate calculations

**At order/invoice entry time** (`store()`/`update()`): `order_total = round(Σ(qty × item_price) − discount + delivery, 2)`. This is a simple pre-tax roll-up. Per-item tax/discount percentages are captured into `pinfo` but not used here.

**At PDF-render time** (`InvoicePdfService::buildData()`) — this is where the real tax math happens, per line:
1. `unitInclusive` = tax-inclusive unit rate, from `pinfo.unit_price_inclusive` if saved, else reconstructed as `round(price * (1 + taxPct/100), 2)`.
2. `lineTotal = round(qty * unitInclusive * (1 - discPct/100), 2)`
3. `taxableAmt = taxPct > 0 ? round(lineTotal / (1 + taxPct/100), 2) : lineTotal`
4. `lineTax = lineTotal - taxableAmt`
5. GST split: IGST if `igstPct > 0` (inter-state), else SGST+CGST.
6. Legacy orders without a saved tax breakdown fall back to a `product_taxes`/`taxes` lookup.
7. `grandTotal = round(subtotalExclTax + taxTotal + chargesTotal + billRoff, 2)` — charges and round-off are only added at this final stage.

**Consequence:** `orders.order_total` and the PDF's `grand_total` are computed independently and are **not guaranteed to match**. Don't treat them as interchangeable in reporting.

**Gotcha — invoice quantity source:** the PDF bases the printed `quantity` on `orders_item.qty_loaded` (what dispatch/driver loaded), **not** `qty_delivered`. If you're debugging a mismatch between what a screen shows as "delivered" and what prints on the invoice, this is almost always why.

**Gotcha — GST is currently always intra-state (SGST+CGST):** `user.state` was dropped from the live DB, so `InvoicePdfService` hardcodes `customerState = companyState`. Inter-state customers are still invoiced with an intra-state tax split until this is revisited.

**Sales Return** does not recompute tax — the ledger amount for a return is simply `returnedQty × original item_price`, no tax breakdown persisted.

## 6. Numbering

- **Invoice number**: prefix `INV/{FY}/` (e.g. `INV/25-26/`), rolls over every April. The authoritative number is resolved inside the write transaction with `SELECT ... FOR UPDATE` (`lockForUpdate()`) over rows in the current `Doc_Year`, so concurrent invoice creation is safely serialized. A manually-typed `bill_no` that doesn't match the prefix pattern is honored as-is without consuming the sequence.
- **Sales Return voucher number**: prefix `SR/{FY}/`, same rollover — but generated via a plain `COUNT(*) + 1`, **without `lockForUpdate()`**. This is a real inconsistency with the invoice-number path and is more susceptible to duplicate numbers under concurrent return creation.
- **Row IDs (`order_id`, `item_id`)**: `orders`/`orders_item` have **no real AUTO_INCREMENT** on TiDB (confirmed in the live schema dump — no `PRIMARY KEY`/`AUTO_INCREMENT` clause). The app computes the next ID as `MAX(id) + 1` in application code (`nextOrderId()`/`nextItemId()`). `storeBulk()` locks the max once per batch; single-row `store()`/`update()` do **not** lock at all — a theoretical ID collision exists under true concurrent writes that don't share an idempotency key. This is the same class of gotcha as other legacy tables lacking real AUTO_INCREMENT on TiDB (`taxes`, `hsn_codes`, `suppliers`, `purchase_*`, `stock_voucher`, `api_tokens`, `units_master`).

## 7. Stock / inventory interaction

Full reference: `docs/STOCK_LEDGER.md`. Sales-relevant summary:

- Stock is authoritative in `product.stock` (for `SINGLE` inventory type) or in `vendor_products.packs[].stk` summed across rows (for `PACK_WISE`). `product.stock` for `PACK_WISE` products is currently unreliable — never trust it, sum the packs instead.
- Shared mutation path: `InventoryLedgerService::resolveVendorProduct()` → `updatePacksStock()` → `recordLedger()` (writes to `vendor_products_inventory`, a write-only audit table nothing currently reads back).
- **Stock only moves when `order_state = 'invoiced'`.** Draft/pending/dispatched orders never touch stock.
- **On `store()`**: decrement stock per item, ledger row `action_type=sale`, `inv_type=DEBIT`, `source=sales_invoice`.
- **On `update()` of an already-invoiced order**: the entire previous effect is reversed first (`sale_reversal`, CREDIT, full old quantities), then the new item list is fully reapplied (`sale`, DEBIT) — even if only one field changed. Expect multiple ledger rows to accumulate on repeatedly-edited invoices.
- **Sales Return `store()`**: validates `returnedQty ≤ qtyDelivered − alreadyReturned` (422 if exceeded), increases stock, writes `sale_return`/CREDIT.
- **Sales Return `update()`**: delta-based; `delta > 0` increases stock with a CREDIT row; `delta < 0` decreases stock but writes no ledger row at all (audit gap).

### Known gaps (call these out explicitly if you touch this code)

1. `cancel_invoice` never reverses stock — the original decrement is stranded with no CREDIT to undo it.
2. `storeBulk()` and `bulkInvoice()` skip the ledger entirely — no stock movement, no ledger row, even though they can put orders directly into `invoiced` state.
3. Sales Return `update()` with a negative delta moves stock without writing a ledger row.
4. Sales Return `destroy()` never reverses the earlier stock credit — deleting a return permanently inflates stock with no automatic correction (only a manual stock voucher can fix it).
5. Multi-supplier products: `resolveVendorProduct()` falls back to "first active `vendor_products` row" when there's no explicit vendor context — can silently post against the wrong supplier's stock pool.
6. `updatePacksStock()` moves every pack in a `vendor_products` row together, even though only one specific pack was sold — the `pack_id` on the ledger row is for attribution only, it doesn't scope the mutation.

## 8. PDF generation

- Rendered via `barryvdh/laravel-dompdf`, driven by `InvoicePdfService` (`generateAndStore()` eager render on create/edit/bulk-invoice, `generateContent()` lazy on-demand fallback, `generateBulkContent()` for multi-invoice combined PDFs).
- Templates: `resources/views/pdf/sales-invoice.blade.php` (single invoice), `resources/views/pdf/bulk-invoices.blade.php` (combined, e.g. per delivery trip).
- **Both templates are `<table>`-based, not flex/grid**, because dompdf 3.x ignores flexbox — this must be preserved in any future edits (see project memory: "Invoice PDF must use table layout").
- Storage: `documents/sales-invoices/{doc_year}/{bill_no with / replaced by _}.pdf` on the `public` disk; the resulting URL is cached onto `orders.invoice_pdf_url`.
- PDF generation is fully server-side (not client-side as an older doc claims — see drift note below).

## 9. Known drift from older docs in this folder

- `SALES_MODULE_HLD.md`, `sales_module_summary.md`: describe the billed state as `'billed'`/`BILLED`; live code uses `'invoiced'`.
- `invoice-generation-workflow.md`: describes PDF generation as client-side/triggered separately with no server call; the live implementation is fully server-side via `InvoicePdfService`.
- `SALES_MODULE_COMPARISON.md`: proposes a normalized 7-table future schema (`sales_customers`, `sales_orders`, `sales_order_items`, `sales_payments`, `sales_shipments`, `sales_returns`, `sales_return_items`). This is a **proposal**, not implemented — the live system is still the single `orders`/`orders_item` design described above.

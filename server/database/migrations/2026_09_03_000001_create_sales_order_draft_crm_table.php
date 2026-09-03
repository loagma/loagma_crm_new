<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * An un-submitted Create Sales Order cart, so closing the sheet (or the app)
 * without checking out doesn't lose it. One row per (staff member, account):
 * a salesman's in-person draft for a shop and a telecaller's phone draft for
 * that same shop are independent, because `staff_id` is part of the key.
 *
 * Deliberately NOT the shared `cart` table, which the CRM used to write to:
 *   - `cart` has no staff column, and its only free-ish column (`ctype_id`)
 *     is a taxonomy key the consumer app joins to `cart_type` for express /
 *     min-total / delivery-charge rules — it can't be namespaced per staff.
 *   - `cart`'s UNIQUE KEY is (userid, product_id, pack_id, addressId) with no
 *     `ctype_id`, so a CRM upsert would match — and `clear()` would delete —
 *     the customer's own consumer-app cart line for the same product+pack.
 *   - It has nowhere to put addons, narration, dates or the delivery address,
 *     and its NOT NULL `pack_id` can't represent a hand-typed line at all.
 *
 * The whole draft therefore lives in one JSON `payload` rather than a row per
 * line item: it's only ever read and written wholesale by the sheet, never
 * queried across, so a schema of its own would buy nothing.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('sales_order_draft_crm', function (Blueprint $table) {
            $table->bigIncrements('id');
            $table->string('staff_id', 20);                    // deli_staff.mobile of whoever is building the cart
            $table->string('account_id', 64);                  // user.userid (customer) or leads_account_crm.id (lead)
            $table->enum('account_type', ['lead', 'customer']);
            $table->longText('payload');                       // {items, addons, narration, document_date, expected_date, delivery_address}
            $table->timestamps();

            // One live draft per staff member per account — the sheet upserts
            // against exactly this key.
            $table->unique(['staff_id', 'account_id', 'account_type'], 'sales_order_draft_crm_owner_unique');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('sales_order_draft_crm');
    }
};

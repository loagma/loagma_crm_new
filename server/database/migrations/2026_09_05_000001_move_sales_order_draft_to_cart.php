<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Per an explicit product decision, the Create Sales Order draft is moved off
 * its own `sales_order_draft_crm` table and onto the shared `cart` table, and
 * `sales_order_draft_crm` is dropped.
 *
 * `cart` was not built for this, so the draft is stored as ONE row per
 * (staff, account) carrying the whole draft in `draft_payload` (JSON) — it is
 * not a real per-line cart. To coexist with the consumer app:
 *
 *   - New columns are all nullable; consumer-app inserts never touch them.
 *   - CRM draft rows are tagged `ctype_id = 'crm_sales_draft'`, a value no
 *     `cart_type` row maps to, so consumer-app cart queries (which filter by
 *     `userid` + a real `ctype_id`) never see them.
 *   - The pre-existing UNIQUE KEY `unique_user_product_pack_address`
 *     (userid, product_id, pack_id, addressId) is left untouched. CRM rows set
 *     product_id = 0, addressId = 0 and pack_id = "crmdraft:{staff}|{type}|{ref}",
 *     so that key stays unique per (staff, account) and cannot collide with a
 *     real consumer row (whose product_id is never 0).
 *   - A second UNIQUE KEY on (staff_id, account_ref, account_type) is added for
 *     the CRM upsert; consumer rows leave all three NULL and NULLs do not
 *     collide in a unique index.
 *
 * `cart.cart_id` has no AUTO_INCREMENT — the controller allocates MAX+1 under a
 * row lock, same pattern as `orders.order_id`.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('cart', function (Blueprint $table) {
            $table->string('staff_id', 20)->nullable()->after('created_at');
            $table->string('account_ref', 64)->nullable()->after('staff_id');
            $table->string('account_type', 16)->nullable()->after('account_ref');
            $table->longText('draft_payload')->nullable()->after('account_type');
            $table->unique(['staff_id', 'account_ref', 'account_type'], 'cart_crm_draft_unique');
        });

        Schema::dropIfExists('sales_order_draft_crm');
    }

    public function down(): void
    {
        Schema::create('sales_order_draft_crm', function (Blueprint $table) {
            $table->bigIncrements('id');
            $table->string('staff_id', 20);
            $table->string('account_id', 64);
            $table->enum('account_type', ['lead', 'customer']);
            $table->longText('payload');
            $table->timestamps();
            $table->unique(['staff_id', 'account_id', 'account_type'], 'sales_order_draft_crm_owner_unique');
        });

        // Carry any live drafts back before removing them from `cart`.
        foreach (DB::table('cart')->where('ctype_id', 'crm_sales_draft')->get() as $row) {
            DB::table('sales_order_draft_crm')->insert([
                'staff_id'     => $row->staff_id,
                'account_id'   => $row->account_ref,
                'account_type' => $row->account_type,
                'payload'      => $row->draft_payload ?? '{}',
                'created_at'   => $row->created_at,
                'updated_at'   => $row->created_at,
            ]);
        }
        DB::table('cart')->where('ctype_id', 'crm_sales_draft')->delete();

        Schema::table('cart', function (Blueprint $table) {
            $table->dropUnique('cart_crm_draft_unique');
            $table->dropColumn(['staff_id', 'account_ref', 'account_type', 'draft_payload']);
        });
    }
};

<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

// Direct one-customer -> one-employee assignment, set by an admin from the
// "Customer Assign" screen. This is deliberately separate from the area-based
// allotment in area_assign_crm: an area assignment fans a whole pincode out to
// a salesman/telecaller, whereas a row here pins a single `user` customer to a
// single employee regardless of area. The employee sees both merged in their
// Allotted Customers list.
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('customer_assign_crm', function (Blueprint $table) {
            $table->bigIncrements('id');
            $table->unsignedBigInteger('customer_userid')->unique(); // user.userid
            $table->string('employee_mobile', 20);                   // deli_staff.mobile
            $table->string('assigned_by', 20)->nullable();           // admin mobile
            $table->timestamps();

            $table->index('employee_mobile');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('customer_assign_crm');
    }
};

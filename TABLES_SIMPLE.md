# Database Tables — Loagma CRM (Simple Reference)

27 tables that the Laravel backend (`server/`) actually reads or writes, table name bolded, one line per column. Pulled live from the production schema (`loagma_new`), so it reflects what's really deployed — not migration files.

## Summary

| # | Table | What it's for |
|---|-------|----------------|
| 1 | **deli_staff** | Staff/employee login & profile (core auth table) |
| 2 | **user** | Customer accounts |
| 3 | **user_addresses** | Customer delivery addresses |
| 4 | **area_crm** | Named service areas |
| 5 | **area_assign_crm** | Employee-to-area assignment |
| 6 | **incharge_assign_crm** | Incharge hierarchy |
| 7 | **LeadsAccount_crm** | Prospect/lead accounts (telecaller funnel) |
| 8 | **role_crm** | List of valid staff roles |
| 9 | **units_master** | Unit of measure lookup |
| 10 | **attendance_crm** | Punch in/out records |
| 11 | **location_pings_crm** | Live GPS trail |
| 12 | **beat_plan_crm** | Recurring visit schedule |
| 13 | **beat_plan_visit_crm** | Single scheduled visit |
| 14 | **call_log_crm** | Call history |
| 15 | **call_scripts_crm** | Canned call scripts |
| 16 | **complaint_crm** | Customer complaints |
| 17 | **order_funnel_crm** | Funnel stage lookup |
| 18 | **order_funnel_response_crm** | Visit funnel form |
| 19 | **telecaller_label_crm** | Quick account labels |
| 20 | **orders** | Order header (shared/legacy) |
| 21 | **orders_item** | Order line items (shared/legacy) |
| 22 | **master_orders** | Groups a multi-vendor checkout (shared/legacy) |
| 23 | **product** | Product catalog (shared/legacy) |
| 24 | **vendor_products** | Per-vendor product overrides (shared/legacy) |
| 25 | **product_taxes** | Product tax rate history (shared/legacy) |
| 26 | **taxes** | Tax rate lookup (shared/legacy) |
| 27 | **admin** | Vendor/admin accounts (shared/legacy, read-only here) |

Tables 1–19 are owned by this app (CRM/telecalling/tracking). Tables 20–27 belong to the older shared ERP but this app reads and, in most cases, writes to them directly.

---

## Full detail

**deli_staff** - staff/employee login & profile
    deli_id - primary key
    admin_id - which admin/vendor the staff belongs to
    role - telecaller / deli_staff / incharge / zonal_incharge / head_incharge / teleadmin / admin
    name - staff name
    mobile - login id
    password - login password, also reused as the OTP code
    otp - unused
    otp_expires_at - unused
    permissions - JSON permission flags
    sess_id - session id
    lat - last known latitude
    lng - last known longitude
    pincode - last known pincode
    city - last known city
    state - last known state
    location_last_updated - last GPS update time
    is_locked - account disabled flag
    punch_in_time - shift start time
    punch_out_time - shift end time
    grace_minutes - late-arrival tolerance
    approval_required - needs manual attendance approval

**user** - customer accounts
    userid - primary key
    email - customer email
    is_email_verified - email verified flag
    contactno - customer phone
    is_contact_verified - phone verified flag
    name - customer name
    account_state - account status
    address - customer address
    latitude - location
    longitude - location
    dob - date of birth
    register_date - signup date
    shop_name - shop name
    shop_address - shop address
    shop_plot_no - shop plot number
    user_type - customer type
    adhar_card - Aadhar number
    shop_photo - shop photo url
    shop_licence - shop license doc
    bussiness_pan_card - PAN doc
    is_approved - approval status
    session_id - login session
    last_activity - last active timestamp
    push_notif_id - push notification token
    is_first_login - first login flag
    has_unread_comments - unread comments flag
    password - login password
    pincode - customer pincode
    city - customer city
    state - customer state
    gst_no - GST number
    party_code - party code
    lead_account_id - link to LeadsAccount_crm after conversion

**user_addresses** - customer delivery addresses
    id - primary key
    user_id - link to user
    full_name - recipient name
    full_address - full address text
    phone_no - contact number
    name - address label name
    address - address text
    lat - latitude
    lng - longitude
    pincode - pincode
    type - home / shop / other
    city_id - city reference
    area_id - area reference
    is_default - default address flag
    created_at - created timestamp

**area_crm** - named service areas
    id - primary key
    area_name - area name
    pincodes - JSON list of pincodes covered
    created_at - created timestamp
    updated_at - updated timestamp

**area_assign_crm** - employee-to-area assignment
    id - primary key
    area_ids - JSON list of assigned area ids
    area_names - JSON list of area names
    employee_id - link to deli_staff
    created_at - created timestamp
    updated_at - updated timestamp

**incharge_assign_crm** - incharge hierarchy
    id - primary key
    head_incharge_id - link to deli_staff (head incharge)
    incharge_ids - JSON list of incharges under them
    incharge_names - JSON list of incharge names
    created_at - created timestamp
    updated_at - updated timestamp

**LeadsAccount_crm** - prospect / lead accounts
    id - primary key (uuid)
    accountCode - lead account code
    businessName - business name
    businessType - business type
    businessSize - business size
    personName - contact person name
    contactNumber - phone number
    dateOfBirth - date of birth
    customerStage - pipeline stage
    funnelStage - funnel stage
    gstNumber - GST number
    panCard - PAN
    ownerImage - owner photo
    shopImage - shop photo
    isActive - active flag
    pincode - pincode
    country - country
    state - state
    district - district
    city - city
    area - area name
    address - address text
    latitude - location
    longitude - location
    areaId - link to area_crm
    assignedToId - assigned telecaller (deli_staff)
    assignedDays - JSON assigned visit days
    createdById - who created it
    approvedById - who approved it
    approvedAt - approval timestamp
    isApproved - approved flag
    approval_status - approval status text
    verificationNotes - verification notes
    rejectionNotes - rejection notes
    createdAt - created timestamp
    updatedAt - updated timestamp

**role_crm** - list of valid staff roles
    id - primary key
    role_name - role name
    created_at - created timestamp
    updated_at - updated timestamp

**units_master** - unit of measure lookup
    unit_id - primary key
    unit_name - unit name (kg, box, litre...)
    dimension - unit dimension
    base_unit_name - base unit reference
    serial_no - display order
    conversion_rate - conversion factor
    is_active - active flag
    created_at - created timestamp

**attendance_crm** - punch in/out records
    id - primary key
    employee_mobile - link to deli_staff
    date - attendance date
    punch_in_time - punch-in time
    punch_in_photo - punch-in selfie
    punch_in_location - punch-in GPS
    punch_out_time - punch-out time
    punch_out_photo - punch-out selfie
    punch_out_location - punch-out GPS
    last_ping_at - last location ping time
    was_interrupted - shift interrupted flag
    total_distance_km - distance travelled
    route_snapped - snapped route path
    auto_closed - auto-closed shift flag
    break_details - JSON break log
    total_work_minutes - total worked minutes
    total_break_minutes - total break minutes
    is_late - late flag
    is_early_out - early checkout flag
    is_early_in - early checkin flag
    late_reason - reason for being late
    early_out_reason - reason for early out
    early_in_reason - reason for early in
    status - pending / approved / rejected
    admin_notes - admin remarks
    approved_by - approver id
    approved_at - approval timestamp
    created_at - created timestamp
    updated_at - updated timestamp

**location_pings_crm** - live GPS trail
    id - primary key
    employee_mobile - link to deli_staff
    date - ping date
    lat - latitude
    lng - longitude
    accuracy - GPS accuracy
    speed - movement speed
    heading - direction heading
    battery - device battery %
    is_mock - fake GPS detected flag
    recorded_at - ping timestamp

**beat_plan_crm** - recurring visit schedule
    id - primary key
    account_id - customer/lead being visited
    account_type - user or lead
    salesman_id - assigned staff
    frequency - daily / weekly / monthly / interval
    days - JSON days of week
    week_anchor_date - week reference date
    month_date - day of month
    specific_dates - JSON custom dates
    appointment_date - specific appointment
    interval_days - repeat interval
    start_date - plan start date
    is_active - active flag
    created_at - created timestamp
    updated_at - updated timestamp

**beat_plan_visit_crm** - single scheduled visit
    id - primary key
    beat_plan_id - link to beat_plan_crm
    account_id - customer/lead
    salesman_id - assigned staff
    visit_date - date of visit
    status - pending / done / missed
    notes - visit notes
    created_at - created timestamp
    updated_at - updated timestamp

**call_log_crm** - call history
    id - primary key
    employee_mobile - caller staff
    source - manual or knowlarity
    direction - inbound / outbound
    knowlarity_call_id - webhook call id
    duration_seconds - call length
    recording_url - call recording link
    raw_payload - full webhook JSON
    account_id - customer/lead called
    account_type - user or lead
    call_outcome - outcome/result
    notes - call notes
    follow_up_date - next follow-up date
    callback_done - callback completed flag
    called_at - call time
    created_at - created timestamp
    updated_at - updated timestamp

**call_scripts_crm** - canned call scripts
    id - primary key
    employee_mobile - script owner (or shared)
    title - script title
    stage_label - funnel stage label
    lines - JSON script lines
    sort_order - display order
    created_at - created timestamp
    updated_at - updated timestamp

**complaint_crm** - customer complaints
    id - primary key
    account_id - customer/lead
    account_type - user or lead
    source_channel - call / visit / manual
    raised_by - staff who logged it
    assigned_to - staff handling it
    assigned_by - who assigned it
    assigned_at - assignment time
    call_log_id - originating call
    beat_plan_id - originating visit
    category - complaint category
    description - complaint text
    status - open / in_progress / resolved
    resolution_notes - resolution details
    resolved_by - who resolved it
    resolved_at - resolution time
    created_at - created timestamp
    updated_at - updated timestamp

**order_funnel_crm** - funnel stage lookup
    id - primary key
    slug - stage code
    name - stage label
    sort_order - display order
    is_active - active flag
    created_at - created timestamp
    updated_at - updated timestamp

**order_funnel_response_crm** - visit funnel form
    id - primary key
    employee_mobile - staff who filled it
    account_id - customer/lead visited
    account_type - user or lead
    beat_plan_id - linked visit plan
    visit_in_at - visit start time
    visit_out_at - visit end time
    duration_seconds - visit duration
    funnel_slug - selected funnel stage
    funnel_name - stage name
    general_notes - general notes
    notes_related_to - notes context
    images - JSON photo urls
    created_at - created timestamp
    updated_at - updated timestamp

**telecaller_label_crm** - quick account labels
    id - primary key
    employee_mobile - who set the label
    account_id - customer/lead
    account_type - user or lead
    label - label text (e.g. hot lead, do not call)
    created_at - created timestamp
    updated_at - updated timestamp

**orders** - order header (legacy, shared with old ERP)
    order_id - primary key
    bill_no - bill number
    invoice_number - invoice number
    charges_json - extra charges JSON
    invoice_pdf_url - invoice PDF link
    bill_dt - bill date
    department - department tag
    bill_narration - bill remarks
    expected_date - expected delivery date
    bill_roff - rounding adjustment
    doc_year - financial year
    sales_return_voucher_no - return voucher number
    sales_return_dt - return date
    sales_return_status - return status
    sales_return_reason - return reason
    sales_return_charges_json - return charges JSON
    salesman_id - staff who booked it
    master_order_id - link to master_orders
    txn_id - payment transaction id
    buyer_userid - customer who ordered
    start_time - order start timestamp
    last_update_time - last update timestamp
    short_datetime - display datetime
    order_state - order status
    payment_method - payment method
    ctype_id - customer type
    items_count - number of items
    delivery_charge - delivery fee
    order_total - total amount
    bill_amount - final bill amount
    delivery_info - delivery notes
    area_name - delivery area
    feedback - customer feedback
    admin_id - vendor/admin who owns it
    payment_status - payment status
    amountReceivedInfo - payment collection info
    trip_id - delivery trip id
    discount - discount amount
    before_discount - amount before discount
    time_slot - delivery time slot
    delivered_time - delivery timestamp
    deli_id - delivery staff id
    idempotency_key - dedupe key for double-submits

**orders_item** - order line items
    order_id - link to orders
    item_id - primary key
    product_id - link to product
    vendor_product_id - vendor-specific product
    pinfo - product info snapshot
    offers - applied offers snapshot
    quantity - quantity ordered
    qty_loaded - quantity loaded for delivery
    qty_delivered - quantity delivered
    qty_returned - quantity returned
    return_reason - return reason
    item_price - price per item
    item_total - line total
    op_id - operation reference
    commission - commission earned

**master_orders** - groups a multi-vendor checkout
    id - primary key
    user_id - customer who checked out
    txn_id - payment transaction id
    payment_status - payment status
    order_count - number of orders in this checkout
    payment_method - payment method
    delivery_info - delivery notes
    order_total - total across all orders
    delivery_charge - total delivery fee
    discount - total discount
    before_discount - amount before discount
    status - overall status
    created_at - created timestamp

**product** - product catalog (legacy, shared with old ERP)
    product_id - primary key
    cat_id - category id
    parent_cat_id - parent category id
    brand - brand name
    ctype_id - customer type restriction
    seq_no - display order
    start_date - listing start date
    is_published - published flag
    is_used - in-use flag
    is_deleted - soft delete flag
    in_stock - stock availability
    inventory_type - inventory type
    inventory_unit_type - unit type
    stock_uom - stock unit of measure
    name - product name
    short_name - short name
    description - product description
    display_photo - product image
    keywords - search keywords
    spec_params - specification params
    packs - JSON pack/pricing options (only ~3% of products have real pricing here)
    default_pack_id - default pack reference
    hsn_code - HSN tax code
    gst_percent - GST rate
    offers - offers text
    cache_txt - cached display text
    img_last_updated - image update timestamp
    stock - stock quantity
    stock_ut_id - stock unit reference
    order_limit - max order quantity
    buffer_limit - buffer stock quantity
    nop - number of packs
    is_taxable - taxable flag
    exempt_from - tax exemption start
    exempt_to - tax exemption end

**vendor_products** - per-vendor product overrides
    id - primary key
    admin_vendor_id - vendor/admin id
    product_id - link to product
    packs - vendor-specific pack pricing
    default_pack_id - default pack reference
    status - listing status
    in_stock - stock availability
    created_at - created timestamp

**product_taxes** - product tax rate history
    id - primary key
    product_id - link to product
    tax_id - link to taxes
    tax_percent - tax rate
    effective_from - rate start date
    effective_to - rate end date
    created_at - created timestamp
    updated_at - updated timestamp

**taxes** - tax rate lookup
    id - primary key
    tax_category - tax category
    tax_sub_category - tax sub-category
    tax_name - tax name
    is_active - active flag
    created_at - created timestamp
    updated_at - updated timestamp

**admin** - vendor/admin accounts (legacy, read-only here)
    userid - primary key
    session_id - login session
    username - login username
    name - admin/vendor name
    password - login password
    type - account type
    register_date - signup date
    last_activity - last active timestamp
    data - misc data blob
    delivery_manage_by - delivery management owner
    org_name - organization name
    org_email - organization email
    org_contact_no - organization phone
    org_gst - organization GST
    org_address - organization address
    category_id - category ids handled
    city_id - city reference
    areas - service areas
    web_token - API/web token
    commission - commission rate
    fssai_no - FSSAI license number
    gst_no - GST number
    licence_1 - license doc 1
    licence_2 - license doc 2
    bank_name - bank name
    bank_branch - bank branch
    account_number - bank account number
    ifsc_code - bank IFSC code
    account_type - bank account type
    scanner_qr - payment QR code
    phonepe_no - PhonePe number
    gpay_no - GPay number

# changes.sql: Simple Guide

`changes.sql` does 3 things to the prod database:
1. Creates **21 new tables** for the CRM.
2. Adds **new columns to 3 existing tables** (`deli_staff`, `user`, `cart`).
3. Inserts **master data** the app needs (roles, visit outcomes, languages).

**Common columns.** Most tables also have:
- `id`: the row number, unique for every row
- `created_at`: when the row was created
- `updated_at`: when the row was last changed

---

## PART 1: New tables

### 1. `role_crm`: list of staff roles
| Column | Purpose |
|---|---|
| `role_name` | Role name, e.g. admin, salesman, telecaller, teleadmin, head_incharge |

### 2. `language_crm`: list of languages
| Column | Purpose |
|---|---|
| `name` | Language name (Hindi, English…) |
| `code` | Short code (hi, en…) |
| `is_active` | 1 = show it in the dropdown, 0 = hide it |
| `sort_order` | Order in the dropdown |

### 3. `area_crm`: marketing areas
| Column | Purpose |
|---|---|
| `area_name` | Area name |
| `pincodes` | List of pincodes inside this area |

### 4. `area_assign_crm`: which areas each employee works in
| Column | Purpose |
|---|---|
| `employee_id` | Employee's mobile number |
| `area_ids` | IDs of the areas given to the employee |
| `area_names` | Names of those areas |

### 5. `incharge_assign_crm`: team hierarchy (who reports to whom)
| Column | Purpose |
|---|---|
| `head_incharge_id` | Senior's mobile number |
| `incharge_ids` | Mobile numbers of the people under that senior |
| `incharge_names` | Names of those people |

### 6. `customer_assign_crm`: one customer given directly to one employee
| Column | Purpose |
|---|---|
| `customer_userid` | Customer ID (from the `user` table) |
| `employee_mobile` | Employee who handles this customer |
| `assigned_by` | Admin who made the assignment |

### 7. `LeadsAccount_crm`: leads (new shops that aren't customers yet)
| Column | Purpose |
|---|---|
| `id` | Unique lead ID |
| `accountCode` | Lead number shown in the app (1001, 1002…) |
| `businessName` | Shop / business name |
| `businessType` | Retail, Wholesale, Distributor… |
| `businessSize` | Small, Medium, Large… |
| `personName` | Owner / contact person name |
| `source` | Where the lead came from (referral, walk-in, cold call…) |
| `contactNumber` | Phone number |
| `language` | Preferred language |
| `customerStage` | Lead stage (lead, prospect, customer…) |
| `funnelStage` | Sales funnel step |
| `gstNumber` | GST number |
| `panCard` | PAN number |
| `ownerImage` | Owner photo |
| `shopImage` | Shop photo |
| `isActive` | 1 = active lead, 0 = inactive |
| `pincode` | Pincode |
| `country` | Country |
| `state` | State |
| `district` | District |
| `city` | City |
| `area` | Area / locality |
| `address` | Full address |
| `latitude` | Location (map) |
| `longitude` | Location (map) |
| `areaId` | Marketing area this lead belongs to |
| `assignedToId` | Employee assigned to this lead |
| `createdById` | Employee who created the lead |
| `approvedById` | Admin who approved it |
| `approvedAt` | When it was approved |
| `isApproved` | 1 = approved, 0 = not approved |
| `approval_status` | pending / approved / rejected / lost |
| `verificationNotes` | Admin's note on approval |
| `rejectionNotes` | Reason for rejection |
| `lost_reason` | Why the lead was lost (price, competitor…) |
| `createdAt` | When the lead was created |
| `updatedAt` | When it was last changed |

### 8. `attendance_crm`: daily punch in / punch out
| Column | Purpose |
|---|---|
| `employee_mobile` | Employee |
| `date` | Attendance date |
| `punch_in_time` | Punch-in time |
| `punch_in_photo` | Selfie at punch-in |
| `punch_in_location` | Location at punch-in |
| `punch_out_time` | Punch-out time |
| `punch_out_photo` | Selfie at punch-out |
| `punch_out_location` | Location at punch-out |
| `last_ping_at` | Last GPS update received |
| `was_interrupted` | 1 = GPS tracking had a long gap |
| `total_distance_km` | Total distance travelled that day |
| `route_snapped` | Route matched to roads, for the map |
| `auto_closed` | 1 = the system punched out automatically (employee forgot) |
| `break_details` | Breaks taken (tea, lunch…) with times |
| `total_work_minutes` | Total working minutes |
| `total_break_minutes` | Total break minutes |
| `is_late` | 1 = came late |
| `is_early_out` | 1 = left early |
| `is_early_in` | 1 = came early |
| `late_reason` | Reason for coming late |
| `early_out_reason` | Reason for leaving early |
| `early_in_reason` | Reason for coming early |
| `status` | on_time / pending / approved / rejected / early_in |
| `admin_notes` | Senior's note when approving or rejecting |
| `approved_by` | Who approved it |
| `approved_at` | When it was approved |

### 9. `location_pings_crm`: GPS points while an employee is on duty
| Column | Purpose |
|---|---|
| `employee_mobile` | Employee |
| `date` | Date |
| `lat` / `lng` | GPS location |
| `accuracy` | GPS accuracy in metres |
| `speed` | Speed |
| `heading` | Direction of travel |
| `battery` | Phone battery % |
| `is_mock` | 1 = fake GPS detected |
| `recorded_at` | Time of this point |

### 10. `beat_plan_crm`: the salesman's visit schedule
| Column | Purpose |
|---|---|
| `account_id` | Shop (lead or customer) to visit |
| `account_type` | lead / customer |
| `salesman_id` | Salesman's mobile |
| `frequency` | weekly / monthly / every N days / specific dates / appointment |
| `days` | Weekdays for weekly visits (Mon, Fri…) |
| `week_anchor_date` | Start week for alternate-week visits |
| `month_date` | Day of the month for monthly visits |
| `specific_dates` | List of fixed visit dates |
| `appointment_date` | Appointment date and time |
| `interval_days` | N, for "every N days" |
| `start_date` | Start date for "every N days" |
| `is_active` | 1 = active, 0 = removed |

### 11. `beat_plan_followup_crm`: follow-ups (revisits / callbacks)
| Column | Purpose |
|---|---|
| `account_id` | Shop to follow up |
| `account_type` | lead / customer |
| `staff_id` | Employee who must follow up |
| `due_date` | Follow-up date |
| `note` | Note about the follow-up |
| `source_action_log_id` | The visit or call that created this follow-up |
| `done` | 1 = completed |
| `done_at` | When it was completed |

### 12. `action_log_stage_crm`: visit outcome options
| Column | Purpose |
|---|---|
| `slug` | Short code (placed_order, shop_closed…) |
| `name` | Name shown in the app |
| `sort_order` | Order in the list |
| `is_active` | 1 = show it, 0 = hide it |

### 13. `action_log_crm`: every visit check-out and call result
| Column | Purpose |
|---|---|
| `employee_mobile` | Employee |
| `role` | salesman / telecaller |
| `account_id` | Shop |
| `account_type` | lead / customer |
| `beat_plan_id` | Beat plan this visit belongs to |
| `check_in_at` | Check-in time |
| `check_in_lat` / `check_in_lng` | Check-in location |
| `check_out_at` | Check-out time |
| `check_out_lat` / `check_out_lng` | Check-out location |
| `duration_seconds` | Time spent at the shop |
| `outcome_slug` | Visit outcome code |
| `outcome_name` | Visit outcome name |
| `order_no` | Order number, if an order was placed |
| `status` | visited / missed / skipped |
| `call_outcome` | Call result (answered, busy, no answer…) |
| `call_status` | Extra call status |
| `is_invalid_call` | 1 = invalid call |
| `call_log_id` | Linked call record |
| `conversation_notes` | What was discussed on the call |
| `discussion_points` | Key points |
| `customer_stage` | Lead stage after the call |
| `funnel_stage` | Funnel step after the call |
| `payment_collected` | Money collected |
| `payment_mode` | Cash / UPI / cheque… |
| `market_note` | Market information (competitors, demand…) |
| `follow_up_date` | Next follow-up date |
| `follow_up_note` | Follow-up note |
| `general_notes` | General notes |
| `notes_related_to` | Note topic (order, stock, complaint…) |
| `images` | Photos taken during the visit |

### 14. `call_log_crm`: every telecaller call
| Column | Purpose |
|---|---|
| `employee_mobile` | Telecaller |
| `source` | manual / knowlarity (cloud call) |
| `direction` | outbound / inbound |
| `knowlarity_call_id` | Call ID from Knowlarity |
| `duration_seconds` | Call length |
| `recording_url` | Call recording link |
| `raw_payload` | Full call data from Knowlarity |
| `account_id` | Shop called |
| `account_type` | lead / customer / unknown |
| `call_outcome` | answered / busy / no_answer / switch_off / invalid / callback / pending / complaint |
| `notes` | Call notes |
| `follow_up_date` | Callback date |
| `callback_done` | 1 = callback completed |
| `called_at` | Call time |

### 15. `call_scripts_crm`: talking points for telecallers
| Column | Purpose |
|---|---|
| `employee_mobile` | Telecaller who owns the script |
| `title` | Script title |
| `stage_label` | Call stage (Opening, Pitch, Closing…) |
| `lines` | The script lines |
| `sort_order` | Order |

### 16. `telecaller_label_crm`: manual tags on a shop
| Column | Purpose |
|---|---|
| `employee_mobile` | Telecaller |
| `account_id` | Shop |
| `account_type` | lead / customer |
| `label` | Tag (do_not_call, wrong_number…) |

### 17. `complaint_crm`: customer complaints
| Column | Purpose |
|---|---|
| `account_id` | Shop that complained |
| `account_type` | lead / customer |
| `source_channel` | Came from a telecaller call or a salesman visit |
| `raised_by` | Employee who logged it |
| `assigned_to` | Employee handling it |
| `assigned_by` | Who assigned it |
| `assigned_at` | When it was assigned |
| `call_log_id` | Linked call |
| `beat_plan_id` | Linked visit |
| `category` | Complaint type |
| `description` | Complaint details |
| `status` | open / in_progress / resolved / closed |
| `resolution_notes` | How it was solved |
| `resolved_by` | Who solved it |
| `resolved_at` | When it was solved |

### 18. `target_crm`: monthly telecaller targets
| Column | Purpose |
|---|---|
| `telecaller_id` | Telecaller's mobile |
| `period` | Month (e.g. 2026-10) |
| `call_target` | Number of calls to make |
| `conversion_target` | Number of customers to convert |

### 19. `pincode_geo_crm`: map location of each pincode
| Column | Purpose |
|---|---|
| `pincode` | Pincode |
| `lat` / `lng` | Location of the pincode |
| `source` | geocoded (found automatically) / manual (set by admin) |

### 20. `tc_allocation_plan_crm`: telecaller's calling plan
| Column | Purpose |
|---|---|
| `employee_mobile` | Telecaller |
| `selected_pincodes` | Pincodes chosen for the plan |
| `pincode_sequence` | Order in which the pincodes will be called |
| `daily_capacity` | Customers per day |
| `start_date` | Plan start date |
| `end_date` | Plan end date |
| `status` | active / completed / cancelled |

### 21. `tc_allocation_item_crm`: each customer inside a calling plan
| Column | Purpose |
|---|---|
| `plan_id` | Which plan |
| `employee_mobile` | Telecaller |
| `account_id` | Shop to call |
| `account_type` | lead / customer |
| `pincode` | Shop's pincode |
| `pincode_rank` | Pincode's position in the plan |
| `account_rank` | Shop's position inside the pincode |
| `status` | pending / assigned / completed / skipped / callback |
| `allocated_date` | Day this shop should be called |
| `call_log_id` | The call made |
| `completed_at` | When it was done |

---

## PART 1B: Keeping the CRM tables consistent

**Staff IDs.** Every column that stores a staff member is the staff member's **mobile number as `varchar(20)`**, the same as `deli_staff.mobile`. The columns are:
- `employee_mobile`, `salesman_id`, `staff_id`
- `raised_by`, `assigned_to`, `assigned_by`, `resolved_by`
- `telecaller_id`
- `assignedToId`, `createdById`, `approvedById`
- `area_assign_crm.employee_id`, `incharge_assign_crm.head_incharge_id`

**Extra indexes for the most common lookups:**

| Table | Index on | Used for |
|---|---|---|
| `LeadsAccount_crm` | `contactNumber` | Duplicate-number check, matching incoming calls |
| `LeadsAccount_crm` | `createdById` | "My leads" list |
| `LeadsAccount_crm` | `approval_status` | Pending-approval list |
| `call_log_crm` | `employee_mobile`, `called_at` | Telecaller dashboard and call history |
| `action_log_crm` | `employee_mobile`, `check_out_at` | Today's visits and reports |

On a new database the tables are created this way in Part 1, so Part 1B changes nothing. On a database where the CRM tables already existed (dev or test), Part 1B converts the old column types and adds any missing index. It keeps the data and makes each change only once.

**Derived columns.** The server sets them; nobody types them in:
- `LeadsAccount_crm.isApproved` always follows `approval_status` (true only when approved).
- `action_log_crm.outcome_name` is always copied from the chosen outcome in `action_log_stage_crm`.

---

## PART 2: New columns on existing tables

### `deli_staff` (staff table)
| Column | Purpose |
|---|---|
| `pincode` | Employee's pincode |
| `city` | Employee's city |
| `language` | Employee's language |
| `punch_in_time` | Shift start time (default 09:00) |
| `punch_out_time` | Shift end time (default 18:00) |
| `grace_minutes` | Late allowance in minutes (default 15) |
| `approval_required` | 1 = late or early punches need senior approval |

### `user` (customer table)
| Column | Purpose |
|---|---|
| `lead_account_id` | The lead this customer came from (filled when a lead is approved) |

### `cart` (cart table)
| Column | Purpose |
|---|---|
| `staff_id` | Employee making the order draft |
| `account_ref` | Shop the draft is for |
| `account_type` | lead / customer |
| `draft_payload` | Saved draft order items |
| `cart_crm_draft_unique` (key) | Only one draft per employee per shop |

---

## PART 3: Master data inserted

| Table | Data | Purpose |
|---|---|---|
| `role_crm` | 9 roles | Role dropdown on the employee form |
| `action_log_stage_crm` | 8 outcomes (Placed order, Shop closed, New customer, Negotiation, Next week, Not interested, Not buying, Interested) | Choices at visit check-out |
| `language_crm` | 29 languages | Language dropdown on the employee and lead forms |

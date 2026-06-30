# Database Tables — Loagma CRM

## 1. deli_staff
Staff / employee records. Core auth table for JWT login.
- Used by: MastersController, AttendanceController, BeatPlanController
- Endpoints: `/employees`, attendance routes, beat plan routes

## 2. users
Default Laravel users table. Legacy, mostly unused.
- Used by: MastersController

## 3. area_crm
Geographic areas with pincode lists stored as JSON.
- Used by: AreaController
- Endpoints: `/areas` (CRUD)

## 4. area_assign_crm
Maps employees to their assigned areas.
- Used by: AreaAssignController, TelecallerController
- Endpoints: `/area-assign`

## 5. role_crm
Role definitions — admin, manager, salesman, telecaller, incharge, etc.
- Used by: MastersController
- Endpoints: `/masters/roles`

## 6. incharge_assign_crm
Maps head incharge to their assigned incharges (hierarchy).
- Used by: InchargeAssignController, AttendanceController
- Endpoints: `/incharge-assign`

## 7. LeadsAccount_crm
Lead and prospect accounts — business info, approval status, location.
- Used by: LeadsAccountController, BeatPlanController, TelecallerController
- Endpoints: `/lead-accounts`, `/customers`

## 8. user
Existing customer table. Legacy, minimal usage.
- Used by: LeadsAccountController, BeatPlanController
- Endpoints: `/customers`

## 9. attendance_crm
Punch-in / punch-out records with location, photos, break tracking.
- Used by: AttendanceController
- Endpoints: `/attendance/punch-in`, `/punch-out`, `/break`, `/today`, `/history`

## 10. beat_plan_crm
Salesman recurring visit schedules (weekly, monthly, specific dates).
- Used by: BeatPlanController
- Endpoints: `/beat-plan/assign`, `/my-plans`, `/today`, `/week`, `/stats`

## 11. beat_plan_visit_crm
Individual visit logs for each beat plan entry.
- Used by: BeatPlanController
- Endpoints: `/beat-plan/{id}/visit`

## 12. call_log_crm
Call logs with outcomes, notes, follow-up dates, callback tracking.
- Used by: CallLogController, TelecallerController
- Endpoints: `/call-logs`, `/telecaller/callbacks`, `/telecaller/call-history`

## 13. call_scripts_crm
Per-telecaller call scripts with talking points and stages.
- Used by: CallScriptController
- Endpoints: `/telecaller/scripts` (CRUD)

## 14. order_funnel_crm
Funnel stage definitions (Placed order, Negotiation, Not interested, etc).
- Used by: OrderFunnelController
- Endpoints: `/order-funnels`

## 15. order_funnel_response_crm
Saved funnel responses per account — visit timing, images, notes.
- Used by: OrderFunnelController
- Endpoints: `/order-funnels/response`, `/upload-image`

## 16. telecaller_label_crm
Quick labels per account set by telecaller (wrong number, do not call, etc).
- Used by: TelecallerController
- Endpoints: `/telecaller/label`

---

## Infrastructure Tables (Laravel defaults)
These are not business logic — auto-managed by Laravel.

| Table | Purpose |
|-------|---------|
| `jobs` | Background job queue |
| `job_batches` | Batch job metadata |
| `failed_jobs` | Failed job records |
| `cache` | Application cache |
| `cache_locks` | Cache lock management |

---

## Key Relationships

- `LeadsAccount_crm` is referenced by beat_plan, call_log, order_funnel_response, telecaller_label
- `deli_staff` is referenced by attendance, call_log, call_scripts, area_assign, incharge_assign
- `area_crm` is referenced by area_assign_crm
- `beat_plan_crm` is referenced by beat_plan_visit_crm

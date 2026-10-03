-- =============================================================================
-- Loagma CRM — changes to apply on the PRODUCTION database (MariaDB 10.11)
-- =============================================================================
-- Generated 2026-10-03 by diffing the dev DB (what the CRM code actually uses)
-- against updated-loagma-structure.sql (prod).
--
-- How to run: phpMyAdmin → select the prod database → SQL tab → paste → Go.
--
-- Safe to run more than once: every statement is IF NOT EXISTS / INSERT IGNORE.
-- Nothing here drops, renames or modifies an existing prod column or row.
-- Shared tables (deli_staff, user, cart) only get NEW, nullable/defaulted
-- columns, so the consumer and delivery apps are unaffected.
--
-- Do NOT run `php artisan migrate` against prod — this file replaces it.
-- =============================================================================

SET NAMES utf8mb4;
SET FOREIGN_KEY_CHECKS = 0;

-- -----------------------------------------------------------------------------
-- PART 1 — New CRM tables (21)
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS `role_crm` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `role_name` varchar(50) COLLATE utf8mb4_unicode_ci NOT NULL,
  `created_at` timestamp NULL DEFAULT NULL,
  `updated_at` timestamp NULL DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `role_crm_role_name_unique` (`role_name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `language_crm` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `name` varchar(100) COLLATE utf8mb4_unicode_ci NOT NULL,
  `code` varchar(10) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `is_active` tinyint(1) NOT NULL DEFAULT '1',
  `sort_order` int NOT NULL DEFAULT '0',
  `created_at` timestamp NULL DEFAULT NULL,
  `updated_at` timestamp NULL DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `language_crm_name_unique` (`name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `area_crm` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `area_name` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `pincodes` json DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT NULL,
  `updated_at` timestamp NULL DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `area_assign_crm` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `area_ids` json NOT NULL,
  `area_names` json NOT NULL,
  `employee_id` bigint unsigned NOT NULL,
  `created_at` timestamp NULL DEFAULT NULL,
  `updated_at` timestamp NULL DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `area_assign_crm_employee_id_unique` (`employee_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `incharge_assign_crm` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `head_incharge_id` bigint unsigned NOT NULL,
  `incharge_ids` json NOT NULL,
  `incharge_names` json NOT NULL,
  `created_at` timestamp NULL DEFAULT NULL,
  `updated_at` timestamp NULL DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `incharge_assign_crm_head_incharge_id_unique` (`head_incharge_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `customer_assign_crm` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `customer_userid` bigint unsigned NOT NULL,
  `employee_mobile` varchar(20) COLLATE utf8mb4_unicode_ci NOT NULL,
  `assigned_by` varchar(20) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT NULL,
  `updated_at` timestamp NULL DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `customer_assign_crm_employee_mobile_index` (`employee_mobile`),
  UNIQUE KEY `customer_assign_crm_customer_userid_unique` (`customer_userid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `LeadsAccount_crm` (
  `id` char(36) COLLATE utf8mb4_unicode_ci NOT NULL,
  `accountCode` varchar(191) COLLATE utf8mb4_unicode_ci NOT NULL,
  `businessName` varchar(191) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `businessType` varchar(191) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `businessSize` varchar(191) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `personName` varchar(191) COLLATE utf8mb4_unicode_ci NOT NULL,
  `source` enum('referral','campaign','walk_in','cold_call','website','other') COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `contactNumber` varchar(191) COLLATE utf8mb4_unicode_ci NOT NULL,
  `language` varchar(191) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `dateOfBirth` datetime DEFAULT NULL,
  `customerStage` varchar(191) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `funnelStage` varchar(191) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `gstNumber` varchar(191) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `panCard` varchar(191) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `ownerImage` varchar(191) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `shopImage` varchar(191) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `isActive` tinyint(1) NOT NULL DEFAULT '1',
  `pincode` varchar(191) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `country` varchar(191) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `state` varchar(191) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `district` varchar(191) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `city` varchar(191) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `area` varchar(191) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `address` varchar(191) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `latitude` double DEFAULT NULL,
  `longitude` double DEFAULT NULL,
  `areaId` bigint unsigned DEFAULT NULL,
  `assignedToId` varchar(191) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `assignedDays` json DEFAULT NULL,
  `createdById` varchar(191) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `approvedById` varchar(191) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `approvedAt` datetime DEFAULT NULL,
  `isApproved` tinyint(1) NOT NULL DEFAULT '0',
  `approval_status` varchar(20) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'pending',
  `verificationNotes` varchar(191) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `rejectionNotes` varchar(191) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `lost_reason` varchar(50) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `createdAt` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updatedAt` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `leadsaccount_crm_businesstype_index` (`businessType`),
  KEY `leadsaccount_crm_businesssize_index` (`businessSize`),
  KEY `leadsaccount_crm_customerstage_index` (`customerStage`),
  KEY `leadsaccount_crm_pincode_index` (`pincode`),
  KEY `leadsaccount_crm_isactive_index` (`isActive`),
  KEY `leadsaccount_crm_areaid_index` (`areaId`),
  KEY `leadsaccount_crm_assignedtoid_index` (`assignedToId`),
  UNIQUE KEY `leadsaccount_crm_accountcode_unique` (`accountCode`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `attendance_crm` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `employee_mobile` varchar(20) COLLATE utf8mb4_unicode_ci NOT NULL,
  `date` date NOT NULL,
  `punch_in_time` datetime DEFAULT NULL,
  `punch_in_photo` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `punch_in_location` json DEFAULT NULL,
  `punch_out_time` datetime DEFAULT NULL,
  `punch_out_photo` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `punch_out_location` json DEFAULT NULL,
  `last_ping_at` datetime DEFAULT NULL,
  `was_interrupted` tinyint(1) NOT NULL DEFAULT '0',
  `total_distance_km` double DEFAULT NULL,
  `route_snapped` json DEFAULT NULL,
  `auto_closed` tinyint(1) NOT NULL DEFAULT '0',
  `break_details` json DEFAULT NULL,
  `total_work_minutes` int DEFAULT NULL,
  `total_break_minutes` int DEFAULT NULL,
  `is_late` tinyint(1) NOT NULL DEFAULT '0',
  `is_early_out` tinyint(1) NOT NULL DEFAULT '0',
  `is_early_in` tinyint(1) NOT NULL DEFAULT '0',
  `late_reason` text COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `early_out_reason` text COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `early_in_reason` text COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `status` enum('on_time','pending','approved','rejected','early_in') COLLATE utf8mb4_unicode_ci DEFAULT 'on_time',
  `admin_notes` text COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `approved_by` varchar(20) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `approved_at` datetime DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT NULL,
  `updated_at` timestamp NULL DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `attendance_crm_employee_mobile_date_unique` (`employee_mobile`,`date`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `location_pings_crm` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `employee_mobile` varchar(20) COLLATE utf8mb4_unicode_ci NOT NULL,
  `date` date NOT NULL,
  `lat` decimal(10,7) NOT NULL,
  `lng` decimal(10,7) NOT NULL,
  `accuracy` decimal(8,2) DEFAULT NULL,
  `speed` decimal(8,2) DEFAULT NULL,
  `heading` decimal(6,2) DEFAULT NULL,
  `battery` tinyint unsigned DEFAULT NULL,
  `is_mock` tinyint(1) NOT NULL DEFAULT '0',
  `recorded_at` datetime NOT NULL,
  PRIMARY KEY (`id`),
  KEY `location_pings_crm_employee_mobile_date_index` (`employee_mobile`,`date`),
  KEY `location_pings_crm_employee_mobile_recorded_at_index` (`employee_mobile`,`recorded_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `beat_plan_crm` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `account_id` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `account_type` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'lead',
  `salesman_id` varchar(20) COLLATE utf8mb4_unicode_ci NOT NULL,
  `frequency` enum('weekly','monthly','n_days','specific_dates','appointment') COLLATE utf8mb4_unicode_ci NOT NULL,
  `days` json DEFAULT NULL,
  `week_anchor_date` date DEFAULT NULL,
  `month_date` tinyint unsigned DEFAULT NULL,
  `specific_dates` json DEFAULT NULL,
  `appointment_date` datetime DEFAULT NULL,
  `interval_days` smallint unsigned DEFAULT NULL,
  `start_date` date DEFAULT NULL,
  `is_active` tinyint(1) NOT NULL DEFAULT '1',
  `created_at` timestamp NULL DEFAULT NULL,
  `updated_at` timestamp NULL DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `beat_plan_crm_account_id_salesman_id_unique` (`account_id`,`salesman_id`),
  KEY `beat_plan_crm_salesman_id_index` (`salesman_id`),
  KEY `beat_plan_crm_is_active_index` (`is_active`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `beat_plan_followup_crm` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `account_id` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `account_type` enum('lead','customer') COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `staff_id` varchar(20) COLLATE utf8mb4_unicode_ci NOT NULL,
  `due_date` date NOT NULL,
  `note` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `source_action_log_id` bigint unsigned DEFAULT NULL,
  `done` tinyint(1) NOT NULL DEFAULT '0',
  `done_at` timestamp NULL DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT NULL,
  `updated_at` timestamp NULL DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `beat_plan_followup_crm_staff_id_index` (`staff_id`),
  KEY `beat_plan_followup_crm_due_date_index` (`due_date`),
  KEY `beat_plan_followup_crm_account_id_index` (`account_id`),
  KEY `beat_plan_followup_crm_staff_id_done_due_date_index` (`staff_id`,`done`,`due_date`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `action_log_stage_crm` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `slug` varchar(100) COLLATE utf8mb4_unicode_ci NOT NULL,
  `name` varchar(150) COLLATE utf8mb4_unicode_ci NOT NULL,
  `sort_order` int unsigned NOT NULL DEFAULT '0',
  `is_active` tinyint(1) NOT NULL DEFAULT '1',
  `created_at` timestamp NULL DEFAULT NULL,
  `updated_at` timestamp NULL DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `order_funnel_crm_slug_unique` (`slug`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `action_log_crm` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `employee_mobile` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `role` enum('salesman','telecaller') COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'salesman',
  `account_id` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `account_type` enum('lead','customer') COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `beat_plan_id` bigint unsigned DEFAULT NULL,
  `check_in_at` timestamp NULL DEFAULT NULL,
  `check_in_lat` decimal(10,7) DEFAULT NULL,
  `check_in_lng` decimal(10,7) DEFAULT NULL,
  `check_out_at` timestamp NULL DEFAULT NULL,
  `check_out_lat` decimal(10,7) DEFAULT NULL,
  `check_out_lng` decimal(10,7) DEFAULT NULL,
  `duration_seconds` int unsigned DEFAULT NULL,
  `outcome_slug` varchar(100) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `outcome_name` varchar(150) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `order_no` varchar(50) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `status` enum('visited','missed','skipped') COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'visited',
  `call_outcome` varchar(30) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `call_status` varchar(60) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `is_invalid_call` tinyint(1) NOT NULL DEFAULT '0',
  `call_log_id` bigint unsigned DEFAULT NULL,
  `conversation_notes` text COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `discussion_points` text COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `customer_stage` varchar(40) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `funnel_stage` varchar(40) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `payment_collected` decimal(12,2) DEFAULT NULL,
  `payment_mode` varchar(30) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `market_note` text COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `follow_up_date` date DEFAULT NULL,
  `follow_up_note` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `general_notes` text COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `notes_related_to` varchar(150) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `images` json DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT NULL,
  `updated_at` timestamp NULL DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `order_funnel_response_crm_employee_mobile_index` (`employee_mobile`),
  KEY `order_funnel_response_crm_account_id_index` (`account_id`),
  KEY `action_log_crm_call_log_id_index` (`call_log_id`),
  KEY `action_log_crm_account_id_created_at_index` (`account_id`,`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `call_log_crm` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `employee_mobile` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `source` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'manual',
  `direction` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `knowlarity_call_id` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `duration_seconds` int unsigned DEFAULT NULL,
  `recording_url` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `raw_payload` json DEFAULT NULL,
  `account_id` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `account_type` enum('lead','customer','unknown') COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'unknown',
  `call_outcome` enum('answered','busy','no_answer','switch_off','invalid','callback','pending','complaint') COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `notes` text COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `follow_up_date` date DEFAULT NULL,
  `callback_done` tinyint(1) NOT NULL DEFAULT '0',
  `called_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `created_at` timestamp NULL DEFAULT NULL,
  `updated_at` timestamp NULL DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `call_log_crm_employee_mobile_index` (`employee_mobile`),
  KEY `call_log_crm_account_id_index` (`account_id`),
  KEY `call_log_crm_knowlarity_call_id_index` (`knowlarity_call_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `call_scripts_crm` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `employee_mobile` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `title` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `stage_label` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `lines` json NOT NULL,
  `sort_order` int NOT NULL DEFAULT '0',
  `created_at` timestamp NULL DEFAULT NULL,
  `updated_at` timestamp NULL DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `call_scripts_crm_employee_mobile_index` (`employee_mobile`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `telecaller_label_crm` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `employee_mobile` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `account_id` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `account_type` enum('lead','customer') COLLATE utf8mb4_unicode_ci NOT NULL,
  `label` varchar(50) COLLATE utf8mb4_unicode_ci NOT NULL,
  `created_at` timestamp NULL DEFAULT NULL,
  `updated_at` timestamp NULL DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `telecaller_label_crm_employee_mobile_account_id_unique` (`employee_mobile`,`account_id`),
  KEY `telecaller_label_crm_employee_mobile_index` (`employee_mobile`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `complaint_crm` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `account_id` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `account_type` enum('lead','customer') COLLATE utf8mb4_unicode_ci NOT NULL,
  `source_channel` enum('telecaller_call','salesman_visit') COLLATE utf8mb4_unicode_ci NOT NULL,
  `raised_by` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `assigned_to` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `assigned_by` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `assigned_at` timestamp NULL DEFAULT NULL,
  `call_log_id` bigint unsigned DEFAULT NULL,
  `beat_plan_id` bigint unsigned DEFAULT NULL,
  `category` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `description` text COLLATE utf8mb4_unicode_ci NOT NULL,
  `status` enum('open','in_progress','resolved','closed') COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'open',
  `resolution_notes` text COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `resolved_by` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `resolved_at` timestamp NULL DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT NULL,
  `updated_at` timestamp NULL DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `complaint_crm_account_id_index` (`account_id`),
  KEY `complaint_crm_raised_by_index` (`raised_by`),
  KEY `complaint_crm_status_index` (`status`),
  KEY `complaint_crm_assigned_to_index` (`assigned_to`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `target_crm` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `telecaller_id` varchar(191) COLLATE utf8mb4_unicode_ci NOT NULL,
  `period` varchar(20) COLLATE utf8mb4_unicode_ci NOT NULL,
  `call_target` int unsigned NOT NULL DEFAULT '0',
  `conversion_target` int unsigned NOT NULL DEFAULT '0',
  `created_at` timestamp NULL DEFAULT NULL,
  `updated_at` timestamp NULL DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `target_crm_telecaller_id_period_unique` (`telecaller_id`,`period`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `pincode_geo_crm` (
  `pincode` varchar(10) COLLATE utf8mb4_unicode_ci NOT NULL,
  `lat` double NOT NULL,
  `lng` double NOT NULL,
  `source` varchar(10) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'derived',
  `sample_count` int unsigned NOT NULL DEFAULT '0',
  `created_at` timestamp NULL DEFAULT NULL,
  `updated_at` timestamp NULL DEFAULT NULL,
  PRIMARY KEY (`pincode`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `tc_allocation_plan_crm` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `employee_mobile` varchar(20) COLLATE utf8mb4_unicode_ci NOT NULL,
  `selected_pincodes` json NOT NULL,
  `pincode_sequence` json NOT NULL,
  `daily_capacity` int unsigned NOT NULL,
  `start_date` date DEFAULT NULL,
  `end_date` date DEFAULT NULL,
  `status` varchar(12) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'active',
  `created_at` timestamp NULL DEFAULT NULL,
  `updated_at` timestamp NULL DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `tc_allocation_plan_crm_employee_mobile_status_index` (`employee_mobile`,`status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `tc_allocation_item_crm` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `plan_id` bigint unsigned NOT NULL,
  `employee_mobile` varchar(20) COLLATE utf8mb4_unicode_ci NOT NULL,
  `account_id` varchar(64) COLLATE utf8mb4_unicode_ci NOT NULL,
  `account_type` varchar(10) COLLATE utf8mb4_unicode_ci NOT NULL,
  `pincode` varchar(10) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `pincode_rank` int unsigned NOT NULL,
  `account_rank` int unsigned NOT NULL,
  `status` varchar(12) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'pending',
  `allocated_date` date DEFAULT NULL,
  `call_log_id` bigint unsigned DEFAULT NULL,
  `completed_at` datetime DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT NULL,
  `updated_at` timestamp NULL DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `tc_allocation_item_crm_plan_id_account_id_unique` (`plan_id`,`account_id`),
  KEY `tc_alloc_item_queue_idx` (`plan_id`,`status`,`pincode_rank`,`account_rank`),
  KEY `tc_alloc_item_day_idx` (`employee_mobile`,`allocated_date`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- -----------------------------------------------------------------------------
-- PART 2 — New columns on existing shared tables
-- -----------------------------------------------------------------------------

-- deli_staff: employee profile + attendance shift settings used by the CRM.
ALTER TABLE `deli_staff`
  ADD COLUMN IF NOT EXISTS `pincode`           VARCHAR(20)  NULL DEFAULT NULL,
  ADD COLUMN IF NOT EXISTS `city`              VARCHAR(100) NULL DEFAULT NULL,
  ADD COLUMN IF NOT EXISTS `language`          VARCHAR(50)  NULL DEFAULT NULL,
  ADD COLUMN IF NOT EXISTS `punch_in_time`     TIME         NULL DEFAULT '09:00:00',
  ADD COLUMN IF NOT EXISTS `punch_out_time`    TIME         NULL DEFAULT '18:00:00',
  ADD COLUMN IF NOT EXISTS `grace_minutes`     INT          NOT NULL DEFAULT 15,
  ADD COLUMN IF NOT EXISTS `approval_required` TINYINT(1)   NOT NULL DEFAULT 1;

-- user: link from an approved lead (LeadsAccount_crm.id, a UUID) to the
-- customer row created on approval.
ALTER TABLE `user`
  ADD COLUMN IF NOT EXISTS `lead_account_id` VARCHAR(36) NULL DEFAULT NULL;

-- cart: the CRM "Create Sales Order" draft is stored as ONE row per
-- (staff, account) with ctype_id = 'crm_sales_draft' and userid = 0, so the
-- consumer app's cart queries never see it.
ALTER TABLE `cart`
  ADD COLUMN IF NOT EXISTS `staff_id`      VARCHAR(20) NULL DEFAULT NULL,
  ADD COLUMN IF NOT EXISTS `account_ref`   VARCHAR(64) NULL DEFAULT NULL,
  ADD COLUMN IF NOT EXISTS `account_type`  VARCHAR(16) NULL DEFAULT NULL,
  ADD COLUMN IF NOT EXISTS `draft_payload` LONGTEXT    NULL DEFAULT NULL;
ALTER TABLE `cart`
  ADD UNIQUE KEY IF NOT EXISTS `cart_crm_draft_unique` (`staff_id`, `account_ref`, `account_type`);


-- -----------------------------------------------------------------------------
-- PART 3 — Required master rows (the app does not work without these)
--   role_crm             → employee role dropdown
--   action_log_stage_crm → salesman check-out outcomes (validated server-side)
--   language_crm         → language dropdown on employee / lead forms
-- -----------------------------------------------------------------------------

-- role_crm
INSERT IGNORE INTO `role_crm` (`role_name`, `created_at`, `updated_at`) VALUES
  ('admin', NOW(), NOW()),
  ('area_incharge', NOW(), NOW()),
  ('head_incharge', NOW(), NOW()),
  ('incharge', NOW(), NOW()),
  ('manager', NOW(), NOW()),
  ('salesman', NOW(), NOW()),
  ('teleadmin', NOW(), NOW()),
  ('telecaller', NOW(), NOW()),
  ('zonal_incharge', NOW(), NOW());

-- action_log_stage_crm (salesman check-out validates `exists:action_log_stage_crm,slug`)
INSERT IGNORE INTO `action_log_stage_crm` (`slug`, `name`, `sort_order`, `is_active`, `created_at`, `updated_at`) VALUES
  ('placed_order', 'Placed order', 1, 1, NOW(), NOW()),
  ('shop_closed', 'Shop closed', 2, 1, NOW(), NOW()),
  ('new_customer', 'New customer', 3, 1, NOW(), NOW()),
  ('negotiation', 'Negotiation', 4, 1, NOW(), NOW()),
  ('next_week', 'Next week', 5, 1, NOW(), NOW()),
  ('not_interested', 'Not interested', 6, 1, NOW(), NOW()),
  ('not_buying', 'Not buying', 7, 1, NOW(), NOW()),
  ('interested', 'Interested', 8, 1, NOW(), NOW());

-- language_crm
INSERT IGNORE INTO `language_crm` (`name`, `code`, `is_active`, `sort_order`, `created_at`, `updated_at`) VALUES
  ('English', 'en', 1, 0, NOW(), NOW()),
  ('Hindi', 'hi', 1, 1, NOW(), NOW()),
  ('Bengali', 'bn', 1, 2, NOW(), NOW()),
  ('Marathi', 'mr', 1, 3, NOW(), NOW()),
  ('Telugu', 'te', 1, 4, NOW(), NOW()),
  ('Tamil', 'ta', 1, 5, NOW(), NOW()),
  ('Gujarati', 'gu', 1, 6, NOW(), NOW()),
  ('Urdu', 'ur', 1, 7, NOW(), NOW()),
  ('Kannada', 'kn', 1, 8, NOW(), NOW()),
  ('Odia', 'or', 1, 9, NOW(), NOW()),
  ('Malayalam', 'ml', 1, 10, NOW(), NOW()),
  ('Punjabi', 'pa', 1, 11, NOW(), NOW()),
  ('Assamese', 'as', 1, 12, NOW(), NOW()),
  ('Maithili', 'mai', 1, 13, NOW(), NOW()),
  ('Sanskrit', 'sa', 1, 14, NOW(), NOW()),
  ('Konkani', 'kok', 1, 15, NOW(), NOW()),
  ('Nepali', 'ne', 1, 16, NOW(), NOW()),
  ('Sindhi', 'sd', 1, 17, NOW(), NOW()),
  ('Dogri', 'doi', 1, 18, NOW(), NOW()),
  ('Manipuri', 'mni', 1, 19, NOW(), NOW()),
  ('Bodo', 'brx', 1, 20, NOW(), NOW()),
  ('Santali', 'sat', 1, 21, NOW(), NOW()),
  ('Kashmiri', 'ks', 1, 22, NOW(), NOW()),
  ('Bhojpuri', 'bho', 1, 23, NOW(), NOW()),
  ('Rajasthani', NULL, 1, 24, NOW(), NOW()),
  ('Chhattisgarhi', NULL, 1, 25, NOW(), NOW()),
  ('Haryanvi', NULL, 1, 26, NOW(), NOW()),
  ('Tulu', 'tcy', 1, 27, NOW(), NOW()),
  ('Other', NULL, 1, 99, NOW(), NOW());

SET FOREIGN_KEY_CHECKS = 1;

-- =============================================================================
-- End of changes.sql
-- =============================================================================

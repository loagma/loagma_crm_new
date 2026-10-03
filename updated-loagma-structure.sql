-- phpMyAdmin SQL Dump
-- version 5.2.3
-- https://www.phpmyadmin.net/
--
-- Host: localhost:3306
-- Generation Time: Oct 03, 2026 at 06:36 AM
-- Server version: 10.11.19-MariaDB-cll-lve
-- PHP Version: 8.4.25

SET SQL_MODE = "NO_AUTO_VALUE_ON_ZERO";
START TRANSACTION;
SET time_zone = "+00:00";


/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8mb4 */;

--
-- Database: `loagma_new`
--

-- --------------------------------------------------------

--
-- Table structure for table `admin`
--

CREATE TABLE `admin` (
  `userid` int(11) UNSIGNED NOT NULL,
  `session_id` varchar(250) DEFAULT '',
  `username` varchar(250) NOT NULL,
  `name` text NOT NULL,
  `password` varchar(60) NOT NULL,
  `type` varchar(250) NOT NULL DEFAULT '',
  `register_date` int(10) UNSIGNED NOT NULL DEFAULT 0,
  `last_activity` int(10) UNSIGNED NOT NULL DEFAULT 0,
  `data` text DEFAULT NULL,
  `delivery_manage_by` varchar(255) NOT NULL DEFAULT 'SuperAdmin',
  `org_name` varchar(255) DEFAULT NULL,
  `org_email` varchar(255) DEFAULT NULL,
  `org_contact_no` varchar(255) DEFAULT NULL,
  `org_gst` varchar(255) DEFAULT NULL,
  `org_address` text NOT NULL,
  `category_id` text DEFAULT NULL,
  `city_id` varchar(255) DEFAULT NULL,
  `areas` text DEFAULT NULL,
  `web_token` text DEFAULT NULL,
  `commission` int(11) DEFAULT NULL,
  `fssai_no` varchar(255) DEFAULT NULL,
  `gst_no` varchar(255) DEFAULT NULL,
  `licence_1` varchar(255) DEFAULT NULL,
  `licence_2` varchar(255) DEFAULT NULL,
  `bank_name` varchar(255) DEFAULT NULL,
  `bank_branch` varchar(255) DEFAULT NULL,
  `account_number` varchar(255) DEFAULT NULL,
  `ifsc_code` varchar(255) DEFAULT NULL,
  `account_type` varchar(100) DEFAULT NULL,
  `scanner_qr` varchar(255) DEFAULT NULL,
  `phonepe_no` varchar(255) DEFAULT NULL,
  `gpay_no` varchar(255) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=latin1 COLLATE=latin1_swedish_ci;

-- --------------------------------------------------------

--
-- Table structure for table `api_tokens`
--

CREATE TABLE `api_tokens` (
  `id` bigint(20) UNSIGNED NOT NULL,
  `token_hash` varchar(64) NOT NULL,
  `user_id` varchar(191) NOT NULL,
  `user_type` varchar(50) NOT NULL DEFAULT 'deli_staff',
  `mobile` varchar(30) DEFAULT NULL,
  `expires_at` timestamp NULL DEFAULT NULL,
  `last_used_at` timestamp NULL DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT NULL,
  `updated_at` timestamp NULL DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Table structure for table `app_settings`
--

CREATE TABLE `app_settings` (
  `admin_id` bigint(20) UNSIGNED NOT NULL,
  `setting_key` varchar(100) NOT NULL,
  `setting_value` text DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT NULL,
  `updated_at` timestamp NULL DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=latin1 COLLATE=latin1_swedish_ci;

-- --------------------------------------------------------

--
-- Table structure for table `bill_adjustments`
--

CREATE TABLE `bill_adjustments` (
  `id` bigint(20) UNSIGNED NOT NULL,
  `voucher_detail_id` bigint(20) UNSIGNED NOT NULL,
  `invoice_type` varchar(20) NOT NULL COMMENT 'SALES | PURCHASE | SALES_RETURN | PURCHASE_RETURN',
  `invoice_id` bigint(20) UNSIGNED NOT NULL COMMENT 'orders.order_id | purchase_vouchers.id',
  `adjustment_type` varchar(15) NOT NULL COMMENT 'AGAINST_REF | ON_ACCOUNT',
  `adjusted_amount` decimal(14,2) NOT NULL,
  `discount_amount` decimal(14,2) NOT NULL DEFAULT 0.00
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------

--
-- Table structure for table `brand`
--

CREATE TABLE `brand` (
  `brand_id` int(10) UNSIGNED NOT NULL,
  `name` text NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=latin1 COLLATE=latin1_swedish_ci;

-- --------------------------------------------------------

--
-- Table structure for table `BusinessType`
--

CREATE TABLE `BusinessType` (
  `id` varchar(10) NOT NULL,
  `name` varchar(100) NOT NULL,
  `createdAt` timestamp(3) NOT NULL DEFAULT current_timestamp(3)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;

-- --------------------------------------------------------

--
-- Table structure for table `calling_staff`
--

CREATE TABLE `calling_staff` (
  `id` int(11) NOT NULL,
  `name` varchar(20) NOT NULL,
  `contact_no` varchar(11) NOT NULL,
  `type` varchar(30) NOT NULL COMMENT 'tele-marketer, converter, Cold caller, etc'
) ENGINE=InnoDB DEFAULT CHARSET=latin1 COLLATE=latin1_swedish_ci;

-- --------------------------------------------------------

--
-- Table structure for table `cart`
--

CREATE TABLE `cart` (
  `cart_id` int(11) NOT NULL,
  `userid` bigint(20) NOT NULL,
  `addressId` int(15) NOT NULL,
  `product_id` bigint(20) NOT NULL,
  `vendor_product_id` int(11) NOT NULL DEFAULT 0,
  `pack_id` varchar(255) NOT NULL,
  `quantity` smallint(5) UNSIGNED NOT NULL DEFAULT 0,
  `total` decimal(10,2) NOT NULL DEFAULT 0.00,
  `ctype_id` varchar(250) NOT NULL DEFAULT 'vegetables_fruits',
  `created_at` timestamp NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=latin1 COLLATE=latin1_swedish_ci;

-- --------------------------------------------------------

--
-- Table structure for table `cart_type`
--

CREATE TABLE `cart_type` (
  `cart_tid` bigint(20) UNSIGNED NOT NULL,
  `type_name` text NOT NULL,
  `ctype_id` text NOT NULL,
  `is_used` tinyint(3) UNSIGNED NOT NULL DEFAULT 0,
  `has_express` tinyint(3) UNSIGNED NOT NULL DEFAULT 0,
  `express_charge` decimal(10,2) UNSIGNED NOT NULL DEFAULT 0.00,
  `min_total` decimal(10,2) UNSIGNED NOT NULL DEFAULT 0.00,
  `delivery_charge` decimal(10,2) UNSIGNED NOT NULL DEFAULT 0.00,
  `note` text NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=latin1 COLLATE=latin1_swedish_ci;

-- --------------------------------------------------------

--
-- Table structure for table `categories`
--

CREATE TABLE `categories` (
  `cat_id` bigint(5) UNSIGNED NOT NULL,
  `name` varchar(250) NOT NULL,
  `parent_cat_id` int(10) UNSIGNED NOT NULL,
  `is_active` tinyint(3) UNSIGNED NOT NULL DEFAULT 0,
  `type` tinyint(4) NOT NULL DEFAULT 0 COMMENT '0:Has_subcategories, 1: Has_products',
  `image_slug` varchar(15) DEFAULT ' ',
  `image_name` text DEFAULT NULL,
  `img_last_updated` int(10) UNSIGNED NOT NULL DEFAULT 0,
  `sort_order` int(11) NOT NULL DEFAULT 0,
  `⁠ is_locked ⁠` tinyint(1) NOT NULL DEFAULT 0,
  `is_locked` tinyint(1) NOT NULL DEFAULT 0
) ENGINE=InnoDB DEFAULT CHARSET=latin1 COLLATE=latin1_swedish_ci;

-- --------------------------------------------------------

--
-- Table structure for table `collection`
--

CREATE TABLE `collection` (
  `col_id` bigint(20) UNSIGNED NOT NULL,
  `day_id` varchar(15) NOT NULL DEFAULT '01-01-2017',
  `amount` decimal(10,2) NOT NULL DEFAULT 0.00,
  `comment` text NOT NULL,
  `post_date` int(10) UNSIGNED NOT NULL DEFAULT 0
) ENGINE=InnoDB DEFAULT CHARSET=latin1 COLLATE=latin1_swedish_ci;

-- --------------------------------------------------------

--
-- Table structure for table `daily_book_stock`
--

CREATE TABLE `daily_book_stock` (
  `id` int(11) NOT NULL,
  `vendor_product_id` int(11) NOT NULL,
  `date` date NOT NULL,
  `closing_stock` decimal(10,2) NOT NULL DEFAULT 0.00,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=latin1 COLLATE=latin1_swedish_ci;

-- --------------------------------------------------------

--
-- Table structure for table `delete_script`
--

CREATE TABLE `delete_script` (
  `delete_sno` bigint(20) UNSIGNED NOT NULL,
  `batch_uuid` char(36) NOT NULL,
  `voucher_name` varchar(64) NOT NULL COMMENT 'snake_case source table name, e.g. purchase_order_items',
  `source_pk` bigint(20) UNSIGNED NOT NULL COMMENT 'the deleted row''s own primary key value in its source table',
  `source_app` varchar(20) NOT NULL DEFAULT 'PMS' COMMENT 'which app performed the mutation; always PMS from this codebase',
  `delete_json` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_bin NOT NULL COMMENT 'full column values immediately before delete' CHECK (json_valid(`delete_json`)),
  `user_id` int(10) UNSIGNED DEFAULT NULL COMMENT 'acting user id; NULL for console/no-auth context',
  `timestamp` timestamp NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Table structure for table `deli_staff`
--

CREATE TABLE `deli_staff` (
  `deli_id` int(11) UNSIGNED NOT NULL,
  `admin_id` int(11) UNSIGNED NOT NULL DEFAULT 0,
  `role` varchar(20) NOT NULL DEFAULT 'driver',
  `permissions` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL CHECK (json_valid(`permissions`)),
  `name` text NOT NULL,
  `mobile` varchar(20) NOT NULL,
  `password` varchar(250) DEFAULT NULL,
  `sess_id` varchar(250) DEFAULT NULL,
  `lat` double(10,8) DEFAULT NULL,
  `lng` double(11,8) DEFAULT NULL,
  `location_last_updated` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  `is_locked` tinyint(3) UNSIGNED NOT NULL DEFAULT 0,
  `state` varchar(191) DEFAULT NULL,
  `is_record_locked` tinyint(1) NOT NULL DEFAULT 0
) ENGINE=InnoDB DEFAULT CHARSET=latin1 COLLATE=latin1_swedish_ci;

-- --------------------------------------------------------

--
-- Table structure for table `department_crm`
--

CREATE TABLE `department_crm` (
  `id` varchar(191) NOT NULL,
  `name` varchar(191) NOT NULL,
  `createdAt` datetime(3) NOT NULL DEFAULT current_timestamp(3)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------

--
-- Table structure for table `driver_accountability_log`
--

CREATE TABLE `driver_accountability_log` (
  `id` int(11) NOT NULL,
  `driver_deli_id` int(11) NOT NULL COMMENT 'References deli_staff.deli_id (the driver being held accountable)',
  `trip_id` int(11) NOT NULL,
  `audit_log_id` int(11) NOT NULL,
  `item_id` int(11) NOT NULL,
  `vendor_product_id` int(11) NOT NULL,
  `product_id` int(11) NOT NULL,
  `loss_type` enum('theft','lost','damaged','unreturned','other') NOT NULL,
  `quantity_lost` decimal(10,2) NOT NULL,
  `unit_type` varchar(20) DEFAULT NULL,
  `monetary_value` decimal(10,2) NOT NULL,
  `penalty_status` enum('pending','applied','waived','disputed') DEFAULT 'pending',
  `penalty_applied_at` datetime DEFAULT NULL,
  `penalty_applied_by` int(11) DEFAULT NULL,
  `loss_notes` text DEFAULT NULL,
  `resolution_notes` text DEFAULT NULL,
  `created_at` datetime DEFAULT current_timestamp(),
  `updated_at` datetime DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------

--
-- Table structure for table `driver_rating`
--

CREATE TABLE `driver_rating` (
  `rating_id` int(11) NOT NULL,
  `order_id` bigint(20) NOT NULL,
  `user_id` bigint(20) DEFAULT NULL,
  `rating` int(1) NOT NULL CHECK (`rating` >= 1 and `rating` <= 5),
  `review_text` text DEFAULT NULL,
  `review_type` enum('delivered','cancelled') NOT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=latin1 COLLATE=latin1_swedish_ci;

-- --------------------------------------------------------

--
-- Stand-in structure for view `eligible_delivery_addresses`
-- (See below for the actual view)
--
CREATE TABLE `eligible_delivery_addresses` (
`id` int(11)
,`user_id` int(11)
,`full_name` varchar(255)
,`full_address` varchar(255)
,`phone_no` varchar(255)
,`name` varchar(255)
,`address` varchar(255)
,`pincode` varchar(10)
,`lat` double(10,8)
,`lng` double(11,8)
,`type` enum('Home','Office')
,`city_id` varchar(255)
,`area_id` varchar(255)
,`is_default` enum('0','1')
,`created_at` datetime
);

-- --------------------------------------------------------

--
-- Table structure for table `email_verification`
--

CREATE TABLE `email_verification` (
  `userid` bigint(15) UNSIGNED NOT NULL,
  `hash` varchar(250) NOT NULL,
  `hash_time` int(10) UNSIGNED NOT NULL DEFAULT 0
) ENGINE=InnoDB DEFAULT CHARSET=latin1 COLLATE=latin1_swedish_ci;

-- --------------------------------------------------------

--
-- Table structure for table `enquiry`
--

CREATE TABLE `enquiry` (
  `id` bigint(20) UNSIGNED NOT NULL,
  `name` text NOT NULL,
  `subject` text NOT NULL,
  `contactno` text NOT NULL,
  `message` text NOT NULL,
  `post_date` int(10) UNSIGNED NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=latin1 COLLATE=latin1_swedish_ci;

-- --------------------------------------------------------

--
-- Table structure for table `expense`
--

CREATE TABLE `expense` (
  `ex_id` bigint(20) UNSIGNED NOT NULL,
  `day_id` varchar(15) NOT NULL DEFAULT '01-01-2017',
  `type` text NOT NULL,
  `amount` decimal(10,2) NOT NULL DEFAULT 0.00,
  `comment` text NOT NULL,
  `post_date` int(10) UNSIGNED NOT NULL DEFAULT 0,
  `etype_id` int(10) UNSIGNED NOT NULL DEFAULT 0
) ENGINE=InnoDB DEFAULT CHARSET=latin1 COLLATE=latin1_swedish_ci;

-- --------------------------------------------------------

--
-- Table structure for table `expense_type`
--

CREATE TABLE `expense_type` (
  `id` int(10) UNSIGNED NOT NULL,
  `name` text NOT NULL,
  `is_locked` tinyint(3) UNSIGNED NOT NULL DEFAULT 0
) ENGINE=InnoDB DEFAULT CHARSET=latin1 COLLATE=latin1_swedish_ci;

-- --------------------------------------------------------

--
-- Table structure for table `favorites`
--

CREATE TABLE `favorites` (
  `userid` bigint(20) UNSIGNED NOT NULL,
  `product_id` bigint(20) UNSIGNED NOT NULL,
  `last_updated` int(10) UNSIGNED NOT NULL DEFAULT 0
) ENGINE=InnoDB DEFAULT CHARSET=latin1 COLLATE=latin1_swedish_ci;

-- --------------------------------------------------------

--
-- Table structure for table `general_account`
--

CREATE TABLE `general_account` (
  `id` bigint(20) UNSIGNED NOT NULL,
  `account_no` varchar(100) NOT NULL,
  `account_name` varchar(255) NOT NULL,
  `account_type` varchar(100) NOT NULL COMMENT 'free text, e.g. Cash / Bank / any other category the UI uses',
  `created_at` timestamp NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------

--
-- Table structure for table `guests`
--

CREATE TABLE `guests` (
  `guest_id` bigint(20) UNSIGNED NOT NULL,
  `push_notif_id` text NOT NULL,
  `user_data` text NOT NULL,
  `last_activity` mediumint(8) UNSIGNED NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=latin1 COLLATE=latin1_swedish_ci;

-- --------------------------------------------------------

--
-- Table structure for table `hsn_codes`
--

CREATE TABLE `hsn_codes` (
  `id` bigint(20) UNSIGNED NOT NULL,
  `hsn_code` varchar(50) NOT NULL,
  `is_active` tinyint(1) NOT NULL DEFAULT 1,
  `created_at` timestamp NULL DEFAULT NULL,
  `updated_at` timestamp NULL DEFAULT NULL,
  `is_locked` tinyint(1) NOT NULL DEFAULT 0
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Table structure for table `inventory_op`
--

CREATE TABLE `inventory_op` (
  `op_id` int(10) UNSIGNED NOT NULL,
  `product_id` int(10) UNSIGNED NOT NULL DEFAULT 0,
  `op_type` varchar(255) NOT NULL DEFAULT 'inbound' COMMENT 'purchase, sale, damage, expire, free',
  `quantity` decimal(10,2) NOT NULL DEFAULT 0.00,
  `unit_type` text DEFAULT NULL,
  `unitquantity` decimal(10,2) NOT NULL DEFAULT 0.00,
  `amount` decimal(10,2) NOT NULL DEFAULT 0.00,
  `op_date` date NOT NULL,
  `note` text NOT NULL,
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  `created_at` timestamp NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_unicode_ci;

-- --------------------------------------------------------

--
-- Table structure for table `lead`
--

CREATE TABLE `lead` (
  `lead_id` int(10) NOT NULL,
  `contact_no` varchar(10) NOT NULL,
  `info` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_bin NOT NULL CHECK (json_valid(`info`)),
  `caller_id` int(10) DEFAULT NULL,
  `status` varchar(20) NOT NULL DEFAULT 'did_not_call',
  `type` varchar(20) DEFAULT NULL,
  `area` varchar(30) DEFAULT NULL,
  `purchase_power` varchar(30) DEFAULT NULL,
  `language` varchar(15) DEFAULT NULL,
  `qualification` varchar(25) DEFAULT NULL,
  `funnel_status` varchar(30) DEFAULT NULL,
  `comments` text DEFAULT NULL,
  `last_updated` varchar(25) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=latin1 COLLATE=latin1_swedish_ci;

-- --------------------------------------------------------

--
-- Table structure for table `ledger_entries`
--

CREATE TABLE `ledger_entries` (
  `id` bigint(20) UNSIGNED NOT NULL,
  `voucher_id` bigint(20) UNSIGNED NOT NULL,
  `ledger_source` varchar(10) NOT NULL COMMENT 'CUSTOMER | SUPPLIER | GENERAL',
  `ledger_id` bigint(20) UNSIGNED NOT NULL COMMENT 'polymorphic: user.userid | suppliers.id | general_account.id, per ledger_source',
  `dr_amount` decimal(14,2) NOT NULL DEFAULT 0.00,
  `cr_amount` decimal(14,2) NOT NULL DEFAULT 0.00,
  `entry_date` date NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------

--
-- Table structure for table `LoginUser_crm`
--

CREATE TABLE `LoginUser_crm` (
  `id` varchar(191) NOT NULL,
  `employeeCode` varchar(191) DEFAULT NULL,
  `name` varchar(191) DEFAULT NULL,
  `email` varchar(191) DEFAULT NULL,
  `contactNumber` varchar(191) NOT NULL,
  `alternativeNumber` varchar(191) DEFAULT NULL,
  `roleId` varchar(191) DEFAULT NULL,
  `roles` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL CHECK (json_valid(`roles`)),
  `departmentId` varchar(191) DEFAULT NULL,
  `isActive` tinyint(1) NOT NULL DEFAULT 1,
  `createdAt` datetime(3) NOT NULL DEFAULT current_timestamp(3),
  `updatedAt` datetime(3) NOT NULL,
  `workStartTime` varchar(191) DEFAULT '09:00:00',
  `workEndTime` varchar(191) DEFAULT '18:00:00',
  `latePunchInGraceMinutes` int(11) DEFAULT 45,
  `earlyPunchOutGraceMinutes` int(11) DEFAULT 30
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------

--
-- Table structure for table `master_orders`
--

CREATE TABLE `master_orders` (
  `id` int(11) NOT NULL,
  `user_id` int(11) NOT NULL,
  `txn_id` varchar(255) NOT NULL,
  `payment_status` varchar(255) NOT NULL,
  `order_count` int(11) NOT NULL,
  `payment_method` varchar(255) NOT NULL,
  `delivery_info` text NOT NULL,
  `order_total` float(10,2) NOT NULL,
  `delivery_charge` float(10,2) NOT NULL,
  `discount` float(10,2) NOT NULL,
  `before_discount` float(10,2) NOT NULL,
  `status` enum('1','0') NOT NULL,
  `created_at` datetime NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=latin1 COLLATE=latin1_swedish_ci;

-- --------------------------------------------------------

--
-- Table structure for table `migrations`
--

CREATE TABLE `migrations` (
  `id` int(10) UNSIGNED NOT NULL,
  `migration` varchar(255) NOT NULL,
  `batch` int(11) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------

--
-- Table structure for table `notes`
--

CREATE TABLE `notes` (
  `id` varchar(191) NOT NULL,
  `user_id` bigint(20) UNSIGNED NOT NULL,
  `folder_name` varchar(191) DEFAULT NULL,
  `title` varchar(255) DEFAULT NULL,
  `content` longtext DEFAULT NULL,
  `createdAt` datetime(3) NOT NULL DEFAULT current_timestamp(3),
  `updatedAt` datetime(3) NOT NULL DEFAULT current_timestamp(3) ON UPDATE current_timestamp(3)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------

--
-- Table structure for table `notifications`
--

CREATE TABLE `notifications` (
  `id` int(10) NOT NULL,
  `notif_title` varchar(75) NOT NULL,
  `notif_body` varchar(145) NOT NULL,
  `type` varchar(25) DEFAULT NULL,
  `audience` varchar(10) NOT NULL DEFAULT 'all' COMMENT 'all audience: this notif will be shown to all users.',
  `created_at` timestamp NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=latin1 COLLATE=latin1_swedish_ci;

-- --------------------------------------------------------

--
-- Table structure for table `offers`
--

CREATE TABLE `offers` (
  `off_id` bigint(20) NOT NULL,
  `name` text DEFAULT NULL,
  `off_type` varchar(250) NOT NULL DEFAULT ' ',
  `product_id` bigint(20) DEFAULT 0 COMMENT 'vendorProductId',
  `off_data` text DEFAULT NULL,
  `is_active` tinyint(4) NOT NULL DEFAULT 0
) ENGINE=InnoDB DEFAULT CHARSET=latin1 COLLATE=latin1_swedish_ci;

-- --------------------------------------------------------

--
-- Table structure for table `offer_log`
--

CREATE TABLE `offer_log` (
  `id` int(11) NOT NULL,
  `user_id` int(11) NOT NULL,
  `order_id` int(11) NOT NULL,
  `offer_id` int(11) NOT NULL,
  `used_date` date NOT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=latin1 COLLATE=latin1_swedish_ci;

-- --------------------------------------------------------

--
-- Table structure for table `orders`
--

CREATE TABLE `orders` (
  `order_id` bigint(20) UNSIGNED NOT NULL,
  `bill_no` varchar(100) DEFAULT NULL,
  `bill_number` int(9) DEFAULT NULL,
  `invoice_number` int(10) UNSIGNED DEFAULT NULL,
  `charges_json` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL CHECK (json_valid(`charges_json`)),
  `invoice_pdf_url` varchar(500) DEFAULT NULL,
  `bill_dt` date DEFAULT NULL,
  `department` varchar(100) DEFAULT NULL,
  `Bill_Narration` text DEFAULT NULL,
  `expected_date` date DEFAULT NULL,
  `bill_roff` decimal(10,2) NOT NULL DEFAULT 0.00,
  `doc_year` varchar(20) DEFAULT NULL,
  `sales_return_voucher_no` varchar(100) DEFAULT NULL,
  `sales_return_dt` date DEFAULT NULL,
  `sales_return_status` varchar(20) DEFAULT NULL,
  `sales_return_attachment_path` varchar(255) DEFAULT NULL,
  `sales_return_reason` text DEFAULT NULL,
  `sales_return_charges_json` text DEFAULT NULL,
  `idempotency_key` varchar(64) DEFAULT NULL,
  `salesman_id` varchar(191) DEFAULT NULL,
  `master_order_id` int(11) NOT NULL DEFAULT 0,
  `txn_id` varchar(250) NOT NULL,
  `buyer_userid` bigint(20) UNSIGNED NOT NULL,
  `start_time` int(10) UNSIGNED NOT NULL DEFAULT 0,
  `last_update_time` int(10) UNSIGNED NOT NULL DEFAULT 0,
  `short_datetime` text NOT NULL,
  `order_state` varchar(250) NOT NULL,
  `payment_method` varchar(250) NOT NULL DEFAULT 'cod',
  `ctype_id` varchar(250) NOT NULL DEFAULT 'vegetables_fruits',
  `items_count` int(10) UNSIGNED NOT NULL DEFAULT 0,
  `delivery_charge` decimal(10,0) NOT NULL DEFAULT 0,
  `order_total` decimal(12,2) UNSIGNED NOT NULL DEFAULT 0.00,
  `bill_amount` int(10) DEFAULT NULL,
  `delivery_info` text NOT NULL,
  `area_name` text DEFAULT NULL,
  `feedback` varchar(100) NOT NULL,
  `admin_id` bigint(20) UNSIGNED NOT NULL DEFAULT 0,
  `payment_status` varchar(250) NOT NULL DEFAULT 'not_paid',
  `amountReceivedInfo` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL,
  `trip_id` int(10) DEFAULT NULL,
  `discount` decimal(10,2) NOT NULL DEFAULT 0.00,
  `before_discount` decimal(10,2) NOT NULL DEFAULT 0.00,
  `time_slot` varchar(250) NOT NULL DEFAULT 'Now',
  `delivered_time` int(11) DEFAULT NULL,
  `deli_id` int(2) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=latin1 COLLATE=latin1_swedish_ci;

-- --------------------------------------------------------

--
-- Table structure for table `orders_item`
--

CREATE TABLE `orders_item` (
  `order_id` bigint(20) UNSIGNED NOT NULL DEFAULT 0,
  `item_id` bigint(20) UNSIGNED NOT NULL,
  `product_id` bigint(20) UNSIGNED NOT NULL,
  `vendor_product_id` int(11) DEFAULT NULL,
  `pinfo` text NOT NULL,
  `invoice_data` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL CHECK (json_valid(`invoice_data`)),
  `offers` text DEFAULT NULL,
  `quantity` mediumint(8) UNSIGNED NOT NULL DEFAULT 0,
  `qty_loaded` int(3) DEFAULT NULL,
  `qty_delivered` int(3) DEFAULT NULL,
  `qty_returned` int(3) DEFAULT NULL,
  `return_reason` varchar(500) DEFAULT NULL,
  `item_price` decimal(12,2) UNSIGNED NOT NULL DEFAULT 0.00,
  `item_total` decimal(12,2) UNSIGNED NOT NULL DEFAULT 0.00,
  `op_id` bigint(20) DEFAULT 0,
  `commission` double(10,2) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=latin1 COLLATE=latin1_swedish_ci;

-- --------------------------------------------------------

--
-- Table structure for table `otp`
--

CREATE TABLE `otp` (
  `contactno` varchar(30) NOT NULL,
  `slug` varchar(16) NOT NULL,
  `otp_num` varchar(10) NOT NULL,
  `otp_time` int(10) UNSIGNED NOT NULL DEFAULT 0,
  `purpose` varchar(250) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=latin1 COLLATE=latin1_swedish_ci;

-- --------------------------------------------------------

--
-- Table structure for table `package_segregation`
--

CREATE TABLE `package_segregation` (
  `id` int(10) UNSIGNED NOT NULL,
  `admin_vendor_id` int(11) NOT NULL,
  `product_id` int(11) NOT NULL,
  `pack_id` varchar(255) NOT NULL COMMENT 'vendor_products.packs[].pi',
  `pack_sg` enum('Bulk','Pack','FMCG','Default Pack') NOT NULL DEFAULT 'Default Pack',
  `created_at` datetime NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------

--
-- Table structure for table `party_advances`
--

CREATE TABLE `party_advances` (
  `id` bigint(20) UNSIGNED NOT NULL,
  `party_type` varchar(10) NOT NULL COMMENT 'CUSTOMER | SUPPLIER',
  `party_id` bigint(20) UNSIGNED NOT NULL,
  `voucher_detail_id` bigint(20) UNSIGNED NOT NULL,
  `amount` decimal(14,2) NOT NULL,
  `remaining_amount` decimal(14,2) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------

--
-- Table structure for table `physical_stock`
--

CREATE TABLE `physical_stock` (
  `id` int(11) NOT NULL,
  `vendor_product_id` int(11) NOT NULL,
  `stock` double NOT NULL,
  `last_updated_at` datetime DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  `note` text DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=latin1 COLLATE=latin1_swedish_ci;

-- --------------------------------------------------------

--
-- Table structure for table `pincodes`
--

CREATE TABLE `pincodes` (
  `area_id` varchar(250) NOT NULL DEFAULT '',
  `pincode` varchar(250) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=latin1 COLLATE=latin1_swedish_ci;

-- --------------------------------------------------------

--
-- Table structure for table `pincode_masters`
--

CREATE TABLE `pincode_masters` (
  `id` bigint(20) UNSIGNED NOT NULL,
  `pincode` varchar(10) NOT NULL,
  `city` varchar(100) NOT NULL,
  `state` varchar(100) NOT NULL,
  `country` varchar(100) NOT NULL DEFAULT 'India',
  `district` varchar(100) DEFAULT NULL,
  `region` varchar(100) DEFAULT NULL,
  `delivery_available` tinyint(1) NOT NULL DEFAULT 1,
  `delivery_charge` decimal(10,2) DEFAULT NULL,
  `is_active` tinyint(1) NOT NULL DEFAULT 1,
  `created_at` timestamp NULL DEFAULT NULL,
  `updated_at` timestamp NULL DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------

--
-- Table structure for table `product`
--

CREATE TABLE `product` (
  `product_id` bigint(20) UNSIGNED NOT NULL,
  `cat_id` int(10) UNSIGNED NOT NULL DEFAULT 0,
  `parent_cat_id` int(10) UNSIGNED NOT NULL DEFAULT 0,
  `brand` text NOT NULL,
  `ctype_id` varchar(250) NOT NULL DEFAULT 'vegetables_fruits',
  `seq_no` int(10) UNSIGNED DEFAULT 0,
  `order_limit` int(10) UNSIGNED NOT NULL DEFAULT 0,
  `buffer_limit` int(10) UNSIGNED NOT NULL DEFAULT 0,
  `nop` int(10) UNSIGNED NOT NULL DEFAULT 0,
  `start_date` int(10) UNSIGNED NOT NULL DEFAULT 0,
  `is_published` tinyint(3) UNSIGNED NOT NULL DEFAULT 0,
  `is_used` tinyint(4) NOT NULL DEFAULT 0,
  `is_deleted` tinyint(4) NOT NULL DEFAULT 0,
  `in_stock` tinyint(3) UNSIGNED NOT NULL DEFAULT 0,
  `inventory_type` enum('SINGLE','PACK_WISE') NOT NULL DEFAULT 'SINGLE',
  `inventory_unit_type` varchar(255) NOT NULL DEFAULT 'WEIGHT',
  `stock_uom` int(5) DEFAULT NULL COMMENT 'References units_master.unit_id.',
  `name` text NOT NULL,
  `short_name` varchar(255) DEFAULT NULL,
  `description` text NOT NULL,
  `display_photo` text DEFAULT NULL,
  `keywords` text DEFAULT NULL,
  `spec_params` text NOT NULL,
  `packs` text DEFAULT NULL,
  `default_pack_id` varchar(255) NOT NULL DEFAULT ' ',
  `hsn_code` varchar(10) NOT NULL,
  `prod_wt` decimal(12,3) NOT NULL,
  `gst_percent` decimal(5,2) NOT NULL,
  `offers` text DEFAULT NULL,
  `cache_txt` mediumtext DEFAULT NULL,
  `img_last_updated` int(10) UNSIGNED NOT NULL DEFAULT 0,
  `stock` decimal(10,3) DEFAULT NULL,
  `stock_ut_id` varchar(100) DEFAULT NULL,
  `is_taxable` tinyint(1) UNSIGNED NOT NULL DEFAULT 1,
  `exempt_from` date DEFAULT NULL,
  `exempt_to` date DEFAULT NULL,
  `⁠ is_locked ⁠` tinyint(1) NOT NULL DEFAULT 0,
  `is_locked` tinyint(1) NOT NULL DEFAULT 0
) ENGINE=InnoDB DEFAULT CHARSET=latin1 COLLATE=latin1_swedish_ci;

-- --------------------------------------------------------

--
-- Table structure for table `product_bkp`
--

CREATE TABLE `product_bkp` (
  `product_id` bigint(20) UNSIGNED NOT NULL,
  `cat_id` int(10) UNSIGNED NOT NULL DEFAULT 0,
  `parent_cat_id` int(10) UNSIGNED NOT NULL DEFAULT 0,
  `brand` text NOT NULL,
  `ctype_id` varchar(250) NOT NULL DEFAULT 'vegetables_fruits',
  `seq_no` int(10) UNSIGNED NOT NULL DEFAULT 0,
  `start_date` int(10) UNSIGNED NOT NULL DEFAULT 0,
  `is_published` tinyint(3) UNSIGNED NOT NULL DEFAULT 0,
  `is_used` tinyint(4) NOT NULL DEFAULT 0,
  `is_deleted` tinyint(4) NOT NULL DEFAULT 0,
  `in_stock` tinyint(3) UNSIGNED NOT NULL DEFAULT 0,
  `inventory_type` enum('SINGLE','PACK_WISE') NOT NULL DEFAULT 'SINGLE',
  `inventory_unit_type` varchar(255) NOT NULL DEFAULT 'WEIGHT',
  `name` text NOT NULL,
  `description` text NOT NULL,
  `display_photo` text DEFAULT NULL,
  `keywords` text DEFAULT NULL,
  `spec_params` text NOT NULL,
  `packs` text DEFAULT NULL,
  `default_pack_id` varchar(255) NOT NULL DEFAULT ' ',
  `offers` text DEFAULT NULL,
  `cache_txt` mediumtext DEFAULT NULL,
  `img_last_updated` int(10) UNSIGNED NOT NULL DEFAULT 0,
  `stock` decimal(10,3) DEFAULT NULL,
  `stock_ut_id` varchar(100) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=latin1 COLLATE=latin1_swedish_ci;

-- --------------------------------------------------------

--
-- Table structure for table `product_photos`
--

CREATE TABLE `product_photos` (
  `product_id` bigint(20) UNSIGNED NOT NULL DEFAULT 0,
  `photo_id` bigint(20) UNSIGNED NOT NULL,
  `file_location` varchar(250) NOT NULL DEFAULT '0',
  `photo_slug` varchar(10) NOT NULL DEFAULT '0000'
) ENGINE=InnoDB DEFAULT CHARSET=latin1 COLLATE=latin1_swedish_ci;

-- --------------------------------------------------------

--
-- Table structure for table `product_purchase`
--

CREATE TABLE `product_purchase` (
  `item_id` bigint(20) UNSIGNED NOT NULL,
  `day_id` varchar(20) NOT NULL DEFAULT '01-01-2018',
  `product_id` bigint(20) UNSIGNED NOT NULL DEFAULT 0,
  `quantity` decimal(10,2) UNSIGNED NOT NULL DEFAULT 0.00,
  `unit_id` text NOT NULL,
  `cost` decimal(10,2) NOT NULL DEFAULT 0.00,
  `post_date` int(10) UNSIGNED NOT NULL DEFAULT 0
) ENGINE=InnoDB DEFAULT CHARSET=latin1 COLLATE=latin1_swedish_ci;

-- --------------------------------------------------------

--
-- Table structure for table `product_taxes`
--

CREATE TABLE `product_taxes` (
  `id` bigint(20) UNSIGNED NOT NULL,
  `product_id` bigint(20) UNSIGNED NOT NULL,
  `tax_id` bigint(20) UNSIGNED NOT NULL,
  `tax_percent` decimal(5,2) NOT NULL,
  `effective_from` date DEFAULT NULL,
  `effective_to` date DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT NULL,
  `updated_at` timestamp NULL DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Table structure for table `prod_barcodes`
--

CREATE TABLE `prod_barcodes` (
  `bar_id` bigint(20) UNSIGNED NOT NULL,
  `product_id` bigint(20) UNSIGNED DEFAULT 0,
  `pack_id` varchar(250) NOT NULL,
  `barcode` varchar(250) NOT NULL DEFAULT '',
  `stock` int(11) DEFAULT 0
) ENGINE=InnoDB DEFAULT CHARSET=latin1 COLLATE=latin1_swedish_ci;

-- --------------------------------------------------------

--
-- Table structure for table `promo`
--

CREATE TABLE `promo` (
  `promo_id` bigint(20) UNSIGNED NOT NULL,
  `title` varchar(250) DEFAULT NULL,
  `description` text DEFAULT NULL,
  `ctype_id` varchar(250) NOT NULL DEFAULT 'all',
  `discount` decimal(10,3) NOT NULL DEFAULT 0.000,
  `max_use` int(10) UNSIGNED NOT NULL DEFAULT 0,
  `from` datetime(6) DEFAULT NULL,
  `to` datetime(6) DEFAULT NULL,
  `status` tinyint(4) NOT NULL DEFAULT 0,
  `promo_data` text NOT NULL DEFAULT '\'{}\'' COMMENT 'amount, percentage, percentage_up_to, ladder'
) ENGINE=InnoDB DEFAULT CHARSET=latin1 COLLATE=latin1_swedish_ci;

-- --------------------------------------------------------

--
-- Table structure for table `promo_log`
--

CREATE TABLE `promo_log` (
  `log_id` bigint(20) UNSIGNED NOT NULL,
  `order_id` bigint(20) UNSIGNED DEFAULT 0,
  `userid` bigint(20) UNSIGNED DEFAULT 0,
  `promo_id` bigint(20) UNSIGNED DEFAULT 0
) ENGINE=InnoDB DEFAULT CHARSET=latin1 COLLATE=latin1_swedish_ci;

-- --------------------------------------------------------

--
-- Table structure for table `purchase_orders`
--

CREATE TABLE `purchase_orders` (
  `id` bigint(20) UNSIGNED NOT NULL,
  `doc_no_prefix` varchar(20) NOT NULL,
  `supplier_id` bigint(20) UNSIGNED NOT NULL,
  `admin_id` bigint(20) UNSIGNED NOT NULL COMMENT 'Vendor scope: references admin.id. Set at doc creation and used by every list/show query for tenant isolation.',
  `salesman_id` varchar(191) DEFAULT NULL,
  `department_id` varchar(191) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `doc_date` date NOT NULL,
  `expected_date` date DEFAULT NULL,
  `status` enum('POSTED','DRAFT','SENT','PARTIALLY_RECEIVED','CLOSED','CANCELLED') NOT NULL DEFAULT 'DRAFT',
  `narration` text DEFAULT NULL,
  `created_by` bigint(20) UNSIGNED DEFAULT NULL,
  `updated_by` bigint(20) UNSIGNED DEFAULT NULL,
  `total_amount` decimal(14,2) NOT NULL DEFAULT 0.00,
  `charges_total` decimal(14,2) NOT NULL DEFAULT 0.00,
  `charges_json` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL CHECK (json_valid(`charges_json`)),
  `total_with_charges` decimal(14,2) NOT NULL DEFAULT 0.00,
  `created_at` timestamp NULL DEFAULT NULL,
  `updated_at` timestamp NULL DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Table structure for table `purchase_order_items`
--

CREATE TABLE `purchase_order_items` (
  `id` bigint(20) UNSIGNED NOT NULL,
  `purchase_order_id` bigint(20) UNSIGNED NOT NULL,
  `product_id` bigint(20) UNSIGNED NOT NULL,
  `vendor_product_id` bigint(20) UNSIGNED DEFAULT NULL,
  `unit` varchar(20) DEFAULT NULL,
  `quantity` decimal(12,3) NOT NULL,
  `consumed_quantity` decimal(12,3) NOT NULL DEFAULT 0.000,
  `written_off_quantity` decimal(12,3) NOT NULL DEFAULT 0.000,
  `remaining_quantity` decimal(12,3) NOT NULL DEFAULT 0.000,
  `price` decimal(12,2) NOT NULL,
  `tax_percent` decimal(5,2) DEFAULT NULL,
  `line_total` decimal(14,2) NOT NULL,
  `created_at` timestamp NULL DEFAULT NULL,
  `updated_at` timestamp NULL DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Table structure for table `purchase_returns`
--

CREATE TABLE `purchase_returns` (
  `id` bigint(20) UNSIGNED NOT NULL,
  `doc_no_prefix` varchar(20) NOT NULL DEFAULT '25-26/',
  `source_purchase_voucher_id` bigint(20) UNSIGNED DEFAULT NULL,
  `supplier_id` bigint(20) UNSIGNED NOT NULL,
  `admin_id` bigint(20) UNSIGNED NOT NULL COMMENT 'Vendor scope: references admin.id. Set at doc creation and used by every list/show query for tenant isolation.',
  `doc_date` date NOT NULL,
  `reason` text DEFAULT NULL,
  `status` enum('DRAFT','POSTED','CANCELLED') NOT NULL DEFAULT 'DRAFT',
  `items_total` decimal(14,2) NOT NULL DEFAULT 0.00,
  `charges_total` decimal(14,2) NOT NULL DEFAULT 0.00,
  `total_with_charges` decimal(14,2) NOT NULL DEFAULT 0.00,
  `charges_json` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL CHECK (json_valid(`charges_json`)),
  `created_by` bigint(20) UNSIGNED DEFAULT NULL,
  `updated_by` bigint(20) UNSIGNED DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT NULL,
  `updated_at` timestamp NULL DEFAULT NULL,
  `idempotency_key` varchar(64) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------

--
-- Table structure for table `purchase_return_items`
--

CREATE TABLE `purchase_return_items` (
  `id` bigint(20) UNSIGNED NOT NULL,
  `purchase_return_id` bigint(20) UNSIGNED NOT NULL,
  `source_purchase_voucher_item_id` bigint(20) UNSIGNED DEFAULT NULL,
  `product_id` bigint(20) UNSIGNED NOT NULL,
  `vendor_product_id` bigint(20) UNSIGNED DEFAULT NULL,
  `returned_quantity` decimal(12,3) NOT NULL DEFAULT 0.000,
  `unit_price` decimal(12,2) NOT NULL DEFAULT 0.00,
  `taxable_amount` decimal(14,2) NOT NULL DEFAULT 0.00,
  `sgst` decimal(12,2) NOT NULL DEFAULT 0.00,
  `cgst` decimal(12,2) NOT NULL DEFAULT 0.00,
  `igst` decimal(12,2) NOT NULL DEFAULT 0.00,
  `cess` decimal(12,2) NOT NULL DEFAULT 0.00,
  `roff` decimal(12,2) NOT NULL DEFAULT 0.00,
  `value` decimal(14,2) NOT NULL DEFAULT 0.00,
  `return_reason` varchar(255) DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT NULL,
  `updated_at` timestamp NULL DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------

--
-- Table structure for table `purchase_vouchers`
--

CREATE TABLE `purchase_vouchers` (
  `id` bigint(20) UNSIGNED NOT NULL,
  `doc_no_prefix` varchar(20) NOT NULL DEFAULT '25-26/',
  `supplier_id` bigint(20) UNSIGNED NOT NULL,
  `admin_id` bigint(20) UNSIGNED NOT NULL COMMENT 'Vendor scope: references admin.id. Set at doc creation and used by every list/show query for tenant isolation.',
  `purchase_order_id` bigint(20) UNSIGNED DEFAULT NULL,
  `doc_date` date NOT NULL,
  `bill_no` varchar(100) NOT NULL,
  `bill_date` date DEFAULT NULL,
  `narration` text DEFAULT NULL,
  `purchase_agent_id` varchar(100) DEFAULT NULL,
  `status` enum('DRAFT','POSTED','CANCELLED') NOT NULL DEFAULT 'DRAFT',
  `items_total` decimal(14,2) NOT NULL DEFAULT 0.00,
  `charges_total` decimal(14,2) NOT NULL DEFAULT 0.00,
  `total_with_charges` decimal(14,2) NOT NULL DEFAULT 0.00,
  `charges_json` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL CHECK (json_valid(`charges_json`)),
  `bill_attachment_path` varchar(255) DEFAULT NULL,
  `created_by` bigint(20) UNSIGNED DEFAULT NULL,
  `updated_by` bigint(20) UNSIGNED DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT NULL,
  `updated_at` timestamp NULL DEFAULT NULL,
  `idempotency_key` varchar(64) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------

--
-- Table structure for table `purchase_voucher_items`
--

CREATE TABLE `purchase_voucher_items` (
  `id` bigint(20) UNSIGNED NOT NULL,
  `purchase_voucher_id` bigint(20) UNSIGNED NOT NULL,
  `source_purchase_order_item_id` bigint(20) UNSIGNED DEFAULT NULL,
  `product_id` bigint(20) UNSIGNED NOT NULL,
  `vendor_product_id` bigint(20) UNSIGNED DEFAULT NULL,
  `unit` varchar(20) DEFAULT NULL,
  `quantity` decimal(12,3) NOT NULL DEFAULT 0.000,
  `writeoff_qty` decimal(12,3) NOT NULL DEFAULT 0.000,
  `is_writeoff` tinyint(1) NOT NULL DEFAULT 0,
  `writeoff_reason` varchar(255) DEFAULT NULL,
  `unit_price` decimal(12,2) NOT NULL DEFAULT 0.00,
  `taxable_amount` decimal(14,2) NOT NULL DEFAULT 0.00,
  `sgst` decimal(12,2) NOT NULL DEFAULT 0.00,
  `cgst` decimal(12,2) NOT NULL DEFAULT 0.00,
  `igst` decimal(12,2) NOT NULL DEFAULT 0.00,
  `cess` decimal(12,2) NOT NULL DEFAULT 0.00,
  `roff` decimal(12,2) NOT NULL DEFAULT 0.00,
  `value` decimal(14,2) NOT NULL DEFAULT 0.00,
  `created_at` timestamp NULL DEFAULT NULL,
  `updated_at` timestamp NULL DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------

--
-- Table structure for table `recommendations`
--

CREATE TABLE `recommendations` (
  `id` int(6) NOT NULL,
  `userId` int(10) NOT NULL,
  `recommendations` varchar(200) NOT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=latin1 COLLATE=latin1_swedish_ci;

-- --------------------------------------------------------

--
-- Table structure for table `search`
--

CREATE TABLE `search` (
  `s.no` int(11) NOT NULL,
  `user_id` int(10) NOT NULL,
  `search_text` varchar(200) NOT NULL,
  `count` int(5) NOT NULL COMMENT 'no. of times this searchText has been used',
  `created_at` timestamp NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Table structure for table `settings`
--

CREATE TABLE `settings` (
  `name` varchar(255) NOT NULL,
  `value` text NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=latin1 COLLATE=latin1_swedish_ci;

-- --------------------------------------------------------

--
-- Table structure for table `stock_count`
--

CREATE TABLE `stock_count` (
  `id` int(11) NOT NULL,
  `assignment_id` int(11) NOT NULL,
  `vendor_product_id` int(11) NOT NULL,
  `counted_quantity` double NOT NULL,
  `count_unit` varchar(12) NOT NULL,
  `standard_unit_quantity` decimal(10,2) DEFAULT NULL,
  `updated_at` datetime DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=latin1 COLLATE=latin1_swedish_ci;

-- --------------------------------------------------------

--
-- Table structure for table `stock_count_assignments`
--

CREATE TABLE `stock_count_assignments` (
  `id` int(11) NOT NULL,
  `master_session_id` int(11) NOT NULL,
  `counter_user_id` int(11) NOT NULL,
  `category_id` int(11) NOT NULL,
  `status` enum('assigned','in_progress','completed','paused') DEFAULT 'assigned',
  `assigned_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `started_at` timestamp NULL DEFAULT NULL,
  `completed_at` timestamp NULL DEFAULT NULL,
  `notes` text DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=latin1 COLLATE=latin1_swedish_ci;

-- --------------------------------------------------------

--
-- Table structure for table `stock_count_master_session`
--

CREATE TABLE `stock_count_master_session` (
  `id` int(11) NOT NULL,
  `supervisor_id` int(11) NOT NULL,
  `admin_id` int(11) NOT NULL COMMENT 'Vendor scope: references admin.id. Set at session creation and used by every downstream query for tenant isolation.',
  `status` enum('planning','in_progress','completed','cancelled') DEFAULT 'planning',
  `total_categories` int(11) DEFAULT 0,
  `completed_categories` int(11) DEFAULT 0,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `completed_at` timestamp NULL DEFAULT NULL,
  `notes` text DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=latin1 COLLATE=latin1_swedish_ci;

-- --------------------------------------------------------

--
-- Table structure for table `stock_notify`
--

CREATE TABLE `stock_notify` (
  `userid` bigint(20) UNSIGNED NOT NULL,
  `product_id` bigint(20) UNSIGNED NOT NULL COMMENT 'this is vendor prod id',
  `created_at` timestamp NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=latin1 COLLATE=latin1_swedish_ci;

-- --------------------------------------------------------

--
-- Table structure for table `stock_voucher`
--

CREATE TABLE `stock_voucher` (
  `id` bigint(20) UNSIGNED NOT NULL,
  `voucher_type` enum('IN','OUT') NOT NULL DEFAULT 'IN',
  `status` enum('DRAFT','POSTED') NOT NULL DEFAULT 'DRAFT',
  `voucher_date` date DEFAULT NULL,
  `remarks` text DEFAULT NULL,
  `posted_at` datetime DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT NULL,
  `updated_at` timestamp NULL DEFAULT NULL,
  `idempotency_key` varchar(64) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------

--
-- Table structure for table `stock_voucher_items`
--

CREATE TABLE `stock_voucher_items` (
  `id` bigint(20) UNSIGNED NOT NULL,
  `voucher_id` bigint(20) UNSIGNED NOT NULL,
  `product_id` bigint(20) UNSIGNED NOT NULL,
  `quantity` decimal(10,3) NOT NULL,
  `unit_type` varchar(20) NOT NULL,
  `created_at` timestamp NULL DEFAULT NULL,
  `updated_at` timestamp NULL DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------

--
-- Table structure for table `suppliers`
--

CREATE TABLE `suppliers` (
  `id` bigint(20) UNSIGNED NOT NULL,
  `admin_id` int(10) UNSIGNED DEFAULT NULL,
  `supplier_code` varchar(50) NOT NULL,
  `supplier_name` varchar(255) NOT NULL,
  `short_name` varchar(255) DEFAULT NULL,
  `business_type` varchar(100) DEFAULT NULL,
  `department` varchar(100) DEFAULT NULL,
  `gst_no` varchar(20) DEFAULT NULL,
  `pan_no` varchar(20) DEFAULT NULL,
  `tan_no` varchar(20) DEFAULT NULL,
  `cin_no` varchar(30) DEFAULT NULL,
  `vat_no` varchar(30) DEFAULT NULL,
  `registration_no` varchar(50) DEFAULT NULL,
  `fssai_no` varchar(50) DEFAULT NULL,
  `website` varchar(255) DEFAULT NULL,
  `email` varchar(255) DEFAULT NULL,
  `phone` varchar(30) DEFAULT NULL,
  `alternate_phone` varchar(30) DEFAULT NULL,
  `contact_person` varchar(255) DEFAULT NULL,
  `contact_person_email` varchar(255) DEFAULT NULL,
  `contact_person_phone` varchar(30) DEFAULT NULL,
  `contact_person_designation` varchar(100) DEFAULT NULL,
  `address_line1` varchar(255) DEFAULT NULL,
  `city` varchar(100) DEFAULT NULL,
  `state` varchar(100) DEFAULT NULL,
  `country` varchar(100) DEFAULT NULL,
  `pincode` varchar(20) DEFAULT NULL,
  `area` varchar(150) DEFAULT NULL,
  `bank_name` varchar(150) DEFAULT NULL,
  `bank_branch` varchar(150) DEFAULT NULL,
  `bank_account_name` varchar(150) DEFAULT NULL,
  `bank_account_number` varchar(50) DEFAULT NULL,
  `ifsc_code` varchar(20) DEFAULT NULL,
  `swift_code` varchar(20) DEFAULT NULL,
  `payment_terms_days` smallint(5) UNSIGNED DEFAULT NULL,
  `credit_limit` decimal(12,2) DEFAULT NULL,
  `rating` decimal(3,2) DEFAULT NULL,
  `is_preferred` tinyint(1) NOT NULL DEFAULT 0,
  `status` enum('ACTIVE','INACTIVE','SUSPENDED') NOT NULL DEFAULT 'ACTIVE',
  `notes` text DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT NULL,
  `updated_at` timestamp NULL DEFAULT NULL,
  `deleted_at` timestamp NULL DEFAULT NULL,
  `is_locked` tinyint(1) NOT NULL DEFAULT 0
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Table structure for table `supplier_products`
--

CREATE TABLE `supplier_products` (
  `id` bigint(20) UNSIGNED NOT NULL,
  `supplier_id` bigint(20) UNSIGNED NOT NULL,
  `product_id` bigint(20) UNSIGNED NOT NULL,
  `vendor_product_id` bigint(20) UNSIGNED DEFAULT NULL,
  `supplier_sku` varchar(100) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Table structure for table `taxes`
--

CREATE TABLE `taxes` (
  `id` bigint(20) UNSIGNED NOT NULL,
  `tax_category` varchar(100) NOT NULL,
  `tax_sub_category` varchar(100) NOT NULL,
  `tax_name` varchar(150) NOT NULL,
  `is_active` tinyint(1) NOT NULL DEFAULT 1,
  `created_at` timestamp NULL DEFAULT NULL,
  `updated_at` timestamp NULL DEFAULT NULL,
  `is_locked` tinyint(1) NOT NULL DEFAULT 0
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Table structure for table `time_slots`
--

CREATE TABLE `time_slots` (
  `slot_id` bigint(20) UNSIGNED NOT NULL,
  `time_slot_group_id` int(11) NOT NULL,
  `area_id` varchar(250) DEFAULT NULL,
  `start_date` int(10) UNSIGNED NOT NULL DEFAULT 1,
  `interval` int(10) UNSIGNED NOT NULL DEFAULT 1,
  `count_limit` int(10) UNSIGNED NOT NULL DEFAULT 3,
  `order_time_end` int(20) UNSIGNED DEFAULT 0,
  `delivery_time_start` int(20) UNSIGNED DEFAULT 0,
  `delivery_time_end` int(20) UNSIGNED DEFAULT 0,
  `display_text` varchar(250) NOT NULL DEFAULT ''
) ENGINE=InnoDB DEFAULT CHARSET=latin1 COLLATE=latin1_swedish_ci;

-- --------------------------------------------------------

--
-- Table structure for table `timing_slot_groups`
--

CREATE TABLE `timing_slot_groups` (
  `id` int(11) NOT NULL,
  `min_amount` float(10,2) NOT NULL,
  `express_delivery_charge` float(10,2) NOT NULL,
  `delivery_charge` float(10,2) NOT NULL,
  `admin_id` int(11) NOT NULL,
  `is_active` enum('1','0') NOT NULL,
  `created_at` datetime NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=latin1 COLLATE=latin1_swedish_ci;

-- --------------------------------------------------------

--
-- Table structure for table `timing_slot_group_categories`
--

CREATE TABLE `timing_slot_group_categories` (
  `id` int(11) NOT NULL,
  `group_id` int(11) NOT NULL,
  `category_id` int(11) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=latin1 COLLATE=latin1_swedish_ci;

-- --------------------------------------------------------

--
-- Table structure for table `trips`
--

CREATE TABLE `trips` (
  `trip_id` int(10) NOT NULL,
  `deli_id` int(11) UNSIGNED DEFAULT NULL,
  `status` varchar(30) NOT NULL COMMENT 'unass, ass, ongoing, completed',
  `description` varchar(40) NOT NULL COMMENT 'vehicle number, trip number. || just vehicle number',
  `start_date` varchar(30) NOT NULL,
  `completed_at` varchar(25) NOT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  `has_discrepancy` tinyint(1) DEFAULT 0 COMMENT 'Indicates if trip has unresolved discrepancies',
  `zone_id` int(11) DEFAULT NULL,
  `vehicle_id` int(11) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=latin1 COLLATE=latin1_swedish_ci;

-- --------------------------------------------------------

--
-- Table structure for table `trip_audit_log`
--

CREATE TABLE `trip_audit_log` (
  `id` int(11) NOT NULL,
  `trip_id` int(11) NOT NULL,
  `order_id` int(11) NOT NULL,
  `item_id` int(11) NOT NULL,
  `vendor_product_id` int(11) NOT NULL,
  `product_id` int(11) NOT NULL,
  `qty_loaded` int(11) NOT NULL,
  `qty_claimed_delivered` int(11) NOT NULL,
  `qty_claimed_returned` int(11) NOT NULL,
  `qty_verified_delivered` int(11) NOT NULL,
  `qty_verified_returned` int(11) NOT NULL,
  `discrepancy_delivered` int(11) GENERATED ALWAYS AS (`qty_verified_delivered` - `qty_claimed_delivered`) STORED,
  `discrepancy_returned` int(11) GENERATED ALWAYS AS (`qty_verified_returned` - `qty_claimed_returned`) STORED,
  `auditor_deli_id` int(11) NOT NULL COMMENT 'References deli_staff.deli_id (the auditor who verified the trip)',
  `audited_at` datetime NOT NULL,
  `investigation_status` enum('pending','resolved') DEFAULT 'pending',
  `investigator_deli_id` int(11) DEFAULT NULL COMMENT 'References deli_staff.deli_id (the investigator who resolved discrepancies)',
  `investigated_at` datetime DEFAULT NULL,
  `resolution_outcome` enum('stock_loss','stock_recovered') DEFAULT NULL,
  `resolution_notes` text DEFAULT NULL,
  `qty_recovered_returned` int(11) DEFAULT NULL,
  `driver_liable` tinyint(1) DEFAULT 0,
  `liability_amount` decimal(10,2) DEFAULT 0.00,
  `created_at` datetime DEFAULT current_timestamp(),
  `updated_at` datetime DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------

--
-- Table structure for table `trip_cards`
--

CREATE TABLE `trip_cards` (
  `zone_id` int(11) NOT NULL,
  `zone_name` varchar(100) NOT NULL,
  `status` enum('active','inactive') NOT NULL DEFAULT 'active',
  `zone_code` varchar(10) DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------

--
-- Table structure for table `trip_card_pincode`
--

CREATE TABLE `trip_card_pincode` (
  `id` int(11) NOT NULL,
  `zone_id` int(11) NOT NULL,
  `pincode` varchar(6) NOT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------

--
-- Table structure for table `units_master`
--

CREATE TABLE `units_master` (
  `unit_id` int(11) NOT NULL,
  `unit_name` varchar(100) NOT NULL,
  `serial_no` int(11) DEFAULT NULL,
  `conversion_rate` decimal(10,4) NOT NULL,
  `is_active` tinyint(1) NOT NULL DEFAULT 1,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `is_locked` tinyint(1) NOT NULL DEFAULT 0
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;

-- --------------------------------------------------------

--
-- Table structure for table `update_script`
--

CREATE TABLE `update_script` (
  `update_sno` bigint(20) UNSIGNED NOT NULL,
  `batch_uuid` char(36) NOT NULL,
  `voucher_name` varchar(64) NOT NULL COMMENT 'snake_case source table name, e.g. purchase_order_items',
  `source_pk` bigint(20) UNSIGNED NOT NULL COMMENT 'the updated row''s own primary key value in its source table',
  `source_app` varchar(20) NOT NULL DEFAULT 'PMS' COMMENT 'which app performed the mutation; always PMS from this codebase',
  `update_json` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_bin NOT NULL COMMENT 'full column values immediately BEFORE the update (old state, not a diff, not the new state)' CHECK (json_valid(`update_json`)),
  `user_id` int(10) UNSIGNED DEFAULT NULL COMMENT 'acting user id; NULL for console/no-auth context',
  `timestamp` timestamp NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Table structure for table `user`
--

CREATE TABLE `user` (
  `userid` bigint(20) UNSIGNED NOT NULL,
  `email` varchar(250) NOT NULL DEFAULT ' ',
  `is_email_verified` tinyint(4) NOT NULL DEFAULT 0,
  `contactno` varchar(250) NOT NULL,
  `is_contact_verified` tinyint(4) NOT NULL DEFAULT 0,
  `name` text NOT NULL,
  `account_state` varchar(250) NOT NULL DEFAULT 'incomplete',
  `address` text NOT NULL,
  `latitude` float(10,6) NOT NULL DEFAULT 0.000000,
  `longitude` float(10,6) NOT NULL DEFAULT 0.000000,
  `dob` text DEFAULT NULL,
  `register_date` int(10) UNSIGNED NOT NULL DEFAULT 0,
  `shop_name` varchar(255) DEFAULT NULL,
  `shop_address` varchar(255) DEFAULT NULL,
  `shop_plot_no` varchar(255) DEFAULT NULL,
  `user_type` enum('B2C','B2B') NOT NULL,
  `adhar_card` varchar(255) DEFAULT NULL,
  `shop_photo` varchar(255) DEFAULT NULL,
  `shop_licence` varchar(255) DEFAULT NULL,
  `bussiness_pan_card` varchar(255) DEFAULT NULL,
  `is_approved` enum('YES','NO','REQUESTED') NOT NULL DEFAULT 'YES',
  `session_id` text NOT NULL,
  `last_activity` int(10) UNSIGNED NOT NULL DEFAULT 0,
  `push_notif_id` text NOT NULL,
  `is_first_login` tinyint(4) UNSIGNED NOT NULL DEFAULT 1,
  `has_unread_comments` tinyint(3) UNSIGNED NOT NULL DEFAULT 0,
  `password` varchar(250) DEFAULT NULL,
  `pincode` varchar(20) DEFAULT NULL,
  `city` varchar(100) DEFAULT NULL,
  `state` varchar(100) DEFAULT NULL,
  `gst_no` varchar(255) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=latin1 COLLATE=latin1_swedish_ci;

-- --------------------------------------------------------

--
-- Table structure for table `user_addresses`
--

CREATE TABLE `user_addresses` (
  `id` int(11) NOT NULL,
  `user_id` int(11) NOT NULL,
  `full_name` varchar(255) DEFAULT NULL,
  `full_address` varchar(255) DEFAULT NULL,
  `phone_no` varchar(255) DEFAULT NULL,
  `name` varchar(255) NOT NULL,
  `address` varchar(255) NOT NULL,
  `pincode` varchar(10) DEFAULT NULL,
  `lat` double(10,8) NOT NULL,
  `lng` double(11,8) NOT NULL,
  `type` enum('Home','Office') NOT NULL,
  `city_id` varchar(255) NOT NULL,
  `area_id` varchar(255) NOT NULL,
  `is_default` enum('0','1') NOT NULL,
  `created_at` datetime NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=latin1 COLLATE=latin1_swedish_ci;

-- --------------------------------------------------------

--
-- Table structure for table `user_membership`
--

CREATE TABLE `user_membership` (
  `id` int(11) NOT NULL,
  `membership_id` int(11) NOT NULL,
  `user_id` int(11) NOT NULL,
  `purchased_date` datetime NOT NULL,
  `membership_months` int(11) NOT NULL,
  `start_date` datetime NOT NULL,
  `expire_date` datetime NOT NULL,
  `amount` float(10,2) NOT NULL,
  `payment_status` enum('PENDING','COMPELETED') NOT NULL,
  `is_active` tinyint(1) NOT NULL DEFAULT 1,
  `created_at` datetime NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=latin1 COLLATE=latin1_swedish_ci;

-- --------------------------------------------------------

--
-- Table structure for table `user_notifications`
--

CREATE TABLE `user_notifications` (
  `id` int(11) NOT NULL,
  `user_id` int(11) DEFAULT NULL,
  `notification_id` int(11) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=latin1 COLLATE=latin1_swedish_ci;

-- --------------------------------------------------------

--
-- Table structure for table `vehicles`
--

CREATE TABLE `vehicles` (
  `vehicle_id` int(11) NOT NULL,
  `vehicle_number` varchar(50) NOT NULL,
  `capacity_kg` decimal(10,2) NOT NULL,
  `is_active` tinyint(1) NOT NULL DEFAULT 1,
  `created_at` datetime NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------

--
-- Table structure for table `vehicle_dispatch`
--

CREATE TABLE `vehicle_dispatch` (
  `id` int(11) NOT NULL,
  `trip_id` int(10) NOT NULL,
  `order_id` bigint(20) NOT NULL,
  `vendor_product_id` int(11) NOT NULL,
  `pack_id` varchar(5) NOT NULL,
  `quantity_expected` decimal(10,2) NOT NULL,
  `quantity_loaded` decimal(10,2) DEFAULT 0.00,
  `quantity_delivered` decimal(10,2) DEFAULT 0.00,
  `quantity_returned` decimal(10,2) DEFAULT 0.00,
  `timestamp` datetime DEFAULT current_timestamp(),
  `note` text DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=latin1 COLLATE=latin1_swedish_ci;

-- --------------------------------------------------------

--
-- Table structure for table `vendor_area_categories`
--

CREATE TABLE `vendor_area_categories` (
  `id` int(11) NOT NULL,
  `admin_id` int(11) NOT NULL,
  `city_id` varchar(255) NOT NULL DEFAULT '',
  `area_id` varchar(255) NOT NULL,
  `category_id` varchar(255) NOT NULL,
  `commisson` int(11) NOT NULL DEFAULT 0
) ENGINE=InnoDB DEFAULT CHARSET=latin1 COLLATE=latin1_swedish_ci;

-- --------------------------------------------------------

--
-- Table structure for table `vendor_products`
--

CREATE TABLE `vendor_products` (
  `id` int(11) NOT NULL,
  `admin_vendor_id` int(11) NOT NULL,
  `product_id` int(11) NOT NULL,
  `packs` text NOT NULL,
  `default_pack_id` varchar(255) NOT NULL,
  `status` enum('1','0') NOT NULL,
  `in_stock` enum('1','0') NOT NULL,
  `created_at` datetime NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_general_ci;

-- --------------------------------------------------------

--
-- Table structure for table `vendor_products_inventory`
--

CREATE TABLE `vendor_products_inventory` (
  `id` int(11) NOT NULL,
  `vendor_product_id` int(11) NOT NULL,
  `product_id` int(11) NOT NULL,
  `action_type` varchar(255) NOT NULL,
  `pack_id` varchar(255) DEFAULT NULL,
  `vendor_id` int(11) DEFAULT NULL,
  `quantity` double(10,2) NOT NULL,
  `unit_type` varchar(255) NOT NULL,
  `unit_id` int(10) UNSIGNED DEFAULT NULL,
  `unitquantity` decimal(18,6) NOT NULL,
  `amount` double(10,2) NOT NULL,
  `wholesale_user_id` int(11) DEFAULT NULL,
  `inv_date` date NOT NULL,
  `inv_datetime` datetime DEFAULT NULL,
  `inv_type` enum('CREDIT','DEBIT') NOT NULL,
  `note` text NOT NULL,
  `source` varchar(100) DEFAULT NULL,
  `trip_id` int(11) DEFAULT NULL,
  `updated_at` datetime NOT NULL,
  `created_at` datetime NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_general_ci;

-- --------------------------------------------------------

--
-- Table structure for table `vouchers`
--

CREATE TABLE `vouchers` (
  `id` bigint(20) UNSIGNED NOT NULL,
  `admin_id` int(10) UNSIGNED DEFAULT NULL,
  `voucher_type` varchar(10) NOT NULL COMMENT 'CP | BP | CR | BR | CN | DN | JV | PDC | PDR',
  `voucher_no` varchar(40) NOT NULL,
  `fy` varchar(7) NOT NULL COMMENT 'e.g. 25-26',
  `seq` int(10) UNSIGNED NOT NULL COMMENT 'per (voucher_type, fy) counter',
  `voucher_date` date NOT NULL,
  `cash_bank_account_id` bigint(20) UNSIGNED DEFAULT NULL COMMENT 'general_account.id; NULL for JV (no single cash/bank header)',
  `total_amount` decimal(14,2) NOT NULL DEFAULT 0.00,
  `narration` text DEFAULT NULL,
  `status` varchar(12) NOT NULL DEFAULT 'POSTED' COMMENT 'POSTED | CANCELLED',
  `created_by` bigint(20) UNSIGNED DEFAULT NULL,
  `updated_by` bigint(20) UNSIGNED DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT NULL,
  `updated_at` timestamp NULL DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------

--
-- Table structure for table `voucher_details`
--

CREATE TABLE `voucher_details` (
  `id` bigint(20) UNSIGNED NOT NULL,
  `voucher_id` bigint(20) UNSIGNED NOT NULL,
  `account_category` varchar(10) NOT NULL COMMENT 'CUSTOMER | SUPPLIER | GENERAL',
  `account_id` bigint(20) UNSIGNED NOT NULL COMMENT 'user.userid | suppliers.id | general_account.id',
  `amount` decimal(14,2) NOT NULL,
  `narration` text DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------

--
-- Table structure for table `voucher_pdc_details`
--

CREATE TABLE `voucher_pdc_details` (
  `id` bigint(20) UNSIGNED NOT NULL,
  `voucher_id` bigint(20) UNSIGNED NOT NULL,
  `cheque_no` varchar(40) NOT NULL,
  `cheque_date` date NOT NULL COMMENT 'due / maturity date printed on the cheque',
  `bank_name` varchar(100) DEFAULT NULL,
  `status` varchar(12) NOT NULL DEFAULT 'PENDING' COMMENT 'PENDING | CLEARED | BOUNCED',
  `cleared_date` date DEFAULT NULL,
  `bounced_date` date DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT NULL,
  `updated_at` timestamp NULL DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------

--
-- Table structure for table `wallet`
--

CREATE TABLE `wallet` (
  `id` int(11) NOT NULL,
  `user_id` int(11) NOT NULL,
  `virtual_amount` float(10,2) NOT NULL,
  `amunt` float(10,2) NOT NULL,
  `event_type` varchar(255) NOT NULL,
  `relative_id` int(11) NOT NULL,
  `info` text NOT NULL,
  `created_at` datetime NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=latin1 COLLATE=latin1_swedish_ci;

-- --------------------------------------------------------

--
-- Table structure for table `zone_vehicles`
--

CREATE TABLE `zone_vehicles` (
  `id` int(11) NOT NULL,
  `zone_id` int(11) NOT NULL,
  `vehicle_id` int(11) NOT NULL,
  `assigned_at` datetime NOT NULL DEFAULT current_timestamp(),
  `is_active` tinyint(1) NOT NULL DEFAULT 1
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------

--
-- Table structure for table `⁠ package_segregation_types ⁠`
--

CREATE TABLE `⁠ package_segregation_types ⁠` (
  `⁠ id ⁠` int(10) UNSIGNED NOT NULL,
  `⁠ admin_vendor_id ⁠` int(11) NOT NULL,
  `⁠ name ⁠` varchar(100) NOT NULL,
  `⁠ is_active ⁠` tinyint(1) NOT NULL DEFAULT 1,
  `⁠ created_at ⁠` datetime NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------

--
-- Table structure for table `⁠ package_segregation ⁠`
--

CREATE TABLE `⁠ package_segregation ⁠` (
  `⁠ id ⁠` int(10) UNSIGNED NOT NULL,
  `⁠ admin_vendor_id ⁠` int(11) NOT NULL,
  `⁠ product_id ⁠` int(11) NOT NULL,
  `⁠ pack_id ⁠` varchar(255) NOT NULL COMMENT 'vendor_products.packs[].pi',
  `⁠ pack_sg_id ⁠` int(10) UNSIGNED NOT NULL COMMENT 'package_segregation_types.id',
  `⁠ created_at ⁠` datetime NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Indexes for dumped tables
--

--
-- Indexes for table `admin`
--
ALTER TABLE `admin`
  ADD PRIMARY KEY (`userid`);

--
-- Indexes for table `api_tokens`
--
ALTER TABLE `api_tokens`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `api_tokens_token_hash_unique` (`token_hash`);

--
-- Indexes for table `app_settings`
--
ALTER TABLE `app_settings`
  ADD PRIMARY KEY (`admin_id`,`setting_key`);

--
-- Indexes for table `bill_adjustments`
--
ALTER TABLE `bill_adjustments`
  ADD PRIMARY KEY (`id`),
  ADD KEY `bill_adjustments_voucher_detail_id_index` (`voucher_detail_id`),
  ADD KEY `bill_adjustments_invoice_type_invoice_id_index` (`invoice_type`,`invoice_id`);

--
-- Indexes for table `brand`
--
ALTER TABLE `brand`
  ADD PRIMARY KEY (`brand_id`);

--
-- Indexes for table `BusinessType`
--
ALTER TABLE `BusinessType`
  ADD PRIMARY KEY (`id`);

--
-- Indexes for table `calling_staff`
--
ALTER TABLE `calling_staff`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `unique_contactNumber` (`contact_no`);

--
-- Indexes for table `cart`
--
ALTER TABLE `cart`
  ADD PRIMARY KEY (`cart_id`),
  ADD UNIQUE KEY `unique_user_product_pack_address` (`userid`,`product_id`,`pack_id`,`addressId`);

--
-- Indexes for table `cart_type`
--
ALTER TABLE `cart_type`
  ADD PRIMARY KEY (`cart_tid`);

--
-- Indexes for table `categories`
--
ALTER TABLE `categories`
  ADD PRIMARY KEY (`cat_id`);

--
-- Indexes for table `collection`
--
ALTER TABLE `collection`
  ADD PRIMARY KEY (`col_id`);

--
-- Indexes for table `daily_book_stock`
--
ALTER TABLE `daily_book_stock`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `unique_product_date` (`vendor_product_id`,`date`),
  ADD KEY `idx_product_date` (`vendor_product_id`,`date`),
  ADD KEY `idx_date` (`date`);

--
-- Indexes for table `delete_script`
--
ALTER TABLE `delete_script`
  ADD PRIMARY KEY (`delete_sno`),
  ADD KEY `idx_delete_script_voucher_ts` (`voucher_name`,`timestamp`),
  ADD KEY `idx_delete_script_batch` (`batch_uuid`),
  ADD KEY `idx_delete_script_voucher_pk` (`voucher_name`,`source_pk`);

--
-- Indexes for table `deli_staff`
--
ALTER TABLE `deli_staff`
  ADD PRIMARY KEY (`deli_id`),
  ADD UNIQUE KEY `mobile` (`mobile`);

--
-- Indexes for table `department_crm`
--
ALTER TABLE `department_crm`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `Department_name_key` (`name`);

--
-- Indexes for table `driver_accountability_log`
--
ALTER TABLE `driver_accountability_log`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_driver` (`driver_deli_id`),
  ADD KEY `idx_trip` (`trip_id`),
  ADD KEY `idx_penalty_status` (`penalty_status`),
  ADD KEY `idx_audit_log` (`audit_log_id`);

--
-- Indexes for table `driver_rating`
--
ALTER TABLE `driver_rating`
  ADD PRIMARY KEY (`order_id`),
  ADD UNIQUE KEY `rating_id` (`rating_id`);

--
-- Indexes for table `enquiry`
--
ALTER TABLE `enquiry`
  ADD PRIMARY KEY (`id`);

--
-- Indexes for table `expense`
--
ALTER TABLE `expense`
  ADD PRIMARY KEY (`ex_id`);

--
-- Indexes for table `expense_type`
--
ALTER TABLE `expense_type`
  ADD PRIMARY KEY (`id`);

--
-- Indexes for table `favorites`
--
ALTER TABLE `favorites`
  ADD PRIMARY KEY (`userid`,`product_id`);

--
-- Indexes for table `general_account`
--
ALTER TABLE `general_account`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `general_account_account_no_unique` (`account_no`),
  ADD KEY `general_account_account_type_index` (`account_type`);

--
-- Indexes for table `guests`
--
ALTER TABLE `guests`
  ADD PRIMARY KEY (`guest_id`);

--
-- Indexes for table `hsn_codes`
--
ALTER TABLE `hsn_codes`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `hsn_codes_hsn_code_unique` (`hsn_code`);

--
-- Indexes for table `inventory_op`
--
ALTER TABLE `inventory_op`
  ADD PRIMARY KEY (`op_id`);

--
-- Indexes for table `lead`
--
ALTER TABLE `lead`
  ADD PRIMARY KEY (`lead_id`),
  ADD UNIQUE KEY `contact_no` (`contact_no`);

--
-- Indexes for table `ledger_entries`
--
ALTER TABLE `ledger_entries`
  ADD PRIMARY KEY (`id`),
  ADD KEY `ledger_entries_voucher_id_index` (`voucher_id`),
  ADD KEY `ledger_entries_source_id_date_index` (`ledger_source`,`ledger_id`,`entry_date`);

--
-- Indexes for table `LoginUser_crm`
--
ALTER TABLE `LoginUser_crm`
  ADD PRIMARY KEY (`id`),
  ADD KEY `User_departmentId_fkey` (`departmentId`);

--
-- Indexes for table `master_orders`
--
ALTER TABLE `master_orders`
  ADD PRIMARY KEY (`id`);

--
-- Indexes for table `migrations`
--
ALTER TABLE `migrations`
  ADD PRIMARY KEY (`id`);

--
-- Indexes for table `notes`
--
ALTER TABLE `notes`
  ADD PRIMARY KEY (`id`),
  ADD KEY `notes_user_id_index` (`user_id`),
  ADD KEY `notes_folder_name_index` (`folder_name`);

--
-- Indexes for table `notifications`
--
ALTER TABLE `notifications`
  ADD PRIMARY KEY (`id`);

--
-- Indexes for table `offers`
--
ALTER TABLE `offers`
  ADD PRIMARY KEY (`off_id`);

--
-- Indexes for table `offer_log`
--
ALTER TABLE `offer_log`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_user_offer_date` (`user_id`,`offer_id`,`used_date`);

--
-- Indexes for table `orders`
--
ALTER TABLE `orders`
  ADD PRIMARY KEY (`order_id`),
  ADD KEY `fk_orders_trips` (`trip_id`),
  ADD KEY `fk_orders_userid` (`master_order_id`);

--
-- Indexes for table `orders_item`
--
ALTER TABLE `orders_item`
  ADD PRIMARY KEY (`item_id`);

--
-- Indexes for table `otp`
--
ALTER TABLE `otp`
  ADD PRIMARY KEY (`contactno`);

--
-- Indexes for table `package_segregation`
--
ALTER TABLE `package_segregation`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uq_package_segregation_vendor_product_pack` (`admin_vendor_id`,`product_id`,`pack_id`),
  ADD KEY `idx_package_segregation_product_id` (`product_id`);

--
-- Indexes for table `party_advances`
--
ALTER TABLE `party_advances`
  ADD PRIMARY KEY (`id`),
  ADD KEY `party_advances_party_type_party_id_index` (`party_type`,`party_id`),
  ADD KEY `party_advances_voucher_detail_id_index` (`voucher_detail_id`);

--
-- Indexes for table `physical_stock`
--
ALTER TABLE `physical_stock`
  ADD PRIMARY KEY (`id`),
  ADD KEY `vendor_product_id` (`vendor_product_id`);

--
-- Indexes for table `pincodes`
--
ALTER TABLE `pincodes`
  ADD PRIMARY KEY (`area_id`);

--
-- Indexes for table `pincode_masters`
--
ALTER TABLE `pincode_masters`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `pincode` (`pincode`),
  ADD UNIQUE KEY `pincode_unique` (`pincode`),
  ADD KEY `city_index` (`city`),
  ADD KEY `state_index` (`state`),
  ADD KEY `delivery_available_index` (`delivery_available`);

--
-- Indexes for table `product`
--
ALTER TABLE `product`
  ADD PRIMARY KEY (`product_id`);
ALTER TABLE `product` ADD FULLTEXT KEY `prodNameFullText` (`name`,`keywords`);

--
-- Indexes for table `product_bkp`
--
ALTER TABLE `product_bkp`
  ADD PRIMARY KEY (`product_id`);
ALTER TABLE `product_bkp` ADD FULLTEXT KEY `prodNameFullText` (`name`,`keywords`);

--
-- Indexes for table `product_photos`
--
ALTER TABLE `product_photos`
  ADD PRIMARY KEY (`photo_id`);

--
-- Indexes for table `product_purchase`
--
ALTER TABLE `product_purchase`
  ADD PRIMARY KEY (`item_id`),
  ADD UNIQUE KEY `day_id` (`day_id`,`product_id`);

--
-- Indexes for table `product_taxes`
--
ALTER TABLE `product_taxes`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `product_taxes_product_id_tax_id_unique` (`product_id`,`tax_id`),
  ADD KEY `product_taxes_product_id_index` (`product_id`),
  ADD KEY `product_taxes_tax_id_foreign` (`tax_id`);

--
-- Indexes for table `prod_barcodes`
--
ALTER TABLE `prod_barcodes`
  ADD PRIMARY KEY (`bar_id`),
  ADD UNIQUE KEY `product_id` (`product_id`,`pack_id`);

--
-- Indexes for table `promo`
--
ALTER TABLE `promo`
  ADD PRIMARY KEY (`promo_id`);

--
-- Indexes for table `promo_log`
--
ALTER TABLE `promo_log`
  ADD PRIMARY KEY (`log_id`);

--
-- Indexes for table `purchase_orders`
--
ALTER TABLE `purchase_orders`
  ADD PRIMARY KEY (`id`),
  ADD KEY `purchase_orders_supplier_id_index` (`supplier_id`),
  ADD KEY `purchase_orders_status_index` (`status`),
  ADD KEY `purchase_orders_doc_date_index` (`doc_date`),
  ADD KEY `idx_admin_id` (`admin_id`);

--
-- Indexes for table `purchase_order_items`
--
ALTER TABLE `purchase_order_items`
  ADD PRIMARY KEY (`id`),
  ADD KEY `purchase_order_items_po_product_index` (`purchase_order_id`,`product_id`),
  ADD KEY `idx_poi_po_vp` (`purchase_order_id`,`vendor_product_id`);

--
-- Indexes for table `purchase_returns`
--
ALTER TABLE `purchase_returns`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `purchase_returns_idempotency_key_unique` (`idempotency_key`),
  ADD KEY `purchase_returns_supplier_id_index` (`supplier_id`),
  ADD KEY `purchase_returns_doc_date_index` (`doc_date`),
  ADD KEY `purchase_returns_source_purchase_voucher_id_foreign` (`source_purchase_voucher_id`),
  ADD KEY `idx_admin_id` (`admin_id`);

--
-- Indexes for table `purchase_return_items`
--
ALTER TABLE `purchase_return_items`
  ADD PRIMARY KEY (`id`),
  ADD KEY `purchase_return_items_purchase_return_id_foreign` (`purchase_return_id`),
  ADD KEY `purchase_return_items_source_purchase_voucher_item_id_foreign` (`source_purchase_voucher_item_id`),
  ADD KEY `idx_pri_pr_vp` (`purchase_return_id`,`vendor_product_id`);

--
-- Indexes for table `purchase_vouchers`
--
ALTER TABLE `purchase_vouchers`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `purchase_vouchers_idempotency_key_unique` (`idempotency_key`),
  ADD KEY `purchase_vouchers_supplier_id_index` (`supplier_id`),
  ADD KEY `purchase_vouchers_doc_date_index` (`doc_date`),
  ADD KEY `purchase_vouchers_purchase_order_id_foreign` (`purchase_order_id`),
  ADD KEY `idx_admin_id` (`admin_id`);

--
-- Indexes for table `purchase_voucher_items`
--
ALTER TABLE `purchase_voucher_items`
  ADD PRIMARY KEY (`id`),
  ADD KEY `purchase_voucher_items_purchase_voucher_id_product_id_index` (`purchase_voucher_id`,`product_id`),
  ADD KEY `idx_pvi_pv_vp` (`purchase_voucher_id`,`vendor_product_id`);

--
-- Indexes for table `recommendations`
--
ALTER TABLE `recommendations`
  ADD PRIMARY KEY (`id`);

--
-- Indexes for table `search`
--
ALTER TABLE `search`
  ADD PRIMARY KEY (`s.no`);
ALTER TABLE `search` ADD FULLTEXT KEY `searchTextFullText` (`search_text`);

--
-- Indexes for table `settings`
--
ALTER TABLE `settings`
  ADD PRIMARY KEY (`name`);

--
-- Indexes for table `stock_count`
--
ALTER TABLE `stock_count`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_assignment` (`assignment_id`),
  ADD KEY `idx_vendor_product` (`vendor_product_id`);

--
-- Indexes for table `stock_count_assignments`
--
ALTER TABLE `stock_count_assignments`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `unique_session_category` (`master_session_id`,`category_id`),
  ADD KEY `idx_counter_user` (`counter_user_id`),
  ADD KEY `idx_master_session` (`master_session_id`);

--
-- Indexes for table `stock_count_master_session`
--
ALTER TABLE `stock_count_master_session`
  ADD PRIMARY KEY (`id`);

--
-- Indexes for table `stock_notify`
--
ALTER TABLE `stock_notify`
  ADD UNIQUE KEY `userid` (`userid`,`product_id`);

--
-- Indexes for table `stock_voucher`
--
ALTER TABLE `stock_voucher`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `stock_voucher_idempotency_key_unique` (`idempotency_key`);

--
-- Indexes for table `stock_voucher_items`
--
ALTER TABLE `stock_voucher_items`
  ADD PRIMARY KEY (`id`),
  ADD KEY `stock_voucher_items_voucher_id_foreign` (`voucher_id`);

--
-- Indexes for table `suppliers`
--
ALTER TABLE `suppliers`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `suppliers_supplier_code_unique` (`supplier_code`),
  ADD KEY `suppliers_gst_no_index` (`gst_no`),
  ADD KEY `suppliers_pan_no_index` (`pan_no`),
  ADD KEY `idx_suppliers_admin_id` (`admin_id`);

--
-- Indexes for table `supplier_products`
--
ALTER TABLE `supplier_products`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `supplier_products_supplier_id_product_id_unique` (`supplier_id`,`product_id`),
  ADD UNIQUE KEY `supplier_products_supplier_id_supplier_sku_unique` (`supplier_id`,`supplier_sku`),
  ADD KEY `supplier_products_product_id_foreign` (`product_id`),
  ADD KEY `idx_sp_supplier_vp` (`supplier_id`,`vendor_product_id`);

--
-- Indexes for table `taxes`
--
ALTER TABLE `taxes`
  ADD PRIMARY KEY (`id`),
  ADD KEY `taxes_category_sub_index` (`tax_category`,`tax_sub_category`);

--
-- Indexes for table `time_slots`
--
ALTER TABLE `time_slots`
  ADD PRIMARY KEY (`slot_id`);

--
-- Indexes for table `timing_slot_groups`
--
ALTER TABLE `timing_slot_groups`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `admin_id` (`admin_id`);

--
-- Indexes for table `timing_slot_group_categories`
--
ALTER TABLE `timing_slot_group_categories`
  ADD PRIMARY KEY (`id`);

--
-- Indexes for table `trips`
--
ALTER TABLE `trips`
  ADD PRIMARY KEY (`trip_id`);

--
-- Indexes for table `trip_audit_log`
--
ALTER TABLE `trip_audit_log`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_trip` (`trip_id`),
  ADD KEY `idx_item` (`item_id`),
  ADD KEY `idx_status` (`investigation_status`),
  ADD KEY `idx_trip_status` (`trip_id`,`investigation_status`);

--
-- Indexes for table `trip_cards`
--
ALTER TABLE `trip_cards`
  ADD PRIMARY KEY (`zone_id`),
  ADD UNIQUE KEY `uq_trip_cards_zone_name` (`zone_name`);

--
-- Indexes for table `trip_card_pincode`
--
ALTER TABLE `trip_card_pincode`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uq_trip_card_pincode_pincode` (`pincode`),
  ADD KEY `idx_trip_card_pincode_zone_id` (`zone_id`);

--
-- Indexes for table `units_master`
--
ALTER TABLE `units_master`
  ADD PRIMARY KEY (`unit_id`),
  ADD UNIQUE KEY `units_master_unit_name_unique` (`unit_name`);

--
-- Indexes for table `update_script`
--
ALTER TABLE `update_script`
  ADD PRIMARY KEY (`update_sno`),
  ADD KEY `idx_update_script_voucher_ts` (`voucher_name`,`timestamp`),
  ADD KEY `idx_update_script_batch` (`batch_uuid`),
  ADD KEY `idx_update_script_voucher_pk` (`voucher_name`,`source_pk`);

--
-- Indexes for table `user`
--
ALTER TABLE `user`
  ADD PRIMARY KEY (`userid`);

--
-- Indexes for table `user_addresses`
--
ALTER TABLE `user_addresses`
  ADD PRIMARY KEY (`id`);

--
-- Indexes for table `user_notifications`
--
ALTER TABLE `user_notifications`
  ADD PRIMARY KEY (`id`),
  ADD KEY `notification_id` (`notification_id`);

--
-- Indexes for table `vehicles`
--
ALTER TABLE `vehicles`
  ADD PRIMARY KEY (`vehicle_id`),
  ADD UNIQUE KEY `uq_vehicles_vehicle_number` (`vehicle_number`);

--
-- Indexes for table `vehicle_dispatch`
--
ALTER TABLE `vehicle_dispatch`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `order_id` (`order_id`),
  ADD KEY `trip_id` (`trip_id`),
  ADD KEY `vendor_product_id` (`vendor_product_id`);

--
-- Indexes for table `vendor_area_categories`
--
ALTER TABLE `vendor_area_categories`
  ADD PRIMARY KEY (`id`);

--
-- Indexes for table `vendor_products`
--
ALTER TABLE `vendor_products`
  ADD PRIMARY KEY (`id`);

--
-- Indexes for table `vendor_products_inventory`
--
ALTER TABLE `vendor_products_inventory`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_vpi_note` (`note`(80));

--
-- Indexes for table `vouchers`
--
ALTER TABLE `vouchers`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `vouchers_voucher_no_unique` (`voucher_no`),
  ADD UNIQUE KEY `vouchers_voucher_type_fy_seq_unique` (`voucher_type`,`fy`,`seq`),
  ADD KEY `vouchers_voucher_type_voucher_date_index` (`voucher_type`,`voucher_date`),
  ADD KEY `idx_vouchers_admin_id` (`admin_id`);

--
-- Indexes for table `voucher_details`
--
ALTER TABLE `voucher_details`
  ADD PRIMARY KEY (`id`),
  ADD KEY `voucher_details_voucher_id_index` (`voucher_id`),
  ADD KEY `voucher_details_account_category_account_id_index` (`account_category`,`account_id`);

--
-- Indexes for table `voucher_pdc_details`
--
ALTER TABLE `voucher_pdc_details`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `voucher_pdc_details_voucher_id_unique` (`voucher_id`),
  ADD KEY `voucher_pdc_details_status_cheque_date_index` (`status`,`cheque_date`);

--
-- Indexes for table `wallet`
--
ALTER TABLE `wallet`
  ADD PRIMARY KEY (`id`);

--
-- Indexes for table `zone_vehicles`
--
ALTER TABLE `zone_vehicles`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_zone_vehicles_zone_id` (`zone_id`),
  ADD KEY `idx_zone_vehicles_vehicle_id` (`vehicle_id`),
  ADD KEY `idx_zone_vehicles_active` (`is_active`);

--
-- Indexes for table `⁠ package_segregation_types ⁠`
--
ALTER TABLE `⁠ package_segregation_types ⁠`
  ADD PRIMARY KEY (`⁠ id ⁠`),
  ADD UNIQUE KEY `⁠ uq_package_segregation_types_vendor_name ⁠` (`⁠ admin_vendor_id ⁠`,`⁠ name ⁠`);

--
-- Indexes for table `⁠ package_segregation ⁠`
--
ALTER TABLE `⁠ package_segregation ⁠`
  ADD PRIMARY KEY (`⁠ id ⁠`),
  ADD UNIQUE KEY `⁠ uq_package_segregation_vendor_product_pack ⁠` (`⁠ admin_vendor_id ⁠`,`⁠ product_id ⁠`,`⁠ pack_id ⁠`),
  ADD KEY `⁠ idx_package_segregation_product_id ⁠` (`⁠ product_id ⁠`),
  ADD KEY `⁠ idx_package_segregation_pack_sg_id ⁠` (`⁠ pack_sg_id ⁠`);

--
-- AUTO_INCREMENT for dumped tables
--

--
-- AUTO_INCREMENT for table `admin`
--
ALTER TABLE `admin`
  MODIFY `userid` int(11) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `api_tokens`
--
ALTER TABLE `api_tokens`
  MODIFY `id` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `bill_adjustments`
--
ALTER TABLE `bill_adjustments`
  MODIFY `id` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `brand`
--
ALTER TABLE `brand`
  MODIFY `brand_id` int(10) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `calling_staff`
--
ALTER TABLE `calling_staff`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `cart`
--
ALTER TABLE `cart`
  MODIFY `cart_id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `cart_type`
--
ALTER TABLE `cart_type`
  MODIFY `cart_tid` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `categories`
--
ALTER TABLE `categories`
  MODIFY `cat_id` bigint(5) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `collection`
--
ALTER TABLE `collection`
  MODIFY `col_id` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `daily_book_stock`
--
ALTER TABLE `daily_book_stock`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `delete_script`
--
ALTER TABLE `delete_script`
  MODIFY `delete_sno` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `deli_staff`
--
ALTER TABLE `deli_staff`
  MODIFY `deli_id` int(11) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `driver_accountability_log`
--
ALTER TABLE `driver_accountability_log`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `driver_rating`
--
ALTER TABLE `driver_rating`
  MODIFY `rating_id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `enquiry`
--
ALTER TABLE `enquiry`
  MODIFY `id` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `expense`
--
ALTER TABLE `expense`
  MODIFY `ex_id` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `expense_type`
--
ALTER TABLE `expense_type`
  MODIFY `id` int(10) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `general_account`
--
ALTER TABLE `general_account`
  MODIFY `id` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `guests`
--
ALTER TABLE `guests`
  MODIFY `guest_id` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `hsn_codes`
--
ALTER TABLE `hsn_codes`
  MODIFY `id` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `inventory_op`
--
ALTER TABLE `inventory_op`
  MODIFY `op_id` int(10) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `lead`
--
ALTER TABLE `lead`
  MODIFY `lead_id` int(10) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `ledger_entries`
--
ALTER TABLE `ledger_entries`
  MODIFY `id` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `master_orders`
--
ALTER TABLE `master_orders`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `migrations`
--
ALTER TABLE `migrations`
  MODIFY `id` int(10) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `notifications`
--
ALTER TABLE `notifications`
  MODIFY `id` int(10) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `offers`
--
ALTER TABLE `offers`
  MODIFY `off_id` bigint(20) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `offer_log`
--
ALTER TABLE `offer_log`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `orders`
--
ALTER TABLE `orders`
  MODIFY `order_id` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `orders_item`
--
ALTER TABLE `orders_item`
  MODIFY `item_id` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `package_segregation`
--
ALTER TABLE `package_segregation`
  MODIFY `id` int(10) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `party_advances`
--
ALTER TABLE `party_advances`
  MODIFY `id` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `physical_stock`
--
ALTER TABLE `physical_stock`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `pincode_masters`
--
ALTER TABLE `pincode_masters`
  MODIFY `id` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `product`
--
ALTER TABLE `product`
  MODIFY `product_id` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `product_bkp`
--
ALTER TABLE `product_bkp`
  MODIFY `product_id` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `product_photos`
--
ALTER TABLE `product_photos`
  MODIFY `photo_id` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `product_purchase`
--
ALTER TABLE `product_purchase`
  MODIFY `item_id` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `product_taxes`
--
ALTER TABLE `product_taxes`
  MODIFY `id` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `prod_barcodes`
--
ALTER TABLE `prod_barcodes`
  MODIFY `bar_id` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `promo`
--
ALTER TABLE `promo`
  MODIFY `promo_id` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `promo_log`
--
ALTER TABLE `promo_log`
  MODIFY `log_id` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `purchase_orders`
--
ALTER TABLE `purchase_orders`
  MODIFY `id` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `purchase_order_items`
--
ALTER TABLE `purchase_order_items`
  MODIFY `id` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `purchase_returns`
--
ALTER TABLE `purchase_returns`
  MODIFY `id` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `purchase_return_items`
--
ALTER TABLE `purchase_return_items`
  MODIFY `id` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `purchase_vouchers`
--
ALTER TABLE `purchase_vouchers`
  MODIFY `id` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `purchase_voucher_items`
--
ALTER TABLE `purchase_voucher_items`
  MODIFY `id` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `recommendations`
--
ALTER TABLE `recommendations`
  MODIFY `id` int(6) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `search`
--
ALTER TABLE `search`
  MODIFY `s.no` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `stock_count`
--
ALTER TABLE `stock_count`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `stock_count_assignments`
--
ALTER TABLE `stock_count_assignments`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `stock_count_master_session`
--
ALTER TABLE `stock_count_master_session`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `stock_voucher`
--
ALTER TABLE `stock_voucher`
  MODIFY `id` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `stock_voucher_items`
--
ALTER TABLE `stock_voucher_items`
  MODIFY `id` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `suppliers`
--
ALTER TABLE `suppliers`
  MODIFY `id` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `supplier_products`
--
ALTER TABLE `supplier_products`
  MODIFY `id` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `taxes`
--
ALTER TABLE `taxes`
  MODIFY `id` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `time_slots`
--
ALTER TABLE `time_slots`
  MODIFY `slot_id` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `timing_slot_groups`
--
ALTER TABLE `timing_slot_groups`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `timing_slot_group_categories`
--
ALTER TABLE `timing_slot_group_categories`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `trip_audit_log`
--
ALTER TABLE `trip_audit_log`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `trip_cards`
--
ALTER TABLE `trip_cards`
  MODIFY `zone_id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `trip_card_pincode`
--
ALTER TABLE `trip_card_pincode`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `units_master`
--
ALTER TABLE `units_master`
  MODIFY `unit_id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `update_script`
--
ALTER TABLE `update_script`
  MODIFY `update_sno` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `user`
--
ALTER TABLE `user`
  MODIFY `userid` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `user_addresses`
--
ALTER TABLE `user_addresses`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `user_notifications`
--
ALTER TABLE `user_notifications`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `vehicles`
--
ALTER TABLE `vehicles`
  MODIFY `vehicle_id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `vehicle_dispatch`
--
ALTER TABLE `vehicle_dispatch`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `vendor_area_categories`
--
ALTER TABLE `vendor_area_categories`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `vendor_products`
--
ALTER TABLE `vendor_products`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `vendor_products_inventory`
--
ALTER TABLE `vendor_products_inventory`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `vouchers`
--
ALTER TABLE `vouchers`
  MODIFY `id` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `voucher_details`
--
ALTER TABLE `voucher_details`
  MODIFY `id` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `voucher_pdc_details`
--
ALTER TABLE `voucher_pdc_details`
  MODIFY `id` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `wallet`
--
ALTER TABLE `wallet`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `zone_vehicles`
--
ALTER TABLE `zone_vehicles`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `⁠ package_segregation_types ⁠`
--
ALTER TABLE `⁠ package_segregation_types ⁠`
  MODIFY `⁠ id ⁠` int(10) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `⁠ package_segregation ⁠`
--
ALTER TABLE `⁠ package_segregation ⁠`
  MODIFY `⁠ id ⁠` int(10) UNSIGNED NOT NULL AUTO_INCREMENT;

-- --------------------------------------------------------

--
-- Structure for view `eligible_delivery_addresses`
--
DROP TABLE IF EXISTS `eligible_delivery_addresses`;

CREATE ALGORITHM=UNDEFINED DEFINER=`root`@`localhost` SQL SECURITY DEFINER VIEW `eligible_delivery_addresses`  AS SELECT `user_addresses`.`id` AS `id`, `user_addresses`.`user_id` AS `user_id`, `user_addresses`.`full_name` AS `full_name`, `user_addresses`.`full_address` AS `full_address`, `user_addresses`.`phone_no` AS `phone_no`, `user_addresses`.`name` AS `name`, `user_addresses`.`address` AS `address`, `user_addresses`.`pincode` AS `pincode`, `user_addresses`.`lat` AS `lat`, `user_addresses`.`lng` AS `lng`, `user_addresses`.`type` AS `type`, `user_addresses`.`city_id` AS `city_id`, `user_addresses`.`area_id` AS `area_id`, `user_addresses`.`is_default` AS `is_default`, `user_addresses`.`created_at` AS `created_at` FROM `user_addresses` WHERE `user_addresses`.`is_default` = 2 ;

--
-- Constraints for dumped tables
--

--
-- Constraints for table `bill_adjustments`
--
ALTER TABLE `bill_adjustments`
  ADD CONSTRAINT `bill_adjustments_voucher_detail_id_foreign` FOREIGN KEY (`voucher_detail_id`) REFERENCES `voucher_details` (`id`) ON DELETE CASCADE;

--
-- Constraints for table `ledger_entries`
--
ALTER TABLE `ledger_entries`
  ADD CONSTRAINT `ledger_entries_voucher_id_foreign` FOREIGN KEY (`voucher_id`) REFERENCES `vouchers` (`id`) ON DELETE CASCADE;

--
-- Constraints for table `LoginUser_crm`
--
ALTER TABLE `LoginUser_crm`
  ADD CONSTRAINT `User_departmentId_fkey` FOREIGN KEY (`departmentId`) REFERENCES `department_crm` (`id`) ON DELETE SET NULL;

--
-- Constraints for table `notes`
--
ALTER TABLE `notes`
  ADD CONSTRAINT `notes_user_id_foreign` FOREIGN KEY (`user_id`) REFERENCES `user` (`userid`) ON DELETE CASCADE;

--
-- Constraints for table `party_advances`
--
ALTER TABLE `party_advances`
  ADD CONSTRAINT `party_advances_voucher_detail_id_foreign` FOREIGN KEY (`voucher_detail_id`) REFERENCES `voucher_details` (`id`) ON DELETE CASCADE;

--
-- Constraints for table `physical_stock`
--
ALTER TABLE `physical_stock`
  ADD CONSTRAINT `physical_stock_ibfk_1` FOREIGN KEY (`vendor_product_id`) REFERENCES `vendor_products` (`id`);

--
-- Constraints for table `product_taxes`
--
ALTER TABLE `product_taxes`
  ADD CONSTRAINT `product_taxes_product_id_foreign` FOREIGN KEY (`product_id`) REFERENCES `product` (`product_id`) ON DELETE CASCADE,
  ADD CONSTRAINT `product_taxes_tax_id_foreign` FOREIGN KEY (`tax_id`) REFERENCES `taxes` (`id`) ON DELETE CASCADE;

--
-- Constraints for table `stock_count`
--
ALTER TABLE `stock_count`
  ADD CONSTRAINT `stock_count_ibfk_1` FOREIGN KEY (`assignment_id`) REFERENCES `stock_count_assignments` (`id`) ON DELETE CASCADE;

--
-- Constraints for table `stock_count_assignments`
--
ALTER TABLE `stock_count_assignments`
  ADD CONSTRAINT `stock_count_assignments_ibfk_1` FOREIGN KEY (`master_session_id`) REFERENCES `stock_count_master_session` (`id`) ON DELETE CASCADE;

--
-- Constraints for table `vehicle_dispatch`
--
ALTER TABLE `vehicle_dispatch`
  ADD CONSTRAINT `vehicle_dispatch_ibfk_1` FOREIGN KEY (`trip_id`) REFERENCES `trips` (`trip_id`),
  ADD CONSTRAINT `vehicle_dispatch_ibfk_2` FOREIGN KEY (`vendor_product_id`) REFERENCES `vendor_products` (`id`);

--
-- Constraints for table `voucher_details`
--
ALTER TABLE `voucher_details`
  ADD CONSTRAINT `voucher_details_voucher_id_foreign` FOREIGN KEY (`voucher_id`) REFERENCES `vouchers` (`id`) ON DELETE CASCADE;

--
-- Constraints for table `voucher_pdc_details`
--
ALTER TABLE `voucher_pdc_details`
  ADD CONSTRAINT `voucher_pdc_details_voucher_id_foreign` FOREIGN KEY (`voucher_id`) REFERENCES `vouchers` (`id`) ON DELETE CASCADE;
COMMIT;

/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;

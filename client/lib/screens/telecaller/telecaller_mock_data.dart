import 'package:flutter/material.dart';

/// Shared constants for the telecaller dashboard + agent modules.
///
/// The screens now load real data from the backend; this file only holds the
/// brand tokens and the display styling for call outcomes and worklist labels
/// (keys mirror the real `call_outcome` enum and the server-side label values).

// ── Brand tokens ─────────────────────────────────────────────────────────────
const kGold = Color(0xFFD7BE69);
const kGoldDark = Color(0xFFC09E3E);
const kBg = Color(0xFFF5F5F5);

// ── Call outcomes (match call_log_crm.call_outcome) ──────────────────────────
const kOutcomeColors = <String, Color>{
  'answered': Color(0xFF43A047),
  'busy': Color(0xFFFB8C00),
  'no_answer': Color(0xFF8E24AA),
  'switch_off': Color(0xFF757575),
  'invalid': Color(0xFFE53935),
  'callback': Color(0xFF1E88E5),
  'complaint': Color(0xFFD32F2F),
  'pending': Color(0xFFBDBDBD),
};

const kOutcomeLabels = <String, String>{
  'answered': 'Answered',
  'busy': 'Busy',
  'no_answer': 'No Answer',
  'switch_off': 'Switched Off',
  'invalid': 'Invalid',
  'callback': 'Callback',
  'complaint': 'Complaint',
  'pending': 'In Progress',
};

// ── Complaint categories (v1 — plain labels, no auto-routing) ────────────────
const kComplaintCategories = <String>[
  'Product Quality / Damaged Goods',
  'Short Supply / Quantity Mismatch',
  'Wrong Item Delivered',
  'Late / Missed Delivery',
  'Billing / Payment Discrepancy',
  'Scheme / Discount Not Applied',
  'Salesman / Delivery Staff Behavior',
  'Order App / Technical Issue',
  'Return / Replacement Request',
  'Other / General Feedback',
];

// ── Worklist labels (match server-derived / custom label keys) ───────────────
const kLabelNotCalled = 'not_called';
const kLabelCalledToday = 'called_today';
const kLabelFollowUp = 'follow_up';
const kLabelProductive = 'productive';
const kLabelWrongNumber = 'wrong_number';
const kLabelDoNotCall = 'do_not_call';

const kWorklistLabels = <String, ({String text, Color color})>{
  kLabelNotCalled: (text: 'Pending', color: Color(0xFF757575)),
  kLabelCalledToday: (text: 'Called', color: Color(0xFF43A047)),
  kLabelFollowUp: (text: 'Follow-up Due', color: Color(0xFFFB8C00)),
  kLabelProductive: (text: 'Productive', color: Color(0xFF2F9E57)),
  kLabelWrongNumber: (text: 'Wrong Number', color: Color(0xFFE53935)),
  kLabelDoNotCall: (text: 'Do Not Call', color: Color(0xFF212121)),
};

/// Style for a worklist label key, falling back to a neutral grey.
({String text, Color color}) worklistLabelStyle(String key) =>
    kWorklistLabels[key] ?? (text: key, color: const Color(0xFF757575));

// ── Unified visit / call status styling ─────────────────────────────────────
// One palette shared by the salesman Beat Plan (pending / visited / revisit /
// productive) and the telecaller Worklist (pending / called / follow-up /
// productive). Each status maps to one hue used for the status chip AND the
// whole card (tinted background + matching border), so a glance down the list
// reads as colour-coded:
//   • pending  → slate grey  (not started)
//   • visited / called → blue (contacted today)
//   • revisit / follow-up → amber (needs another touch)
//   • productive → green (order placed — best outcome)
typedef StatusStyle = ({
  String text,
  Color accent,   // chip text + border, strong colour
  Color chipBg,   // chip fill
  Color cardBg,   // card background tint
  Color cardBorder,
});

const _kStatusStyles = <String, StatusStyle>{
  'pending': (
    text: 'Pending',
    accent: Color(0xFF5B6B7F),
    chipBg: Color(0xFFEDF1F6),
    cardBg: Color(0xFFEEF2F7),
    cardBorder: Color(0xFFCED8E4),
  ),
  'visited': (
    text: 'Visited',
    accent: Color(0xFF1D66C2),
    chipBg: Color(0xFFE3F0FD),
    cardBg: Color(0xFFEFF6FF),
    cardBorder: Color(0xFFBBD7F5),
  ),
  'called': (
    text: 'Called',
    accent: Color(0xFF1D66C2),
    chipBg: Color(0xFFE3F0FD),
    cardBg: Color(0xFFEFF6FF),
    cardBorder: Color(0xFFBBD7F5),
  ),
  'revisit': (
    text: 'Revisit',
    accent: Color(0xFFD97706),
    chipBg: Color(0xFFFEF1E0),
    cardBg: Color(0xFFFFF9F1),
    cardBorder: Color(0xFFF7D9AE),
  ),
  'followup': (
    text: 'Follow-up',
    accent: Color(0xFFD97706),
    chipBg: Color(0xFFFEF1E0),
    cardBg: Color(0xFFFFF9F1),
    cardBorder: Color(0xFFF7D9AE),
  ),
  'productive': (
    text: 'Productive',
    accent: Color(0xFF2E7D32),
    chipBg: Color(0xFFE6F4EA),
    cardBg: Color(0xFFF1F9F2),
    cardBorder: Color(0xFFA9D8B0),
  ),
};

/// Canonical status style for any salesman/telecaller status key. Accepts both
/// vocabularies — server label keys (`not_called`, `called_today`, `follow_up`)
/// and the plain salesman keys (`pending`, `visited`, `revisit`, `productive`).
StatusStyle statusStyle(String? key) {
  switch ((key ?? '').toLowerCase().trim()) {
    case 'productive':
      return _kStatusStyles['productive']!;
    case 'visited':
      return _kStatusStyles['visited']!;
    case 'called':
    case 'called_today':
      return _kStatusStyles['called']!;
    case 'revisit':
      return _kStatusStyles['revisit']!;
    case 'followup':
    case 'follow_up':
      return _kStatusStyles['followup']!;
    case 'pending':
    case 'not_called':
    default:
      return _kStatusStyles['pending']!;
  }
}

// ── Pipeline / customer-stage styling (matches LeadsAccount.customerStage) ────
const kStageStyles = <String, ({String text, Color color})>{
  'lead':        (text: 'Lead',        color: Color(0xFF5A6472)),
  'prospect':    (text: 'Prospect',    color: Color(0xFF3B6FD4)),
  'qualified':   (text: 'Qualified',   color: Color(0xFFD98A2B)),
  'opportunity': (text: 'Opportunity', color: Color(0xFF7C5CD6)),
  'customer':    (text: 'Customer',    color: Color(0xFF2F9E57)),
  'churned':     (text: 'Churned',     color: Color(0xFFC0584C)),
};

/// Display style for a customer-stage key, falling back to neutral grey.
({String text, Color color}) stageStyle(String? key) {
  final k = (key ?? '').toLowerCase().trim();
  return kStageStyles[k] ??
      (text: k.isEmpty ? 'Lead' : k[0].toUpperCase() + k.substring(1), color: const Color(0xFF5A6472));
}

/// Rough pipeline-progress (0–100) for the stage ring. Honest: reflects how far
/// along the funnel the account is, not an invented lead "score".
int stageProgress(String? key) {
  switch ((key ?? '').toLowerCase().trim()) {
    case 'prospect':    return 40;
    case 'qualified':   return 60;
    case 'opportunity': return 80;
    case 'customer':    return 95;
    case 'churned':     return 30;
    default:            return 20; // lead / unknown
  }
}

/// Derived "temperature" from stage (placeholder until real lead scoring exists).
({String text, Color color}) tempForStage(String? key) {
  switch ((key ?? '').toLowerCase().trim()) {
    case 'opportunity':
    case 'qualified':
      return (text: 'Hot', color: const Color(0xFFC0584C));
    case 'prospect':
    case 'customer':
      return (text: 'Warm', color: const Color(0xFFD98A2B));
    default:
      return (text: 'Cold', color: const Color(0xFF5A6472));
  }
}

/// Derived priority from stage (placeholder until a real priority field exists).
({String text, Color color}) priorityForStage(String? key) {
  switch ((key ?? '').toLowerCase().trim()) {
    case 'opportunity':
    case 'qualified':
      return (text: 'High', color: const Color(0xFFC0584C));
    case 'prospect':
      return (text: 'Medium', color: const Color(0xFFD98A2B));
    default:
      return (text: 'Low', color: const Color(0xFF5A6472));
  }
}

// ── Orders (mockup-style create-order sheet + history) ───────────────────────
const kOrderStatusColors = <String, Color>{
  'Draft':            Color(0xFF5A6472),
  'Pending Approval': Color(0xFFD98A2B),
  'Confirmed':        Color(0xFF7C5CD6),
  'Processing':       Color(0xFFD98A2B),
  'Packed':           Color(0xFF3B6FD4),
  'Shipped':          Color(0xFF3B6FD4),
  'Delivered':        Color(0xFF2F9E57),
  'Cancelled':        Color(0xFFC0584C),
};

const kOrderStatusOptions = <String>[
  'Draft', 'Pending Approval', 'Confirmed', 'Processing', 'Packed', 'Shipped', 'Delivered',
];

const kPaymentOptions = <String>['Paid', 'Partial', 'Pending'];

// ── Avatars ──────────────────────────────────────────────────────────────────
const kAvatarColors = <Color>[
  Color(0xFFD2AB5B), Color(0xFF3B6FD4), Color(0xFF2F9E57),
  Color(0xFF7C5CD6), Color(0xFFD98A2B), Color(0xFFC0584C),
];

/// Deterministic avatar colour for a seed (name or id) — stable across rebuilds.
Color avatarColorFor(String seed) {
  if (seed.isEmpty) return kAvatarColors.first;
  var h = 0;
  for (final c in seed.codeUnits) {
    h = (h + c) % kAvatarColors.length;
  }
  return kAvatarColors[h];
}

/// Up-to-two-letter initials from a display name.
String initialsOf(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
  return (parts.first[0] + parts.last[0]).toUpperCase();
}

/// ₹ amount with Indian digit grouping (e.g. 142500 → ₹1,42,500).
String money(num? amount) {
  final n = (amount ?? 0).round();
  final neg = n < 0;
  var s = n.abs().toString();
  if (s.length > 3) {
    final last3 = s.substring(s.length - 3);
    var rest = s.substring(0, s.length - 3);
    final groups = <String>[];
    while (rest.length > 2) {
      groups.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) groups.insert(0, rest);
    s = '${groups.join(',')},$last3';
  }
  return '${neg ? '-' : ''}₹$s';
}

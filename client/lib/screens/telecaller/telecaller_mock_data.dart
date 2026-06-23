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
};

const kOutcomeLabels = <String, String>{
  'answered': 'Answered',
  'busy': 'Busy',
  'no_answer': 'No Answer',
  'switch_off': 'Switched Off',
  'invalid': 'Invalid',
  'callback': 'Callback',
};

// ── Worklist labels (match server-derived / custom label keys) ───────────────
const kLabelNotCalled = 'not_called';
const kLabelCalledToday = 'called_today';
const kLabelFollowUp = 'follow_up';
const kLabelWrongNumber = 'wrong_number';
const kLabelDoNotCall = 'do_not_call';

const kWorklistLabels = <String, ({String text, Color color})>{
  kLabelNotCalled: (text: 'Not Called', color: Color(0xFF757575)),
  kLabelCalledToday: (text: 'Called Today', color: Color(0xFF43A047)),
  kLabelFollowUp: (text: 'Follow-up Due', color: Color(0xFFFB8C00)),
  kLabelWrongNumber: (text: 'Wrong Number', color: Color(0xFFE53935)),
  kLabelDoNotCall: (text: 'Do Not Call', color: Color(0xFF212121)),
};

/// Style for a worklist label key, falling back to a neutral grey.
({String text, Color color}) worklistLabelStyle(String key) =>
    kWorklistLabels[key] ?? (text: key, color: const Color(0xFF757575));

import 'package:flutter/material.dart';

/// Date-window presets shared by Call History and the Team Call History agent
/// roster.
///
/// The roster sends the window to the server (so each agent's call counts are
/// for that window) and hands the same window to the history screen it opens,
/// which filters its already-loaded rows client-side. Keeping one definition
/// means the count on the agent card and the number of rows behind it can't
/// drift apart.
enum CallDateFilter { all, today, yesterday, week, month, custom }

const callDateFilterLabels = <CallDateFilter, String>{
  CallDateFilter.all: 'All time',
  CallDateFilter.today: 'Today',
  CallDateFilter.yesterday: 'Yesterday',
  CallDateFilter.week: 'Last 7 days',
  CallDateFilter.month: 'Last 30 days',
  CallDateFilter.custom: 'Custom range',
};

String fmtDay(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

/// Label for the "active filter" chip — spells out a custom range.
String callDateChipLabel(CallDateFilter filter, DateTimeRange? customRange) =>
    filter == CallDateFilter.custom && customRange != null
        ? '${fmtDay(customRange.start)} - ${fmtDay(customRange.end)}'
        : callDateFilterLabels[filter]!;

/// The concrete local-day span a preset resolves to right now, or null for
/// "all time" (and for a custom preset with no range picked yet).
DateTimeRange? callDateRange(CallDateFilter filter, DateTimeRange? customRange) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  switch (filter) {
    case CallDateFilter.all:
      return null;
    case CallDateFilter.today:
      return DateTimeRange(start: today, end: today);
    case CallDateFilter.yesterday:
      final y = today.subtract(const Duration(days: 1));
      return DateTimeRange(start: y, end: y);
    case CallDateFilter.week:
      return DateTimeRange(start: today.subtract(const Duration(days: 6)), end: today);
    case CallDateFilter.month:
      return DateTimeRange(start: today.subtract(const Duration(days: 29)), end: today);
    case CallDateFilter.custom:
      if (customRange == null) return null;
      return DateTimeRange(
        start: DateTime(customRange.start.year, customRange.start.month, customRange.start.day),
        end: DateTime(customRange.end.year, customRange.end.month, customRange.end.day),
      );
  }
}

/// `Y-m-d` bounds for the server's `?from=&to=` stats window — plain local days,
/// which is what the backend expects (call_log_crm.called_at stores naive IST
/// wall-clock, so sending a UTC instant would clip the edges of the range).
String? _ymd(DateTime? d) => d == null
    ? null
    : '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

({String? from, String? to}) callDateRangeYmd(
  CallDateFilter filter,
  DateTimeRange? customRange,
) {
  final range = callDateRange(filter, customRange);
  return (from: _ymd(range?.start), to: _ymd(range?.end));
}

/// True when a server timestamp falls inside the window. Parses the full
/// ISO-8601 string and converts to local — never substring it, the wire format
/// carries an offset.
bool callDateMatches(CallDateFilter filter, DateTimeRange? customRange, String? iso) {
  final range = callDateRange(filter, customRange);
  if (range == null) return true;
  final dt = (iso == null || iso.isEmpty) ? null : DateTime.tryParse(iso)?.toLocal();
  if (dt == null) return false;
  final day = DateTime(dt.year, dt.month, dt.day);
  return !day.isBefore(range.start) && !day.isAfter(range.end);
}

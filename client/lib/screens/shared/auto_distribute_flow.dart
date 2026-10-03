import 'package:flutter/material.dart';

import 'auto_distribute_dialog.dart';

const _kWeekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// The two-popup "select N → Auto-Distribute" flow shared by the Allotted
/// Customer screen and the Today Worklist:
///   1. [AutoDistributeDialog] — pick From and To dates;
///   2. [AutoDistributeDaysDialog] — pick which weekdays count (Mon–Sun or All).
/// Returns a map with `start_date` (YYYY-MM-DD), either `end_date` (range mode)
/// or `days` (N-days mode), and `weekdays` (a list of short names Mon..Sun; all
/// seven when "All days" is on), or null if the user cancelled at either step.
Future<Map<String, dynamic>?> showAutoDistributeFlow(BuildContext context, int selectedCount) async {
  final dates = await showDialog<Map<String, dynamic>>(
    context: context,
    barrierDismissible: false,
    builder: (_) => AutoDistributeDialog(selectedCount: selectedCount),
  );
  if (dates == null || !context.mounted) return null;

  final weekdays = await showDialog<List<String>>(
    context: context,
    barrierDismissible: false,
    builder: (_) => AutoDistributeDaysDialog(
      selectedCount: selectedCount,
      startDate: DateTime.parse('${dates['start_date']}'),
      endDate: dates['end_date'] == null ? null : DateTime.parse('${dates['end_date']}'),
      days: dates['days'] as int?,
    ),
  );
  if (weekdays == null) return null;

  return {...dates, 'weekdays': weekdays};
}

/// Step 2: choose the weekdays. Only these days receive customers, in even
/// consecutive blocks — those inside the From–To range ([endDate]), or the
/// first [days] matching days counted from [startDate] ("N days" mode).
class AutoDistributeDaysDialog extends StatefulWidget {
  final int selectedCount;
  final DateTime startDate;
  final DateTime? endDate;
  final int? days;
  const AutoDistributeDaysDialog({
    super.key,
    required this.selectedCount,
    required this.startDate,
    this.endDate,
    this.days,
  });

  @override
  State<AutoDistributeDaysDialog> createState() => _AutoDistributeDaysDialogState();
}

class _AutoDistributeDaysDialogState extends State<AutoDistributeDaysDialog> {
  static const _gold = Color(0xFFD7BE69);

  // All days on by default; the telecaller narrows it down.
  final Set<String> _picked = {..._kWeekdays};

  bool get _all => _picked.length == _kWeekdays.length;

  /// The dates that will receive customers (same rule as the server):
  /// range mode → days in startDate..endDate on a picked weekday;
  /// N-days mode → the first N days from startDate on a picked weekday.
  /// (DateTime.weekday: 1=Mon..7=Sun.)
  List<DateTime> get _dates {
    final out = <DateTime>[];
    if (_picked.isEmpty) return out;
    final n = widget.days;
    var d = widget.startDate;
    if (n != null) {
      // At most one week of scanning per wanted date (a single weekday ticked).
      for (var i = 0; out.length < n && i < n * 7 + 7; i++, d = d.add(const Duration(days: 1))) {
        if (_picked.contains(_kWeekdays[d.weekday - 1])) out.add(d);
      }
    } else {
      for (; !d.isAfter(widget.endDate!); d = d.add(const Duration(days: 1))) {
        if (_picked.contains(_kWeekdays[d.weekday - 1])) out.add(d);
      }
    }
    return out;
  }

  static String _label(DateTime d) {
    const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${d.day} ${m[d.month - 1]}';
  }

  @override
  Widget build(BuildContext context) {
    final dates = _dates;
    final days = dates.length;
    final canSubmit = _picked.isNotEmpty && days > 0;
    final perDay = days > 0 ? (widget.selectedCount / days).ceil() : 0;
    final pickedNames = _kWeekdays.where(_picked.contains).join(', ');
    // "4 Mon · 4 Fri" — how the chosen days spread over the dates.
    final perWeekday = [
      for (final w in _kWeekdays)
        if (dates.any((d) => _kWeekdays[d.weekday - 1] == w))
          '${dates.where((d) => _kWeekdays[d.weekday - 1] == w).length} $w',
    ].join(' · ');
    final rangeText = widget.days != null
        ? '${_label(widget.startDate)} → ${days > 0 ? _label(dates.last) : '…'} (${widget.days} days)'
        : '${_label(widget.startDate)} to ${_label(widget.endDate!)}';

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Expanded(
                child: Text('Select days', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _gold.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text('${widget.selectedCount} accounts',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _gold)),
              ),
            ]),
            const SizedBox(height: 4),
            Text(
              'Step 2 of 2 — $rangeText. Only the days you tick get customers.',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                FilterChip(
                  label: const Text('All days'),
                  selected: _all,
                  selectedColor: _gold.withValues(alpha: 0.35),
                  checkmarkColor: Colors.black87,
                  onSelected: (v) => setState(() {
                    _picked
                      ..clear()
                      ..addAll(v ? _kWeekdays : const <String>[]);
                  }),
                ),
                for (final d in _kWeekdays)
                  FilterChip(
                    label: Text(d),
                    selected: _picked.contains(d),
                    selectedColor: _gold.withValues(alpha: 0.35),
                    checkmarkColor: Colors.black87,
                    onSelected: (v) => setState(() => v ? _picked.add(d) : _picked.remove(d)),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                _picked.isEmpty
                    ? 'Tick at least one day.'
                    : days == 0
                        ? 'None of the ticked days ($pickedNames) falls between these dates.'
                        : '${widget.selectedCount} customers over $days day(s)'
                            '${_all ? '' : ' ($perWeekday)'}'
                            '${widget.days != null ? ', ${_label(dates.first)} → ${_label(dates.last)}' : ''}'
                            ' ≈ $perDay per day',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: canSubmit ? Colors.black87 : Colors.red.shade700,
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: canSubmit
                      ? () => Navigator.pop(context, _kWeekdays.where(_picked.contains).toList())
                      : null,
                  style: ElevatedButton.styleFrom(backgroundColor: _gold),
                  child: const Text('Distribute', style: TextStyle(color: Colors.white)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

/// Bottom sheet for the telecaller's geographic daily calling plan: pick
/// pincodes (or Select All) and a From–To date range. The customers are
/// divided over those days (every calendar day counts) and re-divided each
/// morning by the server. Pincodes already in the active plan stay ticked and
/// can't be removed — new ones are merged in; on an update the From date is
/// fixed and only the To date can move.
/// Pops with `(pincodes, start, end)` or null.
class DailyPlanSheet extends StatefulWidget {
  const DailyPlanSheet({
    super.key,
    required this.pincodes,
    required this.inPlan,
    this.planStart,
    this.planEnd,
    this.pendingInPlan = 0,
  });

  final List<({String pincode, int count})> pincodes;
  final Set<String> inPlan;
  final DateTime? planStart; // active plan's From date (locked on update)
  final DateTime? planEnd;
  final int pendingInPlan; // accounts still open in the active plan

  @override
  State<DailyPlanSheet> createState() => _DailyPlanSheetState();
}

class _DailyPlanSheetState extends State<DailyPlanSheet> {
  static const _gold = Color(0xFFD7BE69);

  late final Set<String> _picked = {...widget.inPlan};
  late DateTime? _start = widget.planStart;
  late DateTime? _end = widget.planEnd;

  bool get _isUpdate => widget.inPlan.isNotEmpty;

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);
  static String _ymd(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  static String _label(DateTime d) {
    const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${d.day} ${m[d.month - 1]} ${d.year}';
  }

  List<String> get _selectable =>
      widget.pincodes.map((p) => p.pincode).where((p) => !widget.inPlan.contains(p)).toList();

  Future<void> _pickRange() async {
    final today = _day(DateTime.now());
    if (_isUpdate) {
      // From date is fixed on a running plan — only the To date moves.
      final start = _day(widget.planStart ?? today);
      final first = start.isAfter(today) ? start : today;
      final initial = _end != null && !_end!.isBefore(first) ? _end! : first;
      final picked = await showDatePicker(
        context: context,
        firstDate: first,
        lastDate: start.add(const Duration(days: 365)),
        initialDate: initial,
        helpText: 'Select To date',
      );
      if (picked != null) setState(() => _end = _day(picked));
      return;
    }
    final picked = await showDateRangePicker(
      context: context,
      firstDate: today,
      lastDate: today.add(const Duration(days: 365)),
      initialDateRange: _start != null && _end != null ? DateTimeRange(start: _start!, end: _end!) : null,
      helpText: 'Select From – To dates',
    );
    if (picked != null) {
      setState(() {
        _start = _day(picked.start);
        _end = _day(picked.end);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final pickedAccounts =
        widget.pincodes.where((p) => _picked.contains(p.pincode)).fold(0, (s, p) => s + p.count);
    final selectable = _selectable;
    final allPicked = selectable.every(_picked.contains);

    // Preview of the split: accounts ÷ days. On an update the days counted
    // are today..To (or From..To if the plan hasn't started) and the
    // accounts are what's still open plus the newly added pincodes.
    final today = _day(DateTime.now());
    final from = _start == null ? null : (_isUpdate && _start!.isBefore(today) ? today : _start!);
    final days = (from != null && _end != null) ? _end!.difference(from).inDays + 1 : 0;
    final newAccounts = widget.pincodes
        .where((p) => _picked.contains(p.pincode) && !widget.inPlan.contains(p.pincode))
        .fold(0, (s, p) => s + p.count);
    final toDivide = _isUpdate ? widget.pendingInPlan + newAccounts : pickedAccounts;
    final perDay = days > 0 ? (toDivide / days).ceil() : 0;
    final canSubmit = _start != null && _end != null && days > 0 && _picked.isNotEmpty;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text(_isUpdate ? 'Update Daily Plan' : 'Create Daily Plan',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text('Customers are divided over the days you pick. Pincodes are ordered by location.',
                  style: TextStyle(fontSize: 12, color: Colors.black54)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: InkWell(
                onTap: _pickRange,
                borderRadius: BorderRadius.circular(10),
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: _isUpdate ? 'From (fixed) – To' : 'From – To',
                    isDense: true,
                    prefixIcon: const Icon(Icons.date_range_rounded, color: _gold),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: Text(
                    _start == null || _end == null
                        ? 'Tap to pick dates'
                        : '${_label(_start!)}  →  ${_label(_end!)}',
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
              ),
            ),
            if (days > 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: Text(
                  '$toDivide customers ÷ $days day(s) ≈ $perDay per day',
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Color(0xFF8A6D1F)),
                ),
              ),
            CheckboxListTile(
              dense: true,
              activeColor: _gold,
              title: const Text('Select All', style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text('${_picked.length} of ${widget.pincodes.length} pincodes · $pickedAccounts accounts'),
              value: allPicked,
              onChanged: selectable.isEmpty
                  ? null
                  : (v) => setState(() => v == true ? _picked.addAll(selectable) : _picked.removeAll(selectable)),
            ),
            const Divider(height: 1),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final p in widget.pincodes)
                    CheckboxListTile(
                      dense: true,
                      activeColor: _gold,
                      title: Text(p.pincode),
                      subtitle: Text(widget.inPlan.contains(p.pincode)
                          ? '${p.count} accounts · in plan'
                          : '${p.count} accounts'),
                      value: _picked.contains(p.pincode),
                      onChanged: widget.inPlan.contains(p.pincode)
                          ? null
                          : (v) => setState(() => v == true ? _picked.add(p.pincode) : _picked.remove(p.pincode)),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: ElevatedButton(
                onPressed: canSubmit
                    ? () => Navigator.pop(context, (pincodes: _picked.toList(), start: _ymd(_start!), end: _ymd(_end!)))
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _gold,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: Text(_isUpdate ? 'Save Plan' : 'Create Plan'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

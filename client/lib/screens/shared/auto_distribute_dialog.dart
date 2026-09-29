import 'package:flutter/material.dart';

/// Shared "select N → auto-distribute over a date range" dialog, used by both
/// the salesman Beat Plan screen and the telecaller Worklist screen. Returns
/// {'start_date': 'YYYY-MM-DD', 'end_date': 'YYYY-MM-DD'} on confirm, or null
/// on cancel.
class AutoDistributeDialog extends StatefulWidget {
  final int selectedCount;
  const AutoDistributeDialog({super.key, required this.selectedCount});

  @override
  State<AutoDistributeDialog> createState() => _AutoDistributeDialogState();
}

class _AutoDistributeDialogState extends State<AutoDistributeDialog> {
  static const _gold = Color(0xFFD7BE69);

  DateTime? _startDate;
  DateTime? _endDate;

  int get _dayCount {
    if (_startDate == null || _endDate == null) return 0;
    return _endDate!.difference(_startDate!).inDays + 1;
  }

  bool get _canSubmit => _startDate != null && _endDate != null && !_endDate!.isBefore(_startDate!);

  Future<void> _pickDate({required bool isStart}) async {
    final initial = isStart
        ? (_startDate ?? DateTime.now())
        : (_endDate ?? _startDate ?? DateTime.now());
    final firstDate = isStart ? DateTime.now() : (_startDate ?? DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(firstDate) ? firstDate : initial,
      firstDate: firstDate,
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(primary: _gold),
        ),
        child: child!,
      ),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _startDate = picked;
        if (_endDate != null && _endDate!.isBefore(picked)) _endDate = null;
      } else {
        _endDate = picked;
      }
    });
  }

  String _fmt(DateTime? d) {
    if (d == null) return 'Select date';
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  void _submit() {
    if (!_canSubmit) return;
    Navigator.pop(context, {
      'start_date': _fmt(_startDate),
      'end_date': _fmt(_endDate),
    });
  }

  @override
  Widget build(BuildContext context) {
    final perDay = _dayCount > 0 ? (widget.selectedCount / _dayCount) : 0;
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
              const Text('Auto-Distribute',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const Spacer(),
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
              'Spreads the selected accounts evenly, round-robin, across every day in the chosen range.',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
            const SizedBox(height: 16),

            _DatePickButton(label: 'Start date', value: _fmt(_startDate), onTap: () => _pickDate(isStart: true)),
            const SizedBox(height: 10),
            _DatePickButton(label: 'End date', value: _fmt(_endDate), onTap: () => _pickDate(isStart: false)),

            if (_dayCount > 0) ...[
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${widget.selectedCount} customers over $_dayCount day(s) ≈ ${perDay.toStringAsFixed(1)} per day',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
            ],

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
                  onPressed: _canSubmit ? _submit : null,
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

class _DatePickButton extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onTap;
  const _DatePickButton({required this.label, required this.value, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                  Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            const Icon(Icons.calendar_today, size: 18, color: Colors.grey),
          ],
        ),
      ),
    );
  }
}

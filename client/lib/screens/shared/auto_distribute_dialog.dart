import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Step 1 of the shared "select N → auto-distribute" flow (see
/// auto_distribute_flow.dart): pick the From date and either a To date
/// ("Date range") or a number of days ("N days" — counted only on the weekdays
/// chosen in step 2, so Mon + Fri with N = 8 means 4 Mondays and 4 Fridays).
/// Step 2 then asks which weekdays count.
///
/// Returns on Next: `{'start_date': 'YYYY-MM-DD', 'end_date': 'YYYY-MM-DD'}`
/// in range mode, or `{'start_date': 'YYYY-MM-DD', 'days': N}` in N-days mode.
/// Returns null on cancel.
class AutoDistributeDialog extends StatefulWidget {
  final int selectedCount;
  const AutoDistributeDialog({super.key, required this.selectedCount});

  @override
  State<AutoDistributeDialog> createState() => _AutoDistributeDialogState();
}

class _AutoDistributeDialogState extends State<AutoDistributeDialog> {
  static const _gold = Color(0xFFD7BE69);
  static const _maxDays = 366;

  DateTime? _startDate;
  DateTime? _endDate;
  bool _byCount = false; // false = From–To range, true = From + N days
  final _daysCtrl = TextEditingController();

  int? get _nDays {
    final n = int.tryParse(_daysCtrl.text.trim());
    return n != null && n >= 1 && n <= _maxDays ? n : null;
  }

  int get _dayCount {
    if (_startDate == null || _endDate == null) return 0;
    return _endDate!.difference(_startDate!).inDays + 1;
  }

  bool get _canSubmit => _startDate != null &&
      (_byCount ? _nDays != null : (_endDate != null && !_endDate!.isBefore(_startDate!)));

  @override
  void dispose() {
    _daysCtrl.dispose();
    super.dispose();
  }

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
      if (_byCount) 'days': _nDays else 'end_date': _fmt(_endDate),
    });
  }

  Widget _modeChip(String label, bool byCount) => ChoiceChip(
        label: Text(label),
        selected: _byCount == byCount,
        selectedColor: _gold.withValues(alpha: 0.35),
        onSelected: (_) => setState(() => _byCount = byCount),
      );

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
      child: SingleChildScrollView(
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
              'Step 1 of 2 — choose the start and how long. Next you pick which weekdays count.',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
            const SizedBox(height: 14),
            Wrap(spacing: 8, children: [
              _modeChip('Date range', false),
              _modeChip('N days', true),
            ]),
            const SizedBox(height: 12),

            _DatePickButton(label: _byCount ? 'From date' : 'Start date', value: _fmt(_startDate), onTap: () => _pickDate(isStart: true)),
            const SizedBox(height: 10),
            if (_byCount) ...[
              TextField(
                controller: _daysCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(3)],
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'Number of days (N)',
                  helperText: 'Counted only on the weekdays you pick next, e.g. Mon + Fri with 8 = 4 Mondays + 4 Fridays.',
                  helperMaxLines: 3,
                  errorText: _daysCtrl.text.isNotEmpty && _nDays == null ? 'Enter 1 to $_maxDays' : null,
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: _gold, width: 2),
                  ),
                ),
              ),
            ] else ...[
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
                    '$_dayCount day(s) in this range',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
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
                  child: const Text('Next', style: TextStyle(color: Colors.white)),
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

import 'package:flutter/material.dart';

/// Bottom sheet for the telecaller's geographic daily calling plan: pick
/// pincodes (or Select All) and a daily capacity. Pincodes already in the
/// active plan stay ticked and can't be removed — new ones are merged in.
/// Pops with `(pincodes, capacity)` or null.
class DailyPlanSheet extends StatefulWidget {
  const DailyPlanSheet({super.key, required this.pincodes, required this.inPlan, required this.initialCapacity});

  final List<({String pincode, int count})> pincodes;
  final Set<String> inPlan;
  final int initialCapacity;

  @override
  State<DailyPlanSheet> createState() => _DailyPlanSheetState();
}

class _DailyPlanSheetState extends State<DailyPlanSheet> {
  static const _gold = Color(0xFFD7BE69);

  late final Set<String> _picked = {...widget.inPlan};
  late final _capCtrl = TextEditingController(text: '${widget.initialCapacity}');

  List<String> get _selectable =>
      widget.pincodes.map((p) => p.pincode).where((p) => !widget.inPlan.contains(p)).toList();

  @override
  void dispose() {
    _capCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cap = int.tryParse(_capCtrl.text.trim()) ?? 0;
    final pickedAccounts =
        widget.pincodes.where((p) => _picked.contains(p.pincode)).fold(0, (s, p) => s + p.count);
    final isUpdate = widget.inPlan.isNotEmpty;
    final selectable = _selectable;
    final allPicked = selectable.every(_picked.contains);

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
              child: Text(isUpdate ? 'Update Daily Plan' : 'Create Daily Plan',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text('Pincodes are ordered by actual location, not by number.',
                  style: TextStyle(fontSize: 12, color: Colors.black54)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: TextField(
                controller: _capCtrl,
                keyboardType: TextInputType.number,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'Customers per day (daily capacity)',
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: _gold, width: 2),
                  ),
                ),
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
                onPressed: cap > 0 && _picked.isNotEmpty
                    ? () => Navigator.pop(context, (pincodes: _picked.toList(), capacity: cap))
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _gold,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: Text(isUpdate ? 'Save Plan' : 'Create Plan'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

/// Unit picker for a Sales Order line item.
///
/// Deliberately a bottom sheet rather than a DropdownButton menu: the Unit
/// field sits in a narrow three-column row (Qty | Unit | Unit Price), and a
/// dropdown menu anchors itself so the *selected* item lands on the field —
/// which, once units_master grew to ~20 entries, made the menu climb upward and
/// cover the form. A sheet always opens from the bottom, fits every unit at
/// once, and gives a proper touch target.
Future<String?> showUnitPickerSheet(
  BuildContext context, {
  required List<String> units,
  String? selected,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _UnitPickerSheet(units: units, selected: selected),
  );
}

class _UnitPickerSheet extends StatelessWidget {
  final List<String> units;
  final String? selected;

  const _UnitPickerSheet({required this.units, this.selected});

  static const _gold = Color(0xFFD7BE69);
  static const _goldDark = Color(0xFFC09E3E);

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.6,
      ),
      padding: EdgeInsets.fromLTRB(
          18, 8, 18, 16 + MediaQuery.of(context).padding.bottom),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 42,
              height: 4,
              margin: const EdgeInsets.only(top: 8, bottom: 16),
              decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(3)),
            ),
          ),
          const Text('Select Unit',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text('From the unit master',
              style: TextStyle(fontSize: 11.5, color: Colors.grey.shade500)),
          const SizedBox(height: 14),
          Flexible(
            child: SingleChildScrollView(
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: units.map((u) {
                  final isSelected = u == selected;
                  return GestureDetector(
                    onTap: () => Navigator.of(context).pop(u),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 11),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? _gold.withValues(alpha: 0.16)
                            : const Color(0xFFFAFAFA),
                        borderRadius: BorderRadius.circular(11),
                        border: Border.all(
                            color: isSelected
                                ? _gold
                                : const Color(0xFFE7E7E7),
                            width: isSelected ? 1.4 : 1),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isSelected) ...[
                            const Icon(Icons.check_rounded,
                                size: 15, color: _goldDark),
                            const SizedBox(width: 5),
                          ],
                          Text(
                            u,
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight:
                                  isSelected ? FontWeight.w800 : FontWeight.w600,
                              color: isSelected
                                  ? _goldDark
                                  : const Color(0xFF20242B),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

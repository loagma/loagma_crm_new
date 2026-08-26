import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Quantity picker for a catalog pack — a grid of tappable numbers (1..N)
/// plus a custom-entry field for anything larger, capped at [maxQty] (the
/// pack's live stock). Mirrors [showUnitPickerSheet]'s sheet-not-dropdown
/// reasoning: a grid gives every common quantity a single tap and a proper
/// touch target, instead of typing into a bare number field.
Future<int?> showQuantityPickerSheet(
  BuildContext context, {
  required String productName,
  required String packLabel,
  required int currentQty,
  required int maxQty,
}) {
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _QuantityPickerSheet(
      productName: productName,
      packLabel: packLabel,
      currentQty: currentQty,
      maxQty: maxQty,
    ),
  );
}

class _QuantityPickerSheet extends StatefulWidget {
  final String productName;
  final String packLabel;
  final int currentQty;
  final int maxQty;

  const _QuantityPickerSheet({
    required this.productName,
    required this.packLabel,
    required this.currentQty,
    required this.maxQty,
  });

  @override
  State<_QuantityPickerSheet> createState() => _QuantityPickerSheetState();
}

class _QuantityPickerSheetState extends State<_QuantityPickerSheet> {
  static const _gold = Color(0xFFD7BE69);
  static const _ink = Color(0xFF20242B);

  late final int _selected = widget.currentQty.clamp(1, widget.maxQty > 0 ? widget.maxQty : 1);
  late final _customCtrl = TextEditingController();

  // A fixed grid up to 20 covers the overwhelming majority of real orders;
  // anything beyond that goes through the custom-entry field instead of an
  // ever-scrolling grid.
  static const _gridMax = 20;

  bool get _outOfStock => widget.maxQty <= 0;

  @override
  void dispose() {
    _customCtrl.dispose();
    super.dispose();
  }

  void _confirmCustom() {
    final v = int.tryParse(_customCtrl.text.trim());
    if (v == null || v < 1) return;
    Navigator.of(context).pop(v.clamp(1, widget.maxQty));
  }

  @override
  Widget build(BuildContext context) {
    final gridCount = widget.maxQty > 0 ? widget.maxQty.clamp(1, _gridMax) : 0;

    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
      padding: EdgeInsets.fromLTRB(18, 8, 18, 16 + MediaQuery.of(context).padding.bottom),
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
              decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(3)),
            ),
          ),
          const Text('Select Quantity', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: _ink)),
          const SizedBox(height: 4),
          Text.rich(
            TextSpan(children: [
              TextSpan(text: '${widget.productName}\n', style: const TextStyle(fontWeight: FontWeight.w600, color: _ink)),
              TextSpan(text: 'Pack: ${widget.packLabel}'),
            ]),
            style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
          ),
          const SizedBox(height: 4),
          Text(
            _outOfStock ? 'Out of stock' : 'In stock: ${widget.maxQty}',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: _outOfStock ? const Color(0xFFC0584C) : const Color(0xFF2F9E57),
            ),
          ),
          const SizedBox(height: 14),
          if (_outOfStock)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Text('No stock available for this pack right now.',
                    style: TextStyle(fontSize: 12.5, color: Colors.grey.shade500)),
              ),
            )
          else ...[
            Flexible(
              child: SingleChildScrollView(
                child: GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: gridCount,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 5,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    childAspectRatio: 1,
                  ),
                  itemBuilder: (context, i) {
                    final n = i + 1;
                    final isSelected = n == _selected;
                    return GestureDetector(
                      onTap: () => Navigator.of(context).pop(n),
                      child: Container(
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: isSelected ? _gold : const Color(0xFFF6F6F7),
                          borderRadius: BorderRadius.circular(9),
                          border: Border.all(color: isSelected ? _gold : const Color(0xFFE7E7E7)),
                        ),
                        child: Text(
                          '$n',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: isSelected ? Colors.white : _ink,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            if (widget.maxQty > _gridMax) ...[
              const SizedBox(height: 14),
              Text('Or enter a quantity up to ${widget.maxQty}',
                  style: TextStyle(fontSize: 11.5, color: Colors.grey.shade500)),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _customCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onSubmitted: (_) => _confirmCustom(),
                    decoration: InputDecoration(
                      isDense: true,
                      filled: true,
                      fillColor: const Color(0xFFFAFAFA),
                      hintText: 'e.g. ${_gridMax + 1}',
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: const BorderSide(color: Color(0xFFE7E7E7))),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: const BorderSide(color: Color(0xFFE7E7E7))),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: const BorderSide(color: _gold, width: 1.4)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: _confirmCustom,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _gold,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
                  ),
                  child: const Text('OK', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                ),
              ]),
            ],
          ],
        ],
      ),
    );
  }
}

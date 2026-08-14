import 'package:flutter/material.dart';

import '../services/api_service.dart';
import 'product_picker_sheet.dart';
import 'unit_picker_sheet.dart';

/// Opens the "Product Detail" bottom-sheet form (same layout used by the
/// Create Sales Order screen) to add or edit one order line item. Pass
/// [initial] with an existing item's data to prefill it in edit mode; omit
/// it (or pass null) to start blank in add mode.
///
/// Returns a map with product_id, name, pack_size (hsn/pack label), quantity,
/// unit, item_price, total_tax, item_total (qty × price) and gross_amount
/// (item_total − total_tax) on Save, or null if cancelled.
Future<Map<String, dynamic>?> showOrderItemFormSheet(
  BuildContext context, {
  Map<String, dynamic>? initial,
  int itemNumber = 1,
}) {
  return showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _OrderItemFormSheet(initial: initial, itemNumber: itemNumber),
  );
}

class _OrderItemFormSheet extends StatefulWidget {
  final Map<String, dynamic>? initial;
  final int itemNumber;
  const _OrderItemFormSheet({this.initial, required this.itemNumber});

  @override
  State<_OrderItemFormSheet> createState() => _OrderItemFormSheetState();
}

class _OrderItemFormSheetState extends State<_OrderItemFormSheet> {
  static const _gold = Color(0xFFD7BE69);
  static const _goldDark = Color(0xFFC09E3E);
  // Fallback shown until units_master loads. Deliberately a subset of real
  // units_master names: a selected value that's absent from the loaded list
  // trips DropdownButton's "value must match exactly one item" assert. (The
  // old fallback had 'DOZ', which units_master spells 'DOZEN'.)
  List<String> _units = const ['PCS', 'KG', 'BOX', 'LTR', 'NOS'];

  final _productCtrl = TextEditingController();
  final _qtyCtrl = TextEditingController(text: '1');
  final _priceCtrl = TextEditingController(text: '0');
  String _unit = 'PCS';
  String? _productId;
  String? _hsnCode;
  // GST rate for the selected product, resolved server-side from product_taxes.
  // Unit price is entered tax-inclusive, so tax is extracted back out of it
  // rather than added on top — matching CreateSalesOrderSheet.
  double _gstPercent = 0;

  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    if (i != null) {
      _productCtrl.text = (i['name'] ?? '').toString();
      _qtyCtrl.text = ((i['quantity'] as num?) ?? 1).toString();
      _priceCtrl.text = ((i['item_price'] as num?) ?? 0).toStringAsFixed(2);
      _gstPercent = ((i['tax_percent'] as num?) ?? 0).toDouble();
      _unit = (i['unit'] as String?) ?? 'PCS';
      if (!_units.contains(_unit)) _units = [..._units, _unit];
      _productId = i['product_id'] as String?;
      _hsnCode = i['pack_size'] as String?;
    }
    _loadUnits();
  }

  Future<void> _loadUnits() async {
    final units = await ApiService.getUnits();
    final names = units.map((u) => (u['unit_name'] as String?) ?? '').where((u) => u.isNotEmpty).toList();
    if (!mounted || names.isEmpty) return;
    // An order saved earlier can carry any unit string in orders_item.pinfo,
    // including one units_master no longer lists — keep it as an option so
    // editing that item doesn't silently rewrite its unit (or trip the assert).
    setState(() => _units = names.contains(_unit) ? names : [...names, _unit]);
  }

  Future<void> _pickUnit() async {
    final picked = await showUnitPickerSheet(context, units: _units, selected: _unit);
    if (picked != null) setState(() => _unit = picked);
  }

  @override
  void dispose() {
    _productCtrl.dispose();
    _qtyCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  double get _qty => double.tryParse(_qtyCtrl.text.trim()) ?? 0;
  double get _price => double.tryParse(_priceCtrl.text.trim()) ?? 0;
  double get _productTotal => _qty * _price;
  double get _tax => _gstPercent > 0 ? _productTotal - _productTotal / (1 + _gstPercent / 100) : 0;
  double get _grossAmount => _productTotal - _tax;

  Future<void> _pickProduct() async {
    final picked = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const ProductPickerSheet(),
    );
    if (picked != null) {
      setState(() {
        _productCtrl.text = picked['name'] as String? ?? '';
        _productId = picked['product_id'] as String?;
        _hsnCode = picked['hsn_code'] as String?;
        _gstPercent = (picked['gst_percent'] as num?)?.toDouble() ?? 0;
      });
    }
  }

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 5),
        child: Text(t.toUpperCase(),
            style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, letterSpacing: .5, color: Colors.grey.shade400)),
      );

  InputDecoration _decor({String? hint, Widget? suffixIcon}) => InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
        suffixIcon: suffixIcon,
        isDense: true,
        filled: true,
        fillColor: const Color(0xFFFAFAFA),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: const BorderSide(color: Color(0xFFE7E7E7))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: const BorderSide(color: Color(0xFFE7E7E7))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: const BorderSide(color: _gold)),
      );

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.initial != null;
    return Container(
      height: MediaQuery.of(context).size.height * 0.9,
      padding: EdgeInsets.fromLTRB(18, 8, 18, 18 + MediaQuery.of(context).viewInsets.bottom),
      decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(width: 42, height: 4, margin: const EdgeInsets.only(top: 8, bottom: 16), decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(3)))),
            Text(isEdit ? 'Edit Item' : 'Add Item', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 16),

            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: const Color(0xFFFCFAF3), borderRadius: BorderRadius.circular(12), border: Border.all(color: _gold.withValues(alpha: 0.3))),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Item ${widget.itemNumber}  |  HSN: ${_hsnCode?.isNotEmpty == true ? _hsnCode : 'NA'}',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.grey.shade600)),
                  const SizedBox(height: 10),
                  _label('Product *'),
                  InkWell(
                    borderRadius: BorderRadius.circular(11),
                    onTap: _pickProduct,
                    child: IgnorePointer(
                      child: TextField(
                        controller: _productCtrl,
                        decoration: _decor(
                          hint: 'Tap to search…',
                          suffixIcon: Icon(Icons.search_rounded, size: 18, color: Colors.grey.shade500),
                        ),
                      ),
                    ),
                  ),
                  if (_productCtrl.text.isNotEmpty && _productId == null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('Select a real product from search results',
                          style: TextStyle(fontSize: 10.5, color: Colors.red.shade400)),
                    ),
                  const SizedBox(height: 12),
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        _label('Qty *'),
                        TextField(controller: _qtyCtrl, keyboardType: TextInputType.number, onChanged: (_) => setState(() {}), decoration: _decor()),
                      ]),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        _label('Unit'),
                        InkWell(
                          borderRadius: BorderRadius.circular(11),
                          onTap: _pickUnit,
                          child: Container(
                            height: 46,
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            decoration: BoxDecoration(color: const Color(0xFFFAFAFA), borderRadius: BorderRadius.circular(11), border: Border.all(color: const Color(0xFFE7E7E7))),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(_unit,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 13, color: Color(0xFF20242B), fontWeight: FontWeight.w500)),
                                ),
                                Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: Colors.grey.shade500),
                              ],
                            ),
                          ),
                        ),
                      ]),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        _label('Unit Price (incl. tax) *'),
                        TextField(controller: _priceCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), onChanged: (_) => setState(() {}), decoration: _decor()),
                      ]),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  Divider(height: 1, color: _gold.withValues(alpha: 0.2)),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        _label('Gross Amount'),
                        Text(_grossAmount.toStringAsFixed(2), style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                      ]),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        _label(_gstPercent > 0 ? 'Total Tax (${_gstPercent.toStringAsFixed(_gstPercent % 1 == 0 ? 0 : 2)}%)' : 'Total Tax'),
                        Text(_tax.toStringAsFixed(2), style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                      ]),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        _label('Product Total'),
                        Text(_productTotal.toStringAsFixed(2), style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: _goldDark)),
                      ]),
                    ),
                  ]),
                ],
              ),
            ),
            const SizedBox(height: 18),

            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: Colors.grey.shade300),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
                  ),
                  child: const Text('Cancel', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.black54)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: (_productCtrl.text.trim().isEmpty || _qty <= 0)
                      ? null
                      : () => Navigator.of(context).pop({
                            'product_id': _productId,
                            'name': _productCtrl.text.trim(),
                            'pack_size': _hsnCode,
                            'quantity': _qty.round(),
                            'unit': _unit,
                            'item_price': _price,
                            'tax_percent': _gstPercent,
                            'total_tax': _tax,
                            'item_total': _productTotal,
                            'gross_amount': _grossAmount,
                          }),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _gold,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: _gold.withValues(alpha: 0.5),
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
                  ),
                  child: const Text('Save', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

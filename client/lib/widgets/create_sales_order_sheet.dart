import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';

import '../screens/telecaller/telecaller_mock_data.dart' show kGold, kGoldDark;
import '../services/api_service.dart';
import 'product_picker_sheet.dart';

/// The "Create Sales Order" bottom sheet — originally built for the
/// telecaller's account profile, now shared so every role that can take an
/// order (telecaller, salesman) gets the identical form instead of each
/// screen growing its own slightly-different version.
class OrderLineItem {
  final product = TextEditingController();
  final qty = TextEditingController(text: '1');
  final unitPrice = TextEditingController(text: '0');
  String unit = 'PCS';
  String? productId; // real product_id once selected from search — required to submit a real order
  // GST rate of the selected product (product.gst_percent) — the unit price above
  // is entered tax-inclusive, so tax is extracted back out of it, not added on top.
  double gstPercent = 0;

  double get qtyNum => double.tryParse(qty.text.trim()) ?? 0;
  double get priceNum => double.tryParse(unitPrice.text.trim()) ?? 0;
  double get sgstPercent => gstPercent / 2;
  double get cgstPercent => gstPercent / 2;
  double get productTotal => qtyNum * priceNum;
  double get taxNum => gstPercent > 0 ? productTotal - productTotal / (1 + gstPercent / 100) : 0;
  double get sgstAmount => taxNum / 2;
  double get cgstAmount => taxNum / 2;
  double get grossAmount => productTotal - taxNum;

  void dispose() {
    product.dispose();
    qty.dispose();
    unitPrice.dispose();
  }
}

class OrderAddon {
  String name;
  final amount = TextEditingController(text: '0');
  OrderAddon(this.name);

  double get amountNum => double.tryParse(amount.text.trim()) ?? 0;

  void dispose() => amount.dispose();
}

class CreateSalesOrderSheet extends StatefulWidget {
  final String name;
  final String accountId;
  final String accountType; // 'lead' | 'customer'
  final Map<String, dynamic>? deliveryAddress;
  final String? areaName;
  final void Function(String items, int amount, String status, String pay, String? realOrderId) onSave;
  const CreateSalesOrderSheet({
    super.key,
    required this.name,
    required this.accountId,
    required this.accountType,
    this.deliveryAddress,
    this.areaName,
    required this.onSave,
  });

  @override
  State<CreateSalesOrderSheet> createState() => _CreateSalesOrderSheetState();
}

class _CreateSalesOrderSheetState extends State<CreateSalesOrderSheet> {
  static const _units = ['PCS', 'KG', 'BOX', 'LTR', 'DOZ'];
  static const _addonNames = ['Hamali', 'Transport', 'Packing', 'Discount', 'Other'];

  int? _voucherNo; // null while loading the real preview from the server
  DateTime _documentDate = DateTime.now();
  DateTime _expectedDate = DateTime.now().add(const Duration(days: 1));
  final _narration = TextEditingController();

  final List<OrderLineItem> _lineItems = [OrderLineItem()];
  final List<OrderAddon> _addons = [];
  bool _saving = false;

  bool get _isCustomer => widget.accountType == 'customer';

  @override
  void initState() {
    super.initState();
    _loadVoucherPreview();
  }

  Future<void> _loadVoucherPreview() async {
    final next = await ApiService.getNextSalesOrderId();
    if (!mounted) return;
    setState(() => _voucherNo = next);
  }

  @override
  void dispose() {
    _narration.dispose();
    for (final i in _lineItems) {
      i.dispose();
    }
    for (final a in _addons) {
      a.dispose();
    }
    super.dispose();
  }

  String get _financialYear {
    final d = _documentDate;
    final startYear = d.month >= 4 ? d.year : d.year - 1;
    return '${(startYear % 100).toString().padLeft(2, '0')}-${((startYear + 1) % 100).toString().padLeft(2, '0')}';
  }

  String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  double get _grossAmount => _lineItems.fold(0, (s, i) => s + i.grossAmount);
  double get _totalTax => _lineItems.fold(0, (s, i) => s + i.taxNum);
  double get _sgstTotal => _lineItems.fold(0, (s, i) => s + i.sgstAmount);
  double get _cgstTotal => _lineItems.fold(0, (s, i) => s + i.cgstAmount);
  double get _addonsTotal => _addons.fold(0, (s, a) => s + a.amountNum);
  double get _grandTotal => _grossAmount + _totalTax + _addonsTotal;

  OutlineInputBorder _border([Color c = const Color(0xFFE7E7E7)]) =>
      OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: BorderSide(color: c));

  InputDecoration _decor(String label, {String? hint}) => InputDecoration(
        labelText: label,
        hintText: hint,
        hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
        isDense: true,
        filled: true,
        fillColor: const Color(0xFFFAFAFA),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: _border(),
        enabledBorder: _border(),
        focusedBorder: _border(kGold),
      );

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 5),
        child: Text(t.toUpperCase(),
            style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, letterSpacing: .5, color: Colors.grey.shade400)),
      );

  Widget _sectionTitle(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(t, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: kGoldDark)),
      );

  Widget _voucherArrow(IconData icon, VoidCallback? onTap) => GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: 34, height: 38,
          alignment: Alignment.center,
          child: Icon(icon, size: 20, color: onTap != null ? kGoldDark : Colors.grey.shade300),
        ),
      );

  Widget _sectionCard({required String title, Widget? trailing, required Widget child}) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: kGold.withValues(alpha: 0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(child: _sectionTitle(title)),
              ?trailing,
            ]),
            child,
          ],
        ),
      );

  Future<void> _pickDate({required bool expected}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: expected ? _expectedDate : _documentDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() => expected ? _expectedDate = picked : _documentDate = picked);
    }
  }

  Future<void> _pickProduct(OrderLineItem item) async {
    final picked = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const ProductPickerSheet(),
    );
    if (picked != null) {
      setState(() {
        item.product.text = picked['name'] as String? ?? '';
        item.productId = picked['product_id'] as String?;
        item.gstPercent = (picked['gst_percent'] as num?)?.toDouble() ?? 0;
      });
    }
  }

  String _isoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _submit() async {
    final validItems = _lineItems.where((i) => i.product.text.trim().isNotEmpty && i.qtyNum > 0).toList();
    if (validItems.isEmpty) {
      Fluttertoast.showToast(msg: 'Add at least one product', backgroundColor: Colors.red, textColor: Colors.white);
      return;
    }
    final itemsSummary = validItems.map((i) => i.product.text.trim()).join(', ');

    if (!_isCustomer) {
      // Lead — no real `user` row to attach an order to. Local draft only.
      widget.onSave(itemsSummary, _grandTotal.round(), 'Draft', 'Pending', null);
      Navigator.of(context).pop();
      return;
    }

    final missingProduct = validItems.where((i) => i.productId == null).toList();
    if (missingProduct.isNotEmpty) {
      Fluttertoast.showToast(
        msg: 'Select a real product from search for every item before saving',
        backgroundColor: Colors.red, textColor: Colors.white,
      );
      return;
    }

    setState(() => _saving = true);
    final result = await ApiService.createSalesOrder(
      buyerUserId: widget.accountId,
      // No tax_percent/sgst_percent/cgst_percent here — the server derives
      // those authoritatively from the product's own gst_percent, not from
      // whatever the client computed (see SalesOrderController::store).
      items: validItems.map((i) => {
        'product_id':    i.productId,
        'quantity':      i.qtyNum,
        'item_price':    i.priceNum,
        'unit':          i.unit,
      }).toList(),
      discount: 0,
      // Addons (Hamali/Transport/Packing/etc.) are extra charges, not a discount —
      // the backend has no dedicated "charges" field yet, so fold them into
      // delivery_charge (which the order-total formula adds, matching intent).
      deliveryCharge: _addonsTotal,
      narration: _narration.text.trim().isEmpty ? null : _narration.text.trim(),
      department: null,
      areaName: widget.areaName,
      timeSlot: _fmtDate(_expectedDate),
      documentDate: _isoDate(_documentDate),
      deliveryInfo: widget.deliveryAddress != null ? {
        'name':      widget.name,
        'address':   widget.deliveryAddress!['address'],
        'latitude':  widget.deliveryAddress!['latitude'],
        'longitude': widget.deliveryAddress!['longitude'],
      } : null,
    );
    if (!mounted) return;
    setState(() => _saving = false);

    if (result == null) {
      Fluttertoast.showToast(msg: 'Could not create the order. Try again.', backgroundColor: Colors.red, textColor: Colors.white);
      return;
    }

    final realOrderId = result['order_id']?.toString();
    final savedTotal = ((result['order_total'] as num?) ?? _grandTotal).round();
    widget.onSave(itemsSummary, savedTotal, 'Pending', 'Not Paid', realOrderId);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height - MediaQuery.of(context).padding.top,
      padding: EdgeInsets.fromLTRB(18, 8, 18, 18 + MediaQuery.of(context).viewInsets.bottom),
      decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      child: Stack(
        children: [
          SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(child: Container(width: 42, height: 4, margin: const EdgeInsets.only(top: 8, bottom: 16), decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(3)))),
                const Text('Create Sales Order', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(widget.name, style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                const SizedBox(height: 18),

                // ── Customer & Dates ──────────────────────────────────────────
            _sectionCard(
              title: 'Customer & Dates',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        _label('Financial Year'),
                        Container(
                          height: 46,
                          alignment: Alignment.centerLeft,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(color: const Color(0xFFFAFAFA), borderRadius: BorderRadius.circular(11), border: Border.all(color: const Color(0xFFE7E7E7))),
                          child: Text(_financialYear, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                        ),
                      ]),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        _label('Voucher No'),
                        Container(
                          height: 46,
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          decoration: BoxDecoration(color: const Color(0xFFFAFAFA), borderRadius: BorderRadius.circular(11), border: Border.all(color: const Color(0xFFE7E7E7))),
                          child: Row(children: [
                            // No real "previous voucher" to browse to here — this is always
                            // a *new* order, so only a refresh action makes sense (the preview
                            // can go stale if another order is created elsewhere meanwhile).
                            _voucherArrow(Icons.chevron_left_rounded, null),
                            Expanded(
                              child: _voucherNo == null
                                  ? const Center(
                                      child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: kGold)),
                                    )
                                  : Text('$_voucherNo',
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                            ),
                            _voucherArrow(Icons.refresh_rounded, _loadVoucherPreview),
                          ]),
                        ),
                      ]),
                    ),
                  ]),
                  const SizedBox(height: 14),
                  Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        _label('Document Date *'),
                        InkWell(
                          borderRadius: BorderRadius.circular(11),
                          onTap: () => _pickDate(expected: false),
                          child: Container(
                            height: 46,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(color: const Color(0xFFFAFAFA), borderRadius: BorderRadius.circular(11), border: Border.all(color: const Color(0xFFE7E7E7))),
                            child: Row(children: [
                              Expanded(child: Text(_fmtDate(_documentDate), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
                              Icon(Icons.calendar_today_rounded, size: 15, color: Colors.grey.shade500),
                            ]),
                          ),
                        ),
                      ]),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        _label('Expected Date'),
                        InkWell(
                          borderRadius: BorderRadius.circular(11),
                          onTap: () => _pickDate(expected: true),
                          child: Container(
                            height: 46,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(color: const Color(0xFFFAFAFA), borderRadius: BorderRadius.circular(11), border: Border.all(color: const Color(0xFFE7E7E7))),
                            child: Row(children: [
                              Expanded(child: Text(_fmtDate(_expectedDate), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
                              Icon(Icons.calendar_today_rounded, size: 15, color: Colors.grey.shade500),
                            ]),
                          ),
                        ),
                      ]),
                    ),
                  ]),
                  const SizedBox(height: 14),
                  _label('Customer'),
                  Container(
                    width: double.infinity,
                    height: 46,
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(color: const Color(0xFFFAFAFA), borderRadius: BorderRadius.circular(11), border: Border.all(color: const Color(0xFFE7E7E7))),
                    child: Text(widget.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                  ),
                  if (widget.deliveryAddress != null) ...[
                    const SizedBox(height: 14),
                    _label('Delivery Address'),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      decoration: BoxDecoration(color: const Color(0xFFFAFAFA), borderRadius: BorderRadius.circular(11), border: Border.all(color: const Color(0xFFE7E7E7))),
                      child: Text('${widget.deliveryAddress!['address'] ?? ''}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    ),
                  ],
                  const SizedBox(height: 14),
                  _label('Narration'),
                  TextField(controller: _narration, maxLines: 2, decoration: _decor('', hint: 'Notes for this order…')),
                ],
              ),
            ),

            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(color: kGold.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(10)),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.info_outline_rounded, size: 16, color: kGoldDark),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Prices are entered tax-inclusive — GST is calculated automatically from each product\'s tax rate.',
                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: kGoldDark),
                  ),
                ),
              ]),
            ),

            // ── Product Detail ────────────────────────────────────────────
            _sectionCard(
              title: 'Product Detail',
              trailing: GestureDetector(
                onTap: () => setState(() => _lineItems.add(OrderLineItem())),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(color: kGold.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20), border: Border.all(color: kGold.withValues(alpha: 0.4))),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.add_rounded, size: 15, color: kGoldDark),
                    SizedBox(width: 3),
                    Text('Add Item', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: kGoldDark)),
                  ]),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 6),
                  ..._lineItems.asMap().entries.map((entry) {
                    final idx = entry.key;
                    final item = entry.value;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: const Color(0xFFFCFAF3), borderRadius: BorderRadius.circular(12), border: Border.all(color: kGold.withValues(alpha: 0.3))),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Expanded(
                              child: Text('Item ${idx + 1}  |  HSN: NA',
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.grey.shade600)),
                            ),
                            if (_lineItems.length > 1)
                              GestureDetector(
                                onTap: () => setState(() { item.dispose(); _lineItems.removeAt(idx); }),
                                child: const Icon(Icons.delete_outline_rounded, size: 18, color: Color(0xFFC0584C)),
                              ),
                          ]),
                          const SizedBox(height: 10),
                          _label('Product *'),
                          InkWell(
                            borderRadius: BorderRadius.circular(11),
                            onTap: () => _pickProduct(item),
                            child: IgnorePointer(
                              child: TextField(
                                controller: item.product,
                                decoration: _decor('', hint: 'Tap to search…').copyWith(
                                  suffixIcon: Icon(Icons.search_rounded, size: 18, color: Colors.grey.shade500),
                                  suffixIconConstraints: const BoxConstraints(minWidth: 36),
                                ),
                              ),
                            ),
                          ),
                          if (item.product.text.isNotEmpty && item.productId == null)
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
                                TextField(controller: item.qty, keyboardType: TextInputType.number, onChanged: (_) => setState(() {}), decoration: _decor('')),
                              ]),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                _label('Unit'),
                                Container(
                                  height: 46,
                                  padding: const EdgeInsets.symmetric(horizontal: 10),
                                  decoration: BoxDecoration(color: const Color(0xFFFAFAFA), borderRadius: BorderRadius.circular(11), border: Border.all(color: const Color(0xFFE7E7E7))),
                                  child: DropdownButtonHideUnderline(
                                    child: DropdownButton<String>(
                                      value: item.unit,
                                      isExpanded: true,
                                      isDense: true,
                                      style: const TextStyle(fontSize: 13, color: Color(0xFF20242B), fontWeight: FontWeight.w500),
                                      items: _units.map((u) => DropdownMenuItem(value: u, child: Text(u))).toList(),
                                      onChanged: (v) { if (v != null) setState(() => item.unit = v); },
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
                                TextField(controller: item.unitPrice, keyboardType: const TextInputType.numberWithOptions(decimal: true), onChanged: (_) => setState(() {}), decoration: _decor('')),
                              ]),
                            ),
                          ]),
                          const SizedBox(height: 12),
                          Divider(height: 1, color: kGold.withValues(alpha: 0.2)),
                          const SizedBox(height: 10),
                          if (item.gstPercent > 0) ...[
                            Row(children: [
                              Expanded(flex: 2, child: Text('Tax', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Colors.grey.shade500))),
                              Expanded(child: Text('Tax %', textAlign: TextAlign.right, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Colors.grey.shade500))),
                              Expanded(child: Text('Tax Amount', textAlign: TextAlign.right, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Colors.grey.shade500))),
                            ]),
                            const SizedBox(height: 6),
                            Row(children: [
                              const Expanded(flex: 2, child: Text('SGST', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600))),
                              Expanded(child: Text('${item.sgstPercent.toStringAsFixed(2)}%', textAlign: TextAlign.right, style: const TextStyle(fontSize: 12.5))),
                              Expanded(child: Text(item.sgstAmount.toStringAsFixed(2), textAlign: TextAlign.right, style: const TextStyle(fontSize: 12.5))),
                            ]),
                            const SizedBox(height: 4),
                            Row(children: [
                              const Expanded(flex: 2, child: Text('CGST', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600))),
                              Expanded(child: Text('${item.cgstPercent.toStringAsFixed(2)}%', textAlign: TextAlign.right, style: const TextStyle(fontSize: 12.5))),
                              Expanded(child: Text(item.cgstAmount.toStringAsFixed(2), textAlign: TextAlign.right, style: const TextStyle(fontSize: 12.5))),
                            ]),
                            const SizedBox(height: 10),
                            Divider(height: 1, color: kGold.withValues(alpha: 0.2)),
                            const SizedBox(height: 10),
                          ],
                          Row(children: [
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                _label('Gross Amount'),
                                Text(item.grossAmount.toStringAsFixed(2), style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                              ]),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                _label('Total Tax'),
                                Text(item.taxNum.toStringAsFixed(2), style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                              ]),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                _label('Product Total'),
                                Text(item.productTotal.toStringAsFixed(2), style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: kGoldDark)),
                              ]),
                            ),
                          ]),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),

            // ── Addon ──────────────────────────────────────────────────────
            _sectionCard(
              title: 'Addon',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 4),
                  ..._addons.asMap().entries.map((entry) {
                    final idx = entry.key;
                    final addon = entry.value;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            _label('Name'),
                            Container(
                              height: 46,
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              decoration: BoxDecoration(color: const Color(0xFFFAFAFA), borderRadius: BorderRadius.circular(11), border: Border.all(color: const Color(0xFFE7E7E7))),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  value: addon.name,
                                  isExpanded: true,
                                  isDense: true,
                                  style: const TextStyle(fontSize: 13, color: Color(0xFF20242B), fontWeight: FontWeight.w500),
                                  items: _addonNames.map((n) => DropdownMenuItem(value: n, child: Text(n))).toList(),
                                  onChanged: (v) { if (v != null) setState(() => addon.name = v); },
                                ),
                              ),
                            ),
                          ]),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            _label('Amount'),
                            TextField(controller: addon.amount, keyboardType: const TextInputType.numberWithOptions(decimal: true), onChanged: (_) => setState(() {}), decoration: _decor('')),
                          ]),
                        ),
                        const SizedBox(width: 10),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: GestureDetector(
                            onTap: () => setState(() { addon.dispose(); _addons.removeAt(idx); }),
                            child: const Icon(Icons.delete_outline_rounded, size: 18, color: Color(0xFFC0584C)),
                          ),
                        ),
                      ]),
                    );
                  }),
                  Align(
                    alignment: Alignment.centerRight,
                    child: OutlinedButton.icon(
                      onPressed: () => setState(() => _addons.add(OrderAddon(_addonNames.first))),
                      icon: const Icon(Icons.add_rounded, size: 15, color: kGoldDark),
                      label: const Text('Addons', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: kGoldDark)),
                      style: OutlinedButton.styleFrom(side: const BorderSide(color: kGold), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
                    ),
                  ),
                ],
              ),
            ),

            // ── Summary ────────────────────────────────────────────────────
            _sectionCard(
              title: 'Summary',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 4),
                  Row(children: [
                    Text('Gross Amount', style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
                    const Spacer(),
                    Text(_grossAmount.toStringAsFixed(2), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                  ]),
                  if (_totalTax > 0) ...[
                    const SizedBox(height: 8),
                    Row(children: [
                      Text('SGST', style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
                      const Spacer(),
                      Text(_sgstTotal.toStringAsFixed(2), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                    ]),
                    const SizedBox(height: 8),
                    Row(children: [
                      Text('CGST', style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
                      const Spacer(),
                      Text(_cgstTotal.toStringAsFixed(2), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                    ]),
                  ],
                  if (_addonsTotal > 0) ...[
                    const SizedBox(height: 8),
                    Row(children: [
                      Text('Add on total', style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
                      const Spacer(),
                      Text(_addonsTotal.toStringAsFixed(2), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                    ]),
                  ],
                  const SizedBox(height: 10),
                  Divider(height: 1, color: kGold.withValues(alpha: 0.2)),
                  const SizedBox(height: 10),
                  Row(children: [
                    const Text('Total', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                    const Spacer(),
                    Text('₹${_grandTotal.toStringAsFixed(2)}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: kGoldDark)),
                  ]),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: (_isCustomer ? const Color(0xFF2F9E57) : const Color(0xFFD98A2B)).withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                _isCustomer
                    ? 'This will create a real Sales Order for this customer.'
                    // Whether this is kept anywhere after Save depends on the caller
                    // (e.g. the telecaller flow keeps a local list; others may not) —
                    // this sheet itself has no way to guarantee persistence, so it
                    // doesn't claim one.
                    : 'This account is a lead, not a registered customer yet — no real Sales Order will be created.',
                style: TextStyle(
                  fontSize: 11.5, fontWeight: FontWeight.w600,
                  color: _isCustomer ? const Color(0xFF2F9E57) : const Color(0xFFD98A2B),
                ),
              ),
            ),
            const SizedBox(height: 14),

            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _saving ? null : () => Navigator.of(context).pop(),
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
                  onPressed: _saving ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kGold,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: kGold.withValues(alpha: 0.5),
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
                  ),
                  child: _saving
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Save', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
                ),
              ),
            ]),
          ],
            ),
          ),
          Positioned(
            top: 4, right: 0,
            child: GestureDetector(
              onTap: _saving ? null : () => Navigator.of(context).pop(),
              behavior: HitTestBehavior.opaque,
              child: Container(
                width: 32, height: 32,
                decoration: BoxDecoration(color: Colors.grey.shade100, shape: BoxShape.circle),
                child: Icon(Icons.close_rounded, size: 18, color: Colors.grey.shade600),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

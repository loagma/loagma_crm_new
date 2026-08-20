import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';

import '../screens/telecaller/telecaller_mock_data.dart' show kGold, kGoldDark;
import '../services/api_service.dart';
import 'product_catalog_search.dart';
import 'product_picker_sheet.dart';
import 'unit_picker_sheet.dart';

/// The "Create Sales Order" bottom sheet — originally built for the
/// telecaller's account profile, now shared so every role that can take an
/// order (telecaller, salesman) gets the identical form instead of each
/// screen growing its own slightly-different version.
///
/// Catalog-first layout: the sheet opens straight onto product search/browse
/// (ProductCatalogSearch) — Customer & Dates opens as a centered dialog from
/// the product panel's own pencil button (never a blocking presence on its
/// own; only while the user has deliberately opened it), and the cart (line
/// items / addons / totals / Save) lives behind the bottom "Review & Save"
/// bar as a modal sheet. Both are built from the same state this widget
/// already owns; the Review sheet stays in sync via a StatefulBuilder +
/// [_bump] so edits inside it show up immediately without waiting for the
/// sheet to close — the Customer & Dates dialog doesn't need that since nothing
/// else on screen needs to react live while it's open.
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
  // Shown read-only in the Customer section so whoever is taking the order can
  // confirm they're billing the right account (GST number especially) without
  // leaving the sheet.
  final String? contactNumber;
  final String? gstNumber;
  final String? accountCode;
  final String? city;
  final String? state;
  final String? pincode;
  final void Function(String items, int amount, String status, String pay, String? realOrderId) onSave;
  const CreateSalesOrderSheet({
    super.key,
    required this.name,
    required this.accountId,
    required this.accountType,
    this.deliveryAddress,
    this.areaName,
    this.contactNumber,
    this.gstNumber,
    this.accountCode,
    this.city,
    this.state,
    this.pincode,
    required this.onSave,
  });

  @override
  State<CreateSalesOrderSheet> createState() => _CreateSalesOrderSheetState();
}

class _CreateSalesOrderSheetState extends State<CreateSalesOrderSheet> {
  static const _pageBg = Color(0xFFF4F5F6);
  static const _fieldBg = Color(0xFFFAFAFA);
  static const _fieldBorder = Color(0xFFE7E7E7);
  static const _ink = Color(0xFF20242B);

  // Fallback shown until units_master loads. Deliberately a subset of real
  // units_master names: a selected value that's absent from the loaded list
  // trips DropdownButton's "value must match exactly one item" assert. (The
  // old fallback had 'DOZ', which units_master spells 'DOZEN'.)
  List<String> _units = const ['PCS', 'KG', 'BOX', 'LTR', 'NOS'];
  static const _addonNames = ['Hamali', 'Transport', 'Packing', 'Discount', 'Other'];

  int? _voucherNo; // null while loading the real preview from the server
  DateTime _documentDate = DateTime.now();
  DateTime _expectedDate = DateTime.now().add(const Duration(days: 1));
  final _narration = TextEditingController();

  final List<OrderLineItem> _lineItems = [OrderLineItem()];
  final List<OrderAddon> _addons = [];
  bool _saving = false;
  // True only while the Customer & Dates dialog is on screen — purely so the
  // pencil button can show a brighter border while its dialog is open; the
  // dialog's own visibility is otherwise managed by showDialog/Navigator.
  bool _customerPanelOpen = false;

  bool get _isCustomer => widget.accountType == 'customer';

  @override
  void initState() {
    super.initState();
    _loadVoucherPreview();
    _loadUnits();
  }

  Future<void> _loadVoucherPreview() async {
    final next = await ApiService.getNextSalesOrderId();
    if (!mounted) return;
    setState(() => _voucherNo = next);
  }

  Future<void> _loadUnits() async {
    final units = await ApiService.getUnits();
    final names = units.map((u) => (u['unit_name'] as String?) ?? '').where((u) => u.isNotEmpty).toList();
    if (!mounted || names.isEmpty) return;
    setState(() {
      _units = names;
      // Belt-and-braces for the assert noted on _units: if a line item is still
      // holding a fallback value the real list doesn't have, move it onto one
      // that does instead of crashing the sheet.
      for (final i in _lineItems) {
        if (!names.contains(i.unit)) i.unit = names.first;
      }
    });
  }

  Future<void> _pickUnit(OrderLineItem item) async {
    final picked = await showUnitPickerSheet(context, units: _units, selected: item.unit);
    if (picked != null) setState(() => item.unit = picked);
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
  int get _itemCount => _lineItems.where((i) => i.product.text.trim().isNotEmpty).length;

  OutlineInputBorder _border([Color c = _fieldBorder]) =>
      OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: BorderSide(color: c));

  InputDecoration _decor(String label, {String? hint}) => InputDecoration(
        labelText: label,
        hintText: hint,
        hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
        isDense: true,
        filled: true,
        fillColor: _fieldBg,
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

  List<Widget> _customerDetailRows() {
    final place = [widget.city, widget.state, widget.pincode]
        .map((v) => (v ?? '').trim())
        .where((v) => v.isNotEmpty)
        .join(', ');
    final rows = <String, String>{
      'Code':    (widget.accountCode ?? '').trim(),
      'Phone':   (widget.contactNumber ?? '').trim(),
      'GST No':  (widget.gstNumber ?? '').trim(),
      'Area':    (widget.areaName ?? '').trim(),
      'Place':   place,
    }..removeWhere((_, v) => v.isEmpty);

    if (rows.isEmpty) return const [];

    return [
      const SizedBox(height: 8),
      ...rows.entries.map((e) => Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text.rich(TextSpan(children: [
              TextSpan(text: '${e.key}: ', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: _ink)),
              TextSpan(text: e.value, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w400, color: _ink)),
            ])),
          )),
    ];
  }

  Widget _sectionTitle(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(t, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: _ink)),
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
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.fromLTRB(15, 15, 15, 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(color: const Color(0xFF141F1F).withValues(alpha: 0.04), blurRadius: 2, offset: const Offset(0, 1)),
            BoxShadow(color: const Color(0xFF141F1F).withValues(alpha: 0.05), blurRadius: 18, offset: const Offset(0, 6)),
          ],
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

  Widget _sheetHandle() => Center(
        child: Container(
          width: 42, height: 4,
          margin: const EdgeInsets.only(top: 8, bottom: 14),
          decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(3)),
        ),
      );

  Widget _sheetCloseButton(VoidCallback? onTap, {Key? key}) => GestureDetector(
        key: key,
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: 32, height: 32,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: const Color(0xFF141F1F).withValues(alpha: 0.08), blurRadius: 6, offset: const Offset(0, 2))],
          ),
          child: Icon(Icons.close_rounded, size: 18, color: Colors.grey.shade600),
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

  // Fed by ProductCatalogSearch's Add button — replaces the still-empty
  // starter line item on the first add, then appends after that, so picking
  // from the catalog doesn't leave a dangling blank "Item 1" behind it.
  void _addFromCatalog(OrderLineItem item) {
    setState(() {
      if (_lineItems.length == 1 && _lineItems.first.product.text.trim().isEmpty) {
        _lineItems.first.dispose();
        _lineItems[0] = item;
      } else {
        _lineItems.add(item);
      }
    });
    Fluttertoast.showToast(msg: 'Added to order — $_itemCount item${_itemCount == 1 ? '' : 's'} in cart', backgroundColor: kGold, textColor: Colors.white);
  }

  // Nested sheets (Customer & Dates / Review Order) are separate routes, so a
  // bare setState() on this State doesn't refresh what's already on screen
  // inside them — this updates the real data AND the open sheet's own
  // StatefulBuilder in one call.
  void _bump(StateSetter setModalState, VoidCallback fn) {
    setState(fn);
    setModalState(() {});
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
      _closeAfterSave();
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
    _closeAfterSave();
  }

  // A successful save happens from inside the Review Order sheet, which is
  // itself stacked on top of this sheet — closing just that sheet would leave
  // the (now-saved) catalog screen open behind it, so this pops both routes.
  void _closeAfterSave() {
    final nav = Navigator.of(context);
    nav.pop();
    nav.pop();
  }

  // ── Customer & Dates (opens centered, from the product panel's pencil
  // button) ──────────────────────────────────────────────────────────────
  // A real (centered) dialog rather than a bottom sheet or side panel — it
  // still never blocks the product side just by existing, because it's only
  // on screen while the user deliberately has it open; closing it (X,
  // Cancel, or Save) is the same action in all three cases, since every
  // field here is already live-bound to shared state via controllers or
  // immediate setState, so there's nothing separate to persist.
  Future<void> _openCustomerDatesDialog() async {
    setState(() => _customerPanelOpen = true);
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.4),
      builder: (dialogCtx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440, maxHeight: 680),
          child: _customerDatesPanel(onClose: () => Navigator.of(dialogCtx).pop()),
        ),
      ),
    );
    if (mounted) setState(() => _customerPanelOpen = false);
  }

  Widget _customerDatesPanel({required VoidCallback onClose}) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(color: const Color(0xFF141F1F).withValues(alpha: 0.04), blurRadius: 2, offset: const Offset(0, 1)),
          BoxShadow(color: const Color(0xFF141F1F).withValues(alpha: 0.08), blurRadius: 22, offset: const Offset(0, 8)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 34, height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(9), border: Border.all(color: _fieldBorder)),
              child: const Icon(Icons.edit_note_rounded, size: 18, color: Color(0xFF20242B)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Customer & Dates', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: kGoldDark)),
                const SizedBox(height: 2),
                Text('Enter or update customer and document details', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
              ]),
            ),
            GestureDetector(
              key: const Key('customerDatesCloseBtn'),
              onTap: onClose,
              behavior: HitTestBehavior.opaque,
              child: Icon(Icons.close_rounded, size: 20, color: Colors.grey.shade500),
            ),
          ]),
          const SizedBox(height: 16),
          Flexible(child: SingleChildScrollView(child: _customerDatesFields())),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: onClose,
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: Colors.grey.shade300),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
                ),
                child: const Text('Cancel', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: Colors.black54)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton(
                onPressed: onClose,
                style: ElevatedButton.styleFrom(
                  backgroundColor: kGold,
                  foregroundColor: Colors.white,
                  elevation: 4,
                  shadowColor: kGold.withValues(alpha: 0.45),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
                ),
                child: const Text('Save', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
              ),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _customerDatesFields() {
    return Column(
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
                decoration: BoxDecoration(color: _fieldBg, borderRadius: BorderRadius.circular(11), border: Border.all(color: _fieldBorder)),
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
                padding: const EdgeInsets.only(left: 12, right: 4),
                decoration: BoxDecoration(color: _fieldBg, borderRadius: BorderRadius.circular(11), border: Border.all(color: _fieldBorder)),
                // No real "previous voucher" to browse to here — this is always a
                // *new* order, so only a refresh action makes sense (the preview
                // can go stale if another order is created elsewhere meanwhile) —
                // no left/previous arrow shown since there's nothing it could do.
                child: Row(children: [
                  Expanded(
                    child: _voucherNo == null
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: kGold))
                        : Text('$_voucherNo', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
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
                  decoration: BoxDecoration(color: _fieldBg, borderRadius: BorderRadius.circular(11), border: Border.all(color: _fieldBorder)),
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
                  decoration: BoxDecoration(color: _fieldBg, borderRadius: BorderRadius.circular(11), border: Border.all(color: _fieldBorder)),
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
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(color: _fieldBg, borderRadius: BorderRadius.circular(11), border: Border.all(color: _fieldBorder)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.name.trim().isEmpty ? 'Unnamed customer' : widget.name,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: widget.name.trim().isEmpty ? Colors.grey.shade500 : null,
                ),
              ),
              ..._customerDetailRows(),
            ],
          ),
        ),
        if (widget.deliveryAddress != null) ...[
          const SizedBox(height: 14),
          _label('Delivery Address'),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(color: _fieldBg, borderRadius: BorderRadius.circular(11), border: Border.all(color: _fieldBorder)),
            child: Text('${widget.deliveryAddress!['address'] ?? ''}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          ),
        ],
        const SizedBox(height: 14),
        _label('Narration'),
        TextField(controller: _narration, maxLines: 3, decoration: _decor('', hint: 'Enter narration (optional)…')),
      ],
    );
  }

  // ── Review Order (opens from the bottom cart bar) ────────────────────────

  void _openReviewSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setModalState) => Container(
          height: MediaQuery.of(sheetCtx).size.height * 0.92,
          padding: EdgeInsets.fromLTRB(18, 8, 18, 14 + MediaQuery.of(sheetCtx).viewInsets.bottom),
          decoration: const BoxDecoration(color: _pageBg, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
          child: Column(
            children: [
              _sheetHandle(),
              Row(children: [
                const Expanded(child: Text('Review Order', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: _ink))),
                _sheetCloseButton(_saving ? null : () => Navigator.of(sheetCtx).pop(), key: const Key('reviewCloseBtn')),
              ]),
              const SizedBox(height: 14),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 14),
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
                      _sectionCard(
                        title: 'Product Detail',
                        trailing: GestureDetector(
                          onTap: () => _bump(setModalState, () => _lineItems.add(OrderLineItem())),
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
                        child: _productDetailItems(setModalState),
                      ),
                      _sectionCard(
                        title: 'Addon',
                        child: _addonItems(setModalState),
                      ),
                      _sectionCard(
                        title: 'Summary',
                        child: _summaryContent(),
                      ),
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
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _saving ? null : () => Navigator.of(sheetCtx).pop(),
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
                    onPressed: _saving ? null : () async {
                      await _submit();
                      if (sheetCtx.mounted) setModalState(() {});
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kGold,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: kGold.withValues(alpha: 0.5),
                      elevation: 4,
                      shadowColor: kGold.withValues(alpha: 0.45),
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
      ),
    );
  }

  Widget _productDetailItems(StateSetter setModalState) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 6),
        ..._lineItems.asMap().entries.map((entry) {
          final idx = entry.key;
          final item = entry.value;
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: const Color(0xFFF6F6F7), borderRadius: BorderRadius.circular(14)),
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
                      onTap: () => _bump(setModalState, () { item.dispose(); _lineItems.removeAt(idx); }),
                      child: const Icon(Icons.delete_outline_rounded, size: 18, color: Color(0xFFC0584C)),
                    ),
                ]),
                const SizedBox(height: 10),
                _label('Product *'),
                InkWell(
                  borderRadius: BorderRadius.circular(11),
                  onTap: () async { await _pickProduct(item); setModalState(() {}); },
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
                      TextField(controller: item.qty, keyboardType: TextInputType.number, onChanged: (_) => _bump(setModalState, () {}), decoration: _decor('')),
                    ]),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      _label('Unit'),
                      InkWell(
                        borderRadius: BorderRadius.circular(11),
                        onTap: () async { await _pickUnit(item); setModalState(() {}); },
                        child: Container(
                          height: 46,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          decoration: BoxDecoration(color: _fieldBg, borderRadius: BorderRadius.circular(11), border: Border.all(color: _fieldBorder)),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(item.unit,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 13, color: _ink, fontWeight: FontWeight.w500)),
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
                      TextField(controller: item.unitPrice, keyboardType: const TextInputType.numberWithOptions(decimal: true), onChanged: (_) => _bump(setModalState, () {}), decoration: _decor('')),
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
    );
  }

  Widget _addonItems(StateSetter setModalState) {
    return Column(
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
                    decoration: BoxDecoration(color: _fieldBg, borderRadius: BorderRadius.circular(11), border: Border.all(color: _fieldBorder)),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: addon.name,
                        isExpanded: true,
                        isDense: true,
                        style: const TextStyle(fontSize: 13, color: _ink, fontWeight: FontWeight.w500),
                        items: _addonNames.map((n) => DropdownMenuItem(value: n, child: Text(n))).toList(),
                        onChanged: (v) { if (v != null) _bump(setModalState, () => addon.name = v); },
                      ),
                    ),
                  ),
                ]),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _label('Amount'),
                  TextField(controller: addon.amount, keyboardType: const TextInputType.numberWithOptions(decimal: true), onChanged: (_) => _bump(setModalState, () {}), decoration: _decor('')),
                ]),
              ),
              const SizedBox(width: 10),
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: GestureDetector(
                  onTap: () => _bump(setModalState, () { addon.dispose(); _addons.removeAt(idx); }),
                  child: const Icon(Icons.delete_outline_rounded, size: 18, color: Color(0xFFC0584C)),
                ),
              ),
            ]),
          );
        }),
        Align(
          alignment: Alignment.centerRight,
          child: OutlinedButton.icon(
            onPressed: () => _bump(setModalState, () => _addons.add(OrderAddon(_addonNames.first))),
            icon: const Icon(Icons.add_rounded, size: 15, color: kGoldDark),
            label: const Text('Addons', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: kGoldDark)),
            style: OutlinedButton.styleFrom(side: const BorderSide(color: kGold), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
          ),
        ),
      ],
    );
  }

  Widget _summaryContent() {
    return Column(
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
    );
  }

  // ── Main screen: catalog-first ────────────────────────────────────────────

  Widget _header() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Expanded(
          child: Text('Create Sales Order', style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, color: _ink)),
        ),
        _sheetCloseButton(_saving ? null : () => Navigator.of(context).pop()),
      ],
    );
  }

  // Store-name bar sitting above the product list, inside the product panel —
  // the pencil here (not in the sheet's own header) is what the user asked
  // for: "clearly visible in the top-right of the store/product panel", so it
  // only ever intercepts taps meant for opening Customer & Dates, never ones
  // meant for a product card underneath it.
  Widget _productPanelHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(color: const Color(0xFFF3F3F4), borderRadius: BorderRadius.circular(12)),
      child: Row(children: [
        Icon(Icons.storefront_outlined, size: 18, color: Colors.grey.shade700),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            widget.name.trim().isEmpty ? 'Unnamed customer' : widget.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: _ink),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          key: const Key('pencilEditBtn'),
          onTap: _openCustomerDatesDialog,
          behavior: HitTestBehavior.opaque,
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: _customerPanelOpen ? kGold : kGold.withValues(alpha: 0.5)),
            ),
            child: Icon(Icons.edit_outlined, size: 16, color: kGoldDark),
          ),
        ),
      ]),
    );
  }

  Widget _productPanel() {
    return Stack(
      children: [
        ProductCatalogSearch(onAdd: _addFromCatalog, secondaryHeader: _productPanelHeader()),
        Positioned(bottom: 4, right: 4, child: _micButton()),
      ],
    );
  }

  Widget _micButton() => GestureDetector(
        onTap: () => Fluttertoast.showToast(msg: 'Voice search coming soon', backgroundColor: kGold, textColor: Colors.white),
        child: Container(
          width: 52, height: 52,
          decoration: BoxDecoration(
            color: kGold,
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: kGold.withValues(alpha: 0.45), blurRadius: 14, offset: const Offset(0, 6))],
          ),
          child: const Icon(Icons.mic_none_rounded, color: Colors.white, size: 24),
        ),
      );

  Widget _cartBar() {
    final count = _itemCount;
    return GestureDetector(
      key: const Key('cartBar'),
      onTap: _openReviewSheet,
      child: Container(
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: kGold,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: kGold.withValues(alpha: 0.4), blurRadius: 16, offset: const Offset(0, 6))],
        ),
        child: Row(children: [
          const Icon(Icons.shopping_bag_outlined, color: Colors.white, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              count == 0 ? 'No items yet' : '$count item${count == 1 ? '' : 's'}  ·  ₹${_grandTotal.toStringAsFixed(2)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: Colors.white),
            ),
          ),
          const SizedBox(width: 8),
          const Text('Review & Save', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Colors.white)),
          const SizedBox(width: 4),
          const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 16),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height - MediaQuery.of(context).padding.top,
      padding: EdgeInsets.fromLTRB(18, 12, 18, 14 + MediaQuery.of(context).viewInsets.bottom),
      decoration: const BoxDecoration(color: _pageBg, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sheetHandle(),
          _header(),
          const SizedBox(height: 14),
          Expanded(child: _productPanel()),
          _cartBar(),
        ],
      ),
    );
  }
}

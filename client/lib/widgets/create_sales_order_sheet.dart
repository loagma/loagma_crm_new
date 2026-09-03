import 'dart:async';

import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';

import '../screens/telecaller/telecaller_mock_data.dart' show kGold, kGoldDark;
import '../services/api_service.dart';
import 'catalog_product_picker.dart';
import 'product_catalog_search.dart';
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
  String?
  productId; // real product_id once selected from search — required to submit a real order
  // Which vendor_products.packs[] entry this line came from — identifies a
  // single product+pack combo so the catalog's qty stepper can find and
  // live-update this exact line instead of always appending a new one. Null
  // Null only if this product had no vendor pack pricing at all — see
  // ProductController::search.
  String? packId;
  // Full pack label as shown in the catalog (e.g. "1 Pack of 5 Kg @ 195/-")
  // — `unit` alone is just the trailing token off that label ("Kg"), not
  // enough to tell two packs of the same product apart in the cart. Null
  // Null only if this product had no vendor pack pricing at all — see
  // ProductController::search.
  String? packLabel;
  // vendor_products.id for this product+vendor — carried along so a stored
  // draft line records which vendor listing priced it (and so the draft's
  // stock figure can be re-resolved on restore — see
  // SalesOrderDraftController); null for a product with no vendor pack
  // pricing (same case as packId).
  String? vendorProductId;
  // product.hsn_code, carried along so a catalog pick still shows a real HSN
  // in the item header instead of always falling back to "NA".
  String? hsnCode;
  // Live stock for the selected pack at the moment this item was added from
  // the catalog (ProductController::parsePacks' 'stock') — null only for a
  // product with no vendor pack pricing at all.
  int? maxQty;
  // GST rate of the selected product (product.gst_percent) — the unit price above
  // is entered tax-inclusive, so tax is extracted back out of it, not added on top.
  double gstPercent = 0;

  double get qtyNum => double.tryParse(qty.text.trim()) ?? 0;
  double get priceNum => double.tryParse(unitPrice.text.trim()) ?? 0;
  double get sgstPercent => gstPercent / 2;
  double get cgstPercent => gstPercent / 2;
  double get productTotal => qtyNum * priceNum;
  double get taxNum =>
      gstPercent > 0 ? productTotal - productTotal / (1 + gstPercent / 100) : 0;
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
  final void Function(
    String items,
    int amount,
    String status,
    String pay,
    String? realOrderId,
  )
  onSave;
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
  static const _addonNames = [
    'Hamali',
    'Transport',
    'Packing',
    'Discount',
    'Other',
  ];

  int? _voucherNo; // null while loading the real preview from the server
  DateTime _documentDate = DateTime.now();
  DateTime _expectedDate = DateTime.now().add(const Duration(days: 1));
  final _narration = TextEditingController();

  // Starts empty — items only ever arrive from the catalog's qty stepper
  // (or, for a product with no vendor pack pricing, the manual product
  // search inside _manualItemForm), never a blank line shown by default.
  final List<OrderLineItem> _lineItems = [];
  final List<OrderAddon> _addons = [];
  bool _saving = false;
  // True only while the Customer & Dates dialog is on screen — purely so the
  // pencil button can show a brighter border while its dialog is open; the
  // dialog's own visibility is otherwise managed by showDialog/Navigator.
  bool _customerPanelOpen = false;
  // The Review sheet's addon editor (Hamali/Transport/etc.) starts collapsed
  // behind a "+ Add Charges" link so the default view matches the plain
  // item-list + Bill Details cart layout — most orders never need it.
  bool _showAddons = false;

  bool get _isCustomer => widget.accountType == 'customer';

  // -- Draft persistence (sales_order_draft_crm) ---------------------------
  // Autosave is debounced so a burst of qty taps is one PUT, not ten. Every
  // mutation path funnels through _scheduleDraftSave(); dispose() flushes any
  // pending timer so closing the sheet right after an edit still persists it.
  Timer? _draftDebounce;
  static const _draftDebounceDelay = Duration(milliseconds: 600);
  // Nothing is saved until the restore has finished - otherwise the empty
  // initial state would race the GET and overwrite the very draft being
  // loaded.
  bool _draftLoaded = false;
  // The address stored on the draft, used only when the caller didn't pass a
  // freshly-picked one (see _deliveryAddress).
  Map<String, dynamic>? _draftDeliveryAddress;

  // The caller resolves an address *before* opening the sheet, so a choice
  // made this session always wins over whatever the draft remembers; the
  // draft's copy is the fallback for when nothing was picked.
  Map<String, dynamic>? get _deliveryAddress =>
      widget.deliveryAddress ?? _draftDeliveryAddress;

  @override
  void initState() {
    super.initState();
    _loadVoucherPreview();
    _loadUnits();
    // Leads restore too - the draft table is keyed by (staff, account) and
    // never touches `user`, so nothing here depends on the account being a
    // registered customer.
    _loadDraft();
    // The narration field has no onChanged of its own, so watch the
    // controller instead of threading a callback through the Review sheet.
    _narration.addListener(_scheduleDraftSave);
  }

  // Restores this staff member's in-progress cart for this account so
  // closing the sheet (or the app) without checking out doesn't lose it.
  // Everything the user built comes back: line items - including hand-typed
  // ones the old `cart` table couldn't represent - plus extra charges,
  // narration, both dates and the delivery address.
  Future<void> _loadDraft() async {
    final draft = await ApiService.getOrderDraft(
      accountId: widget.accountId,
      accountType: widget.accountType,
    );
    if (!mounted) {
      _draftLoaded = true;
      return;
    }
    if (draft == null) {
      // No stored draft (or the fetch failed) - start clean, but allow
      // autosave from here on so this session still persists.
      setState(() => _draftLoaded = true);
      if (!_draftIsEmpty) _scheduleDraftSave();
      return;
    }

    setState(() {
      for (final raw in (draft['items'] as List?) ?? const []) {
        final r = Map<String, dynamic>.from(raw as Map);
        // This GET is fired from initState and the catalog is already
        // interactive while it's in flight, so the user can have added this
        // exact product+pack before the draft landed. Their live tap is the
        // more recent intent - keep it and skip the stored copy, rather than
        // ending up with the line twice.
        final productId = r['product_id']?.toString();
        final packId = r['pack_id']?.toString();
        if (productId != null &&
            _lineItems.any(
              (i) => i.productId == productId && i.packId == packId,
            )) {
          continue;
        }
        final item = OrderLineItem();
        item.product.text = (r['product_name'] ?? '').toString();
        item.productId = productId;
        item.packId = packId;
        item.packLabel = r['pack_label']?.toString();
        item.vendorProductId = r['vendor_product_id']?.toString();
        item.hsnCode = r['hsn_code']?.toString();
        item.gstPercent = (r['gst_percent'] as num?)?.toDouble() ?? 0;
        // Re-resolved against live vendor_products stock server-side, so a
        // draft that sat for days can't submit against a stale figure.
        item.maxQty = (r['max_qty'] as num?)?.toInt();
        item.unit = (r['unit'] ?? 'PCS').toString();
        item.qty.text = (r['quantity'] ?? '1').toString();
        item.unitPrice.text = (r['unit_price'] ?? '0').toString();
        _lineItems.add(item);
      }
      for (final raw in (draft['addons'] as List?) ?? const []) {
        final r = Map<String, dynamic>.from(raw as Map);
        final addon = OrderAddon((r['name'] ?? _addonNames.first).toString());
        addon.amount.text = (r['amount'] ?? '0').toString();
        _addons.add(addon);
      }
      // The addon editor starts collapsed, but a restored draft that has
      // charges should show them rather than hiding them behind the link.
      if (_addons.isNotEmpty) _showAddons = true;

      final narration = (draft['narration'] ?? '').toString();
      if (narration.isNotEmpty) {
        // Assigning fires the listener added in initState, which would
        // schedule a save of what is still being restored - _draftLoaded is
        // still false here, so that save is correctly suppressed.
        _narration.text = narration;
      }
      _documentDate = _parseIsoDate(draft['document_date']) ?? _documentDate;
      _expectedDate = _parseIsoDate(draft['expected_date']) ?? _expectedDate;

      final addr = draft['delivery_address'];
      if (addr is Map) _draftDeliveryAddress = Map<String, dynamic>.from(addr);

      _draftLoaded = true;
    });

    // Edits made while the GET was in flight were suppressed by the
    // _draftLoaded gate above; now that it's open, make sure they're stored
    // rather than waiting for the user's next tap.
    if (!_draftIsEmpty) _scheduleDraftSave();
  }

  static DateTime? _parseIsoDate(dynamic raw) {
    if (raw is! String || raw.trim().isEmpty) return null;
    return DateTime.tryParse(raw.trim());
  }

  // Everything the sheet would need to rebuild itself. Quantities and prices
  // are stored as their raw controller text so a restore is character-exact
  // rather than round-tripped through a double.
  Map<String, dynamic> _draftPayload() => {
    'items': _lineItems
        .map(
          (i) => {
            'product_name': i.product.text,
            'product_id': i.productId,
            'pack_id': i.packId,
            'pack_label': i.packLabel,
            'vendor_product_id': i.vendorProductId,
            'hsn_code': i.hsnCode,
            'gst_percent': i.gstPercent,
            'max_qty': i.maxQty,
            'unit': i.unit,
            'quantity': i.qty.text,
            'unit_price': i.unitPrice.text,
          },
        )
        .toList(),
    'addons': _addons
        .map((a) => {'name': a.name, 'amount': a.amount.text})
        .toList(),
    'narration': _narration.text,
    'document_date': _isoDate(_documentDate),
    'expected_date': _isoDate(_expectedDate),
    'delivery_address': _deliveryAddress,
  };

  // True once there's genuinely nothing worth restoring - an emptied cart
  // deletes its draft row instead of storing an empty one, so re-opening
  // starts clean rather than restoring a blank draft over fresh defaults.
  bool get _draftIsEmpty =>
      _lineItems.isEmpty && _addons.isEmpty && _narration.text.trim().isEmpty;

  // Called from every cart mutation. Coalesces a burst of edits into one
  // write and never blocks the UI - a failed save just means this particular
  // edit isn't there next time.
  void _scheduleDraftSave() {
    if (!_draftLoaded) return; // still restoring - don't overwrite the draft
    _draftDebounce?.cancel();
    _draftDebounce = Timer(_draftDebounceDelay, _saveDraftNow);
  }

  // Checkout hands the cart's contents to a real order (or, for a lead, to
  // the caller's local list), so the draft must not survive it. Ordering
  // matters: kill the pending autosave and latch _draftLoaded off FIRST, or
  // dispose()'s flush - which runs moments later when _closeAfterSave() pops
  // this route - would happily re-create the row we just deleted.
  Future<void> _discardDraft() async {
    _draftDebounce?.cancel();
    _draftDebounce = null;
    _draftLoaded = false;
    await ApiService.clearOrderDraft(
      accountId: widget.accountId,
      accountType: widget.accountType,
    );
  }

  void _saveDraftNow() {
    _draftDebounce?.cancel();
    _draftDebounce = null;
    if (!_draftLoaded) return;
    if (_draftIsEmpty) {
      ApiService.clearOrderDraft(
        accountId: widget.accountId,
        accountType: widget.accountType,
      );
      return;
    }
    ApiService.saveOrderDraft(
      accountId: widget.accountId,
      accountType: widget.accountType,
      payload: _draftPayload(),
    );
  }

  Future<void> _loadVoucherPreview() async {
    final next = await ApiService.getNextSalesOrderId();
    if (!mounted) return;
    setState(() => _voucherNo = next);
  }

  Future<void> _loadUnits() async {
    final units = await ApiService.getUnits();
    final names = units
        .map((u) => (u['unit_name'] as String?) ?? '')
        .where((u) => u.isNotEmpty)
        .toList();
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
    final picked = await showUnitPickerSheet(
      context,
      units: _units,
      selected: item.unit,
    );
    if (picked != null) {
      setState(() => item.unit = picked);
      _scheduleDraftSave();
    }
  }

  @override
  void dispose() {
    // A pending debounce would otherwise be cancelled with the timer, losing
    // the last edit when the user adds an item and immediately closes the
    // sheet. Fire it now - the request outlives this State, which is fine
    // because ApiService is static and needs no context.
    if (_draftDebounce?.isActive ?? false) _saveDraftNow();
    _draftDebounce?.cancel();
    _narration.removeListener(_scheduleDraftSave);
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
  double get _addonsTotal => _addons.fold(0, (s, a) => s + a.amountNum);
  double get _grandTotal => _grossAmount + _totalTax + _addonsTotal;
  int get _itemCount =>
      _lineItems.where((i) => i.product.text.trim().isNotEmpty).length;

  OutlineInputBorder _border([Color c = _fieldBorder]) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(11),
    borderSide: BorderSide(color: c),
  );

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
    child: Text(
      t.toUpperCase(),
      style: TextStyle(
        fontSize: 9.5,
        fontWeight: FontWeight.w700,
        letterSpacing: .5,
        color: Colors.grey.shade400,
      ),
    ),
  );

  List<Widget> _customerDetailRows() {
    final place = [
      widget.city,
      widget.state,
      widget.pincode,
    ].map((v) => (v ?? '').trim()).where((v) => v.isNotEmpty).join(', ');
    final rows = <String, String>{
      'Code': (widget.accountCode ?? '').trim(),
      'Phone': (widget.contactNumber ?? '').trim(),
      'GST No': (widget.gstNumber ?? '').trim(),
      'Area': (widget.areaName ?? '').trim(),
      'Place': place,
    }..removeWhere((_, v) => v.isEmpty);

    if (rows.isEmpty) return const [];

    return [
      const SizedBox(height: 8),
      ...rows.entries.map(
        (e) => Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '${e.key}: ',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: _ink,
                  ),
                ),
                TextSpan(
                  text: e.value,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w400,
                    color: _ink,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ];
  }

  Widget _voucherArrow(IconData icon, VoidCallback? onTap) => GestureDetector(
    onTap: onTap,
    behavior: HitTestBehavior.opaque,
    child: Container(
      width: 34,
      height: 38,
      alignment: Alignment.center,
      child: Icon(
        icon,
        size: 20,
        color: onTap != null ? kGoldDark : Colors.grey.shade300,
      ),
    ),
  );

  Widget _sheetHandle() => Center(
    child: Container(
      width: 42,
      height: 4,
      margin: const EdgeInsets.only(top: 8, bottom: 14),
      decoration: BoxDecoration(
        color: Colors.grey.shade300,
        borderRadius: BorderRadius.circular(3),
      ),
    ),
  );

  Widget _sheetCloseButton(VoidCallback? onTap, {Key? key}) => GestureDetector(
    key: key,
    onTap: onTap,
    behavior: HitTestBehavior.opaque,
    child: Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF141F1F).withValues(alpha: 0.08),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
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
      setState(
        () => expected ? _expectedDate = picked : _documentDate = picked,
      );
      _scheduleDraftSave();
    }
  }

  Future<void> _pickProduct(OrderLineItem item) async {
    final picked = await showCatalogProductPicker(context);
    if (picked != null) {
      setState(() {
        item.product.text = picked.product.text.trim();
        item.productId = picked.productId;
        item.packId = picked.packId;
        item.packLabel = picked.packLabel;
        item.vendorProductId = picked.vendorProductId;
        item.hsnCode = picked.hsnCode;
        item.maxQty = picked.maxQty;
        item.gstPercent = picked.gstPercent;
        // The catalog already knows a real qty/unit/price for this pack —
        // carry them over instead of leaving the form's previous values sitting there mismatched.
        item.qty.text = picked.qty.text;
        item.unit = picked.unit;
        item.unitPrice.text = picked.unitPrice.text;
      });
      picked.dispose();
      // The catalog picker's own pick never goes through _setCatalogQty (this
      // is a search-and-replace onto an existing manual-entry line, not a
      // catalog card's stepper), so it never reaches the persisted cart on
      // its own — sync it now rather than waiting for the next qty tap.
      _syncCartQty(item, item.qtyNum.round());
    }
  }

  // Current cart quantity for one product+pack — read by ProductCatalogSearch
  // so a card's stepper reflects reality (e.g. re-opening the catalog after
  // adding 3 of a pack shows "3", not a stepper reset back to 0).
  int catalogQtyFor(String productId, String? packId) {
    for (final i in _lineItems) {
      if (i.productId == productId && i.packId == packId)
        return i.qtyNum.round();
    }
    return 0;
  }

  // Fed by the catalog card's qty stepper on every +/-/picker change — finds
  // this exact product+pack's existing line and updates its quantity in
  // place (a stepper represents *one* live cart line, not a repeatable
  // one-shot "Add" action), creates one on the first increment from 0, and
  // removes it entirely once qty drops back to 0.
  void _setCatalogQty({
    required String productId,
    required String? packId,
    required int qty,
    required OrderLineItem Function() buildItem,
  }) {
    OrderLineItem? changed;
    setState(() {
      final idx = _lineItems.indexWhere(
        (i) => i.productId == productId && i.packId == packId,
      );
      if (qty <= 0) {
        if (idx != -1) {
          changed = _lineItems[idx];
          _lineItems.removeAt(idx);
        }
      } else if (idx != -1) {
        _lineItems[idx].qty.text = '$qty';
        changed = _lineItems[idx];
      } else {
        final item = buildItem()..qty.text = '$qty';
        _lineItems.add(item);
        changed = item;
      }
    });
    // Persist to sales_order_draft_crm so this survives closing the sheet or
    // the app — leads included, since the draft is keyed by (staff, account)
    // rather than a `user` row. Debounced and fire-and-forget: a failed save
    // never blocks the on-screen cart, it just means the next open won't
    // reflect this particular change.
    if (changed != null) _scheduleDraftSave();
    if (qty <= 0 && changed != null) changed!.dispose();
  }

  // Nested sheets (Customer & Dates / Review Order) are separate routes, so a
  // bare setState() on this State doesn't refresh what's already on screen
  // inside them — this updates the real data AND the open sheet's own
  // StatefulBuilder in one call.
  void _bump(StateSetter setModalState, VoidCallback fn) {
    setState(fn);
    setModalState(() {});
    // Every Review-sheet edit - addon add/remove/rename, addon amount typing,
    // item delete, manual item fields - goes through here, so one hook covers
    // all of them.
    _scheduleDraftSave();
  }

  String _isoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _submit() async {
    final validItems = _lineItems
        .where((i) => i.product.text.trim().isNotEmpty && i.qtyNum > 0)
        .toList();
    if (validItems.isEmpty) {
      Fluttertoast.showToast(
        msg: 'Add at least one product',
        backgroundColor: Colors.red,
        textColor: Colors.white,
      );
      return;
    }
    final itemsSummary = validItems
        .map((i) => i.product.text.trim())
        .join(', ');

    if (!_isCustomer) {
      // Lead - no real `user` row to attach an order to. Local draft only,
      // but from the user's point of view this Save *is* the checkout, so the
      // stored cart goes with it.
      await _discardDraft();
      if (!mounted) return;
      widget.onSave(
        itemsSummary,
        _grandTotal.round(),
        'Draft',
        'Pending',
        null,
      );
      _closeAfterSave();
      return;
    }

    final missingProduct = validItems
        .where((i) => i.productId == null)
        .toList();
    if (missingProduct.isNotEmpty) {
      Fluttertoast.showToast(
        msg: 'Select a real product from search for every item before saving',
        backgroundColor: Colors.red,
        textColor: Colors.white,
      );
      return;
    }

    setState(() => _saving = true);
    final result = await ApiService.createSalesOrder(
      buyerUserId: widget.accountId,
      // No tax_percent/sgst_percent/cgst_percent here — the server derives
      // those authoritatively from the product's own gst_percent, not from
      // whatever the client computed (see SalesOrderController::store).
      items: validItems
          .map(
            (i) => {
              'product_id': i.productId,
              'quantity': i.qtyNum,
              'item_price': i.priceNum,
              'unit': i.unit,
              // Stored server-side into orders_item.pinfo['ps'] and surfaced
              // back by OrderListController::getOrderDetail — so Order
              // Details can show which pack was actually sold, not just a
              // bare unit token.
              'pack_size': i.packLabel,
            },
          )
          .toList(),
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
      deliveryInfo: _deliveryAddress != null
          ? {
              'name': widget.name,
              'address': _deliveryAddress!['address'],
              'latitude': _deliveryAddress!['latitude'],
              'longitude': _deliveryAddress!['longitude'],
            }
          : null,
    );
    if (!mounted) return;
    setState(() => _saving = false);

    if (result == null) {
      Fluttertoast.showToast(
        msg: 'Could not create the order. Try again.',
        backgroundColor: Colors.red,
        textColor: Colors.white,
      );
      return;
    }

    final realOrderId = result['order_id']?.toString();
    final savedTotal = ((result['order_total'] as num?) ?? _grandTotal).round();
    // The order now owns these items - drop the draft so they don't keep
    // re-appearing next time this account's cart loads. Awaited (the old
    // fire-and-forget could lose the race against the sheet closing, leaving
    // an already-ordered cart to come back).
    await _discardDraft();
    if (!mounted) return;
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
          child: _customerDatesPanel(
            onClose: () => Navigator.of(dialogCtx).pop(),
          ),
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
          BoxShadow(
            color: const Color(0xFF141F1F).withValues(alpha: 0.04),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
          BoxShadow(
            color: const Color(0xFF141F1F).withValues(alpha: 0.08),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: _fieldBorder),
                ),
                child: const Icon(
                  Icons.edit_note_rounded,
                  size: 18,
                  color: Color(0xFF20242B),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Customer & Dates',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: kGoldDark,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Enter or update customer and document details',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ],
                ),
              ),
              GestureDetector(
                key: const Key('customerDatesCloseBtn'),
                onTap: onClose,
                behavior: HitTestBehavior.opaque,
                child: Icon(
                  Icons.close_rounded,
                  size: 20,
                  color: Colors.grey.shade500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Flexible(child: SingleChildScrollView(child: _customerDatesFields())),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onClose,
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: Colors.grey.shade300),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(13),
                    ),
                  ),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: Colors.black54,
                    ),
                  ),
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
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(13),
                    ),
                  ),
                  child: const Text(
                    'Save',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _customerDatesFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _label('Financial Year'),
                  Container(
                    height: 46,
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: _fieldBg,
                      borderRadius: BorderRadius.circular(11),
                      border: Border.all(color: _fieldBorder),
                    ),
                    child: Text(
                      _financialYear,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _label('Voucher No'),
                  Container(
                    height: 46,
                    padding: const EdgeInsets.only(left: 12, right: 4),
                    decoration: BoxDecoration(
                      color: _fieldBg,
                      borderRadius: BorderRadius.circular(11),
                      border: Border.all(color: _fieldBorder),
                    ),
                    // No real "previous voucher" to browse to here — this is always a
                    // *new* order, so only a refresh action makes sense (the preview
                    // can go stale if another order is created elsewhere meanwhile) —
                    // no left/previous arrow shown since there's nothing it could do.
                    child: Row(
                      children: [
                        Expanded(
                          child: _voucherNo == null
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: kGold,
                                  ),
                                )
                              : Text(
                                  '$_voucherNo',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                        ),
                        _voucherArrow(
                          Icons.refresh_rounded,
                          _loadVoucherPreview,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _label('Document Date *'),
                  InkWell(
                    borderRadius: BorderRadius.circular(11),
                    onTap: () => _pickDate(expected: false),
                    child: Container(
                      height: 46,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: _fieldBg,
                        borderRadius: BorderRadius.circular(11),
                        border: Border.all(color: _fieldBorder),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              _fmtDate(_documentDate),
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Icon(
                            Icons.calendar_today_rounded,
                            size: 15,
                            color: Colors.grey.shade500,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _label('Expected Date'),
                  InkWell(
                    borderRadius: BorderRadius.circular(11),
                    onTap: () => _pickDate(expected: true),
                    child: Container(
                      height: 46,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: _fieldBg,
                        borderRadius: BorderRadius.circular(11),
                        border: Border.all(color: _fieldBorder),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              _fmtDate(_expectedDate),
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Icon(
                            Icons.calendar_today_rounded,
                            size: 15,
                            color: Colors.grey.shade500,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _label('Customer'),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: _fieldBg,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: _fieldBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.name.trim().isEmpty ? 'Unnamed customer' : widget.name,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: widget.name.trim().isEmpty
                      ? Colors.grey.shade500
                      : null,
                ),
              ),
              ..._customerDetailRows(),
            ],
          ),
        ),
        if (_deliveryAddress != null) ...[
          const SizedBox(height: 14),
          _label('Delivery Address'),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: _fieldBg,
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: _fieldBorder),
            ),
            child: Text(
              '${_deliveryAddress!['address'] ?? ''}',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ],
        const SizedBox(height: 14),
        _label('Narration'),
        TextField(
          controller: _narration,
          maxLines: 3,
          decoration: _decor('', hint: 'Enter narration (optional)…'),
        ),
      ],
    );
  }

  // ── Cart (opens from the bottom cart FAB) ─────────────────────────────────

  void _openReviewSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setModalState) => Container(
          height: MediaQuery.of(sheetCtx).size.height * 0.92,
          padding: EdgeInsets.fromLTRB(
            18,
            8,
            18,
            14 + MediaQuery.of(sheetCtx).viewInsets.bottom,
          ),
          decoration: const BoxDecoration(
            color: _pageBg,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              _sheetHandle(),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Cart',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: _ink,
                      ),
                    ),
                  ),
                  _sheetCloseButton(
                    _saving ? null : () => Navigator.of(sheetCtx).pop(),
                    key: const Key('reviewCloseBtn'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Expanded(
                child: SingleChildScrollView(
                  // Web/desktop draws its scrollbar as an overlay on the
                  // right edge — without this, it sits right on top of each
                  // cart row's qty stepper (the rightmost thing in the row).
                  padding: const EdgeInsets.only(right: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _deliveryInfoBanner(),
                      Row(
                        children: [
                          const Text(
                            'Items',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: _ink,
                            ),
                          ),
                          const Spacer(),
                          GestureDetector(
                            // Real products (with real pack pricing) come from
                            // the catalog, not a blank hand-typed form — so
                            // "Add Item" just sends the telecaller back there
                            // instead of dropping an empty manual-entry row
                            // into the cart.
                            onTap: () => Navigator.of(sheetCtx).pop(),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.add_rounded,
                                  size: 15,
                                  color: kGoldDark,
                                ),
                                SizedBox(width: 2),
                                Text(
                                  'Add Item',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: kGoldDark,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      if (_lineItems.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          child: Center(
                            child: Text(
                              'Your cart is empty — go back and add products from the catalog.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 12.5,
                                color: Colors.grey.shade500,
                              ),
                            ),
                          ),
                        )
                      else
                        ..._lineItems.asMap().entries.map((entry) {
                          final idx = entry.key;
                          final item = entry.value;
                          // Items added from the catalog already have a real
                          // pack price/qty cap — shown as a compact cart row.
                          // Anything else (manually picked via the plain product
                          // search, which carries no pack pricing) still needs
                          // the full editable form so a price can be typed in.
                          final fromCatalog =
                              item.productId != null && item.packId != null;
                          return fromCatalog
                              ? _cartItemRow(item, setModalState)
                              : _manualItemForm(item, idx, setModalState);
                        }),
                      const SizedBox(height: 2),
                      _addChargesSection(setModalState),
                      const SizedBox(height: 10),
                      _billDetailsCard(),
                      const SizedBox(height: 10),
                      _cartFooterNote(),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _saving
                      ? null
                      : () async {
                          await _submit();
                          if (sheetCtx.mounted) setModalState(() {});
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kGold,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: kGold.withValues(alpha: 0.5),
                    elevation: 4,
                    shadowColor: kGold.withValues(alpha: 0.45),
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(13),
                    ),
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          _isCustomer
                              ? 'Place Order  |  ₹${_grandTotal.toStringAsFixed(0)}'
                              : 'Save',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Items added straight from the catalog already carry a real pack price —
  // this full editable form only fires for items with no pack behind them
  // (a product with no vendor pack pricing at all), which need a hand-typed
  // price. Its own "Product" search still opens the same catalog picker
  // (see _pickProduct/showCatalogProductPicker) — packId only stays null
  // here because that particular product genuinely has no pack to attach.
  Widget _manualItemForm(
    OrderLineItem item,
    int idx,
    StateSetter setModalState,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F6F7),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Item ${idx + 1}  |  HSN: NA',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Colors.grey.shade600,
                  ),
                ),
              ),
              if (_lineItems.length > 1)
                GestureDetector(
                  onTap: () => _bump(setModalState, () {
                    item.dispose();
                    _lineItems.removeAt(idx);
                  }),
                  child: const Icon(
                    Icons.delete_outline_rounded,
                    size: 18,
                    color: Color(0xFFC0584C),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          _label('Product *'),
          InkWell(
            borderRadius: BorderRadius.circular(11),
            onTap: () async {
              await _pickProduct(item);
              setModalState(() {});
            },
            child: IgnorePointer(
              child: TextField(
                controller: item.product,
                decoration: _decor('', hint: 'Tap to search…').copyWith(
                  suffixIcon: Icon(
                    Icons.search_rounded,
                    size: 18,
                    color: Colors.grey.shade500,
                  ),
                  suffixIconConstraints: const BoxConstraints(minWidth: 36),
                ),
              ),
            ),
          ),
          if (item.product.text.isNotEmpty && item.productId == null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Select a real product from search results',
                style: TextStyle(fontSize: 10.5, color: Colors.red.shade400),
              ),
            ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _label('Qty *'),
                    TextField(
                      controller: item.qty,
                      keyboardType: TextInputType.number,
                      onChanged: (v) => _bump(setModalState, () {
                        final cap = item.maxQty;
                        final n = int.tryParse(v.trim());
                        if (cap != null && n != null && n > cap) {
                          item.qty.text = '$cap';
                          item.qty.selection = TextSelection.collapsed(
                            offset: item.qty.text.length,
                          );
                        }
                      }),
                      decoration: _decor(
                        '',
                        hint: item.maxQty != null ? 'Max ${item.maxQty}' : null,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _label('Unit'),
                    InkWell(
                      borderRadius: BorderRadius.circular(11),
                      onTap: () async {
                        await _pickUnit(item);
                        setModalState(() {});
                      },
                      child: Container(
                        height: 46,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          color: _fieldBg,
                          borderRadius: BorderRadius.circular(11),
                          border: Border.all(color: _fieldBorder),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                item.unit,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: _ink,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            Icon(
                              Icons.keyboard_arrow_down_rounded,
                              size: 18,
                              color: Colors.grey.shade500,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _label('Unit Price (incl. tax) *'),
                    TextField(
                      controller: item.unitPrice,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      onChanged: (_) => _bump(setModalState, () {}),
                      decoration: _decor(''),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Divider(height: 1, color: kGold.withValues(alpha: 0.2)),
          const SizedBox(height: 10),
          if (item.gstPercent > 0) ...[
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: Text(
                    'Tax',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    'Tax %',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    'Tax Amount',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                const Expanded(
                  flex: 2,
                  child: Text(
                    'SGST',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    '${item.sgstPercent.toStringAsFixed(2)}%',
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontSize: 12.5),
                  ),
                ),
                Expanded(
                  child: Text(
                    item.sgstAmount.toStringAsFixed(2),
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontSize: 12.5),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                const Expanded(
                  flex: 2,
                  child: Text(
                    'CGST',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    '${item.cgstPercent.toStringAsFixed(2)}%',
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontSize: 12.5),
                  ),
                ),
                Expanded(
                  child: Text(
                    item.cgstAmount.toStringAsFixed(2),
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontSize: 12.5),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Divider(height: 1, color: kGold.withValues(alpha: 0.2)),
            const SizedBox(height: 10),
          ],
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _label('Gross Amount'),
                    Text(
                      item.grossAmount.toStringAsFixed(2),
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _label('Total Tax'),
                    Text(
                      item.taxNum.toStringAsFixed(2),
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _label('Product Total'),
                    Text(
                      item.productTotal.toStringAsFixed(2),
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: kGoldDark,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Compact cart row for a catalog-added item — image placeholder, name,
  // unit, a live qty stepper (mirrors the catalog card's own stepper so
  // adjusting it here stays consistent with adjusting it from the catalog),
  // and the line's total.
  Widget _cartItemRow(OrderLineItem item, StateSetter setModalState) {
    // The full pack label ("1 Pack of 5 Kg @ 195/-"), not just the bare
    // unit token — otherwise two different packs of the same product both
    // just say "Kg" and are indistinguishable in the cart.
    final packDetail = (item.packLabel?.trim().isNotEmpty ?? false)
        ? item.packLabel!.trim()
        : item.unit;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: _fieldBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: _fieldBg,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.inventory_2_outlined,
              size: 16,
              color: Colors.grey.shade400,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.product.text.trim(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: _ink,
                  ),
                ),
                Text(
                  packDetail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                ),
                Text(
                  '₹${item.productTotal.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: kGoldDark,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          _cartQtyStepper(item, setModalState),
        ],
      ),
    );
  }

  Widget _cartQtyStepper(OrderLineItem item, StateSetter setModalState) {
    final qty = item.qtyNum.round();
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: kGoldDark,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: () =>
                _bump(setModalState, () => _changeCartQty(item, qty - 1)),
            child: const Padding(
              padding: EdgeInsets.all(5),
              child: Icon(Icons.remove_rounded, size: 14, color: Colors.white),
            ),
          ),
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: Text(
              '$qty',
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: _ink,
              ),
            ),
          ),
          GestureDetector(
            onTap: () =>
                _bump(setModalState, () => _changeCartQty(item, qty + 1)),
            child: const Padding(
              padding: EdgeInsets.all(5),
              child: Icon(Icons.add_rounded, size: 14, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  // Dropping to 0 removes the line entirely (mirrors the catalog card's own
  // stepper — a qty of 0 means "not in the cart", not "an empty line").
  void _changeCartQty(OrderLineItem item, int newQty) {
    final cap = item.maxQty;
    var clamped = newQty < 0 ? 0 : newQty;
    if (cap != null && clamped > cap) {
      clamped = cap;
      Fluttertoast.showToast(
        msg: 'Only $cap in stock',
        backgroundColor: const Color(0xFFC0584C),
        textColor: Colors.white,
      );
    }
    if (clamped <= 0) {
      final idx = _lineItems.indexOf(item);
      if (idx != -1) {
        _lineItems.removeAt(idx);
      }
      _syncCartQty(item, 0);
      item.dispose();
      return;
    }
    item.qty.text = '$clamped';
    _syncCartQty(item, clamped);
  }

  // Shared by both qty-mutation paths (catalog card stepper and this review-
  // sheet stepper). The draft is stored whole, so unlike the old per-line
  // `cart` sync this needs nothing off the item itself - and hand-typed items
  // with no vendor pack now persist exactly like catalog ones.
  void _syncCartQty(OrderLineItem item, int qty) => _scheduleDraftSave();

  // Real data only — no fabricated "free delivery above ₹X" threshold, since
  // that business rule doesn't exist anywhere in this backend. Shows the
  // expected delivery date already picked in Customer & Dates, plus the
  // delivery-charge figure once extra charges are added.
  Widget _deliveryInfoBanner() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF2F9E57).withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.local_shipping_outlined,
            size: 15,
            color: Color(0xFF2F9E57),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Delivery Info',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF2F9E57),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _addonsTotal > 0
                      ? 'Delivery charge ₹${_addonsTotal.toStringAsFixed(0)}  ·  Expected by ${_fmtDate(_expectedDate)}'
                      : 'Expected by ${_fmtDate(_expectedDate)}',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF2F9E57),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Collapsed behind a link by default — most orders never need Hamali/
  // Transport/etc., so the plain item list + Bill Details stays the norm.
  Widget _addChargesSection(StateSetter setModalState) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () => _bump(setModalState, () => _showAddons = !_showAddons),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _showAddons
                    ? Icons.remove_circle_outline_rounded
                    : Icons.add_circle_outline_rounded,
                size: 15,
                color: kGoldDark,
              ),
              const SizedBox(width: 5),
              Text(
                _showAddons
                    ? 'Hide extra charges'
                    : 'Add extra charges (Hamali, Transport…)',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: kGoldDark,
                ),
              ),
            ],
          ),
        ),
        if (_showAddons) ...[
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
            ),
            child: _addonItems(setModalState),
          ),
        ],
      ],
    );
  }

  Widget _billDetailsCard() {
    final amount =
        _grossAmount + _totalTax; // == sum of each line's productTotal
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 13),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(13),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF141F1F).withValues(alpha: 0.04),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
          BoxShadow(
            color: const Color(0xFF141F1F).withValues(alpha: 0.05),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.receipt_long_outlined,
                size: 15,
                color: Colors.grey.shade600,
              ),
              const SizedBox(width: 5),
              const Text(
                'Bill Details',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: _ink,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                'Amount',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
              const Spacer(),
              Text(
                amount.toStringAsFixed(2),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Row(
            children: [
              Text(
                'Delivery Charges',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
              const Spacer(),
              Text(
                _addonsTotal.toStringAsFixed(2),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Divider(height: 1, color: kGold.withValues(alpha: 0.2)),
          const SizedBox(height: 8),
          Row(
            children: [
              const Text(
                'Total Amount',
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              Text(
                '₹${_grandTotal.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: kGoldDark,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // "Pay on Delivery" is accurate, not aspirational — SalesOrderController
  // hardcodes payment_method to 'cod' for every real order it creates.
  Widget _cartFooterNote() {
    if (_isCustomer) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Pay on Delivery',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: Color(0xFF2F9E57),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            'We sincerely request you to keep the payment ready and unload the stock as soon as possible.',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
          ),
        ],
      );
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFD98A2B).withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
      ),
      // Whether this is kept anywhere after Save depends on the caller (e.g.
      // the telecaller flow keeps a local list; others may not) — this sheet
      // itself has no way to guarantee persistence, so it doesn't claim one.
      child: const Text(
        'This account is a lead, not a registered customer yet — no real Sales Order will be created.',
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: Color(0xFFD98A2B),
        ),
      ),
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
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _label('Name'),
                      Container(
                        height: 46,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: _fieldBg,
                          borderRadius: BorderRadius.circular(11),
                          border: Border.all(color: _fieldBorder),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: addon.name,
                            isExpanded: true,
                            isDense: true,
                            style: const TextStyle(
                              fontSize: 13,
                              color: _ink,
                              fontWeight: FontWeight.w500,
                            ),
                            items: _addonNames
                                .map(
                                  (n) => DropdownMenuItem(
                                    value: n,
                                    child: Text(n),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) {
                              if (v != null)
                                _bump(setModalState, () => addon.name = v);
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _label('Amount'),
                      TextField(
                        controller: addon.amount,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        onChanged: (_) => _bump(setModalState, () {}),
                        decoration: _decor(''),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: GestureDetector(
                    onTap: () => _bump(setModalState, () {
                      addon.dispose();
                      _addons.removeAt(idx);
                    }),
                    child: const Icon(
                      Icons.delete_outline_rounded,
                      size: 18,
                      color: Color(0xFFC0584C),
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
        Align(
          alignment: Alignment.centerRight,
          child: OutlinedButton.icon(
            onPressed: () => _bump(
              setModalState,
              () => _addons.add(OrderAddon(_addonNames.first)),
            ),
            icon: const Icon(Icons.add_rounded, size: 15, color: kGoldDark),
            label: const Text(
              'Addons',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: kGoldDark,
              ),
            ),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: kGold),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Main screen: catalog-first ────────────────────────────────────────────

  Widget _header() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Expanded(
          child: Text(
            'Create Sales Order',
            style: TextStyle(
              fontSize: 15.5,
              fontWeight: FontWeight.w800,
              color: _ink,
            ),
          ),
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
      decoration: BoxDecoration(
        color: const Color(0xFFF3F3F4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            Icons.storefront_outlined,
            size: 18,
            color: Colors.grey.shade700,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              widget.name.trim().isEmpty ? 'Unnamed customer' : widget.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: _ink,
              ),
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
                border: Border.all(
                  color: _customerPanelOpen
                      ? kGold
                      : kGold.withValues(alpha: 0.5),
                ),
              ),
              child: Icon(Icons.edit_outlined, size: 16, color: kGoldDark),
            ),
          ),
        ],
      ),
    );
  }

  // Voice search (mic button + speech-to-text) lives inside ProductCatalogSearch
  // itself now, since it needs direct access to the search controller/debounce —
  // this panel just hosts it.
  Widget _productPanel() {
    return ProductCatalogSearch(
      onQtyChanged: _setCatalogQty,
      qtyFor: catalogQtyFor,
      secondaryHeader: _productPanelHeader(),
    );
  }

  // Replaces the old full-width "Review & Save" bar with a compact
  // floating cart button — a badge on it is enough to see there's
  // something to review; the bar's own real estate was crowding the
  // catalog list underneath it.
  Widget _cartFab() {
    final count = _itemCount;
    return Positioned(
      right: 0,
      bottom: 0,
      child: GestureDetector(
        key: const Key('cartBar'),
        onTap: _openReviewSheet,
        child: Container(
          width: 56,
          height: 56,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: kGold,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: kGold.withValues(alpha: 0.45),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              const Icon(
                Icons.shopping_cart_outlined,
                color: Colors.white,
                size: 24,
              ),
              if (count > 0)
                Positioned(
                  right: -8,
                  top: -8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 2,
                    ),
                    constraints: const BoxConstraints(minWidth: 18),
                    decoration: BoxDecoration(
                      color: const Color(0xFFC0584C),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white, width: 1.5),
                    ),
                    child: Text(
                      '$count',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height:
          MediaQuery.of(context).size.height -
          MediaQuery.of(context).padding.top,
      padding: EdgeInsets.fromLTRB(
        18,
        12,
        18,
        14 + MediaQuery.of(context).viewInsets.bottom,
      ),
      decoration: const BoxDecoration(
        color: _pageBg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sheetHandle(),
          _header(),
          const SizedBox(height: 2),
          Expanded(child: Stack(children: [_productPanel(), _cartFab()])),
        ],
      ),
    );
  }
}

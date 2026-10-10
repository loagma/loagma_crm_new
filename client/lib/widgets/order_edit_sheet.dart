import 'dart:async';

import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';

import '../screens/telecaller/telecaller_mock_data.dart' show kGold, kGoldDark;
import '../services/api_service.dart';
import 'create_sales_order_sheet.dart' show OrderLineItem;
import 'product_catalog_search.dart';

/// Edit a pending CRM order: change quantities, remove items, add items from
/// the catalog and change add-on charges. The server re-prices everything
/// exactly like placing (live price, units_master stock, offers, delivery
/// charge, the order's own promo) and moves stock by the difference only.
/// Returns true when the change was saved.
Future<bool> showOrderEditSheet(BuildContext context, Map<String, dynamic> order) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _OrderEditSheet(order: order),
  );
  return saved == true;
}

class _Line {
  final String productId, vendorProductId, packId, name, pack;
  int qty;
  _Line(this.productId, this.vendorProductId, this.packId, this.name, this.pack, this.qty);
  String get key => '$vendorProductId|$packId';
  Map<String, dynamic> get body => {
        'product_id': int.parse(productId),
        'vendor_product_id': int.parse(vendorProductId),
        'pack_id': packId,
        'quantity': qty,
      };
}

class _Charge {
  String name;
  String? remarks; // kept as saved (PMS shows it on the invoice)
  final amount = TextEditingController();
  _Charge(this.name, num value, {this.remarks}) {
    amount.text = value.abs() == value.abs().roundToDouble() ? value.abs().toStringAsFixed(0) : value.abs().toString();
  }
  double get value => double.tryParse(amount.text.trim()) ?? 0;
}

class _OrderEditSheet extends StatefulWidget {
  final Map<String, dynamic> order;
  const _OrderEditSheet({required this.order});

  @override
  State<_OrderEditSheet> createState() => _OrderEditSheetState();
}

class _OrderEditSheetState extends State<_OrderEditSheet> {
  // same list as the order sheet / PMS
  static const _chargeNames = ['Hamali', 'Freight', 'Packing', 'Others', 'Discount', 'Round off'];

  late final String _orderId = '${widget.order['order_id']}';
  final List<_Line> _lines = [];
  final List<_Charge> _charges = [];
  Map<String, dynamic>? _bill;
  String? _error;
  bool _loading = false, _saving = false;
  int _seq = 0;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    for (final raw in (widget.order['items'] as List?) ?? const []) {
      final it = Map<String, dynamic>.from(raw as Map);
      if (it['free'] == true || it['vendor_product_id'] == null || it['pack_id'] == null) continue; // free items are recomputed
      _lines.add(_Line('${it['product_id']}', '${it['vendor_product_id']}', '${it['pack_id']}', '${it['name'] ?? ''}',
          '${it['pack_size'] ?? ''}', (it['quantity'] as num?)?.toInt() ?? 1));
    }
    for (final raw in (widget.order['charges'] as List?) ?? const []) {
      final c = Map<String, dynamic>.from(raw as Map);
      var name = '${c['name']}';
      String? remarks = c['remarks'] == null ? null : '${c['remarks']}';
      // stored as Others + remarks "Packing" → shown as Packing again
      if (name == 'Others' && remarks == 'Packing') {
        name = 'Packing';
        remarks = null;
      }
      _charges.add(_Charge(_chargeNames.contains(name) ? name : 'Others', (c['amount'] as num?) ?? 0, remarks: remarks));
    }
    final roundOff = (widget.order['round_off'] as num?) ?? 0; // orders.bill_roff
    if (roundOff != 0) _charges.add(_Charge('Round off', roundOff));
    _refresh();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    for (final c in _charges) {
      c.amount.dispose();
    }
    super.dispose();
  }

  List<Map<String, dynamic>> get _chargeBody => _charges
      .where((c) => c.value != 0)
      .map((c) => {
            'name': c.name,
            // round off keeps its sign as typed; discount always negative
            'amount': c.name == 'Discount' ? -c.value.abs() : c.value,
            if (c.remarks != null && c.remarks!.isNotEmpty) 'remarks': c.remarks,
          })
      .toList();

  void _changed() {
    setState(() {});
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 450), _refresh);
  }

  Future<void> _refresh() async {
    if (_lines.isEmpty) {
      setState(() {
        _bill = null;
        _error = 'An order needs at least one item. To remove everything, cancel the order instead.';
      });
      return;
    }
    final seq = ++_seq;
    setState(() => _loading = true);
    final res = await ApiService.previewOrderEdit(_orderId,
        items: _lines.map((l) => l.body).toList(), charges: _chargeBody);
    if (!mounted || seq != _seq) return;
    setState(() {
      _loading = false;
      if (res['success'] == true) {
        _bill = Map<String, dynamic>.from(res['data'] as Map);
        _error = null;
      } else {
        _bill = null;
        _error = '${res['message']}';
      }
    });
  }

  Future<void> _save() async {
    final bill = _bill;
    if (bill == null || _error != null || _loading) return;
    setState(() => _saving = true);
    final res = await ApiService.updateOrder(_orderId,
        items: _lines.map((l) => l.body).toList(),
        charges: _chargeBody,
        totalAmount: (bill['total'] as num).toDouble());
    if (!mounted) return;
    setState(() => _saving = false);
    if (res['success'] == true) {
      Fluttertoast.showToast(msg: 'Order #$_orderId updated', backgroundColor: const Color(0xFF43A047), textColor: Colors.white);
      Navigator.of(context).pop(true);
    } else {
      Fluttertoast.showToast(msg: '${res['message']}', backgroundColor: Colors.red, textColor: Colors.white);
      _refresh();
    }
  }

  // Same catalog as Create Sales Order (units_master stock limits); picks are
  // merged into this order's lines when the catalog closes.
  Future<void> _addItems() async {
    final picked = <String, OrderLineItem>{};
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Container(
          height: MediaQuery.of(ctx).size.height * 0.9,
          padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + MediaQuery.of(ctx).viewInsets.bottom),
          decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
          child: Column(
            children: [
              Row(children: [
                const Expanded(child: Text('Add Item', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
                IconButton(onPressed: () => Navigator.of(ctx).pop(), icon: const Icon(Icons.close_rounded)),
              ]),
              Expanded(
                child: ProductCatalogSearch(
                  qtyFor: (productId, packId) => int.tryParse(
                          picked['$productId|${packId ?? ''}']?.qty.text ?? '') ??
                      0,
                  onQtyChanged: ({required productId, required packId, required qty, required buildItem}) {
                    setSheet(() {
                      final k = '$productId|${packId ?? ''}';
                      picked.remove(k)?.dispose();
                      if (qty > 0) picked[k] = buildItem()..qty.text = '$qty';
                    });
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (picked.isEmpty || !mounted) return;
    for (final item in picked.values) {
      if (item.productId != null && item.vendorProductId != null && item.packId != null) {
        final line = _Line(item.productId!, item.vendorProductId!, item.packId!, item.product.text.trim(),
            item.packLabel ?? '', item.qtyNum.round());
        final existing = _lines.where((l) => l.key == line.key).toList();
        if (existing.isNotEmpty) {
          existing.first.qty += line.qty;
        } else {
          _lines.add(line);
        }
      }
      item.dispose();
    }
    _changed();
  }

  Widget _lineRow(_Line l) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: const Color(0xFFFAFAFA), borderRadius: BorderRadius.circular(10)),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(l.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700), maxLines: 2, overflow: TextOverflow.ellipsis),
              if (l.pack.isNotEmpty) Text(l.pack, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
            ]),
          ),
          IconButton(
            onPressed: () {
              if (l.qty > 1) {
                l.qty--;
              } else {
                _lines.remove(l);
              }
              _changed();
            },
            icon: const Icon(Icons.remove_circle_outline_rounded, color: kGoldDark),
          ),
          Text('${l.qty}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
          IconButton(onPressed: () { l.qty++; _changed(); }, icon: const Icon(Icons.add_circle_outline_rounded, color: kGoldDark)),
          IconButton(onPressed: () { _lines.remove(l); _changed(); }, icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFE53935))),
        ]),
      );

  Widget _chargeRow(_Charge c) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(children: [
          Expanded(
            child: DropdownButtonFormField<String>(
              initialValue: c.name,
              isDense: true,
              decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
              items: _chargeNames.map((n) => DropdownMenuItem(value: n, child: Text(n))).toList(),
              onChanged: (v) { if (v != null) { c.name = v; _changed(); } },
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: c.amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(isDense: true, border: OutlineInputBorder(), prefixText: '₹ '),
              onChanged: (_) => _changed(),
            ),
          ),
          IconButton(
            onPressed: () { _charges.remove(c); c.amount.dispose(); _changed(); },
            icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFE53935)),
          ),
        ]),
      );

  Widget _billRow(String l, String v, {bool bold = false, Color? color}) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(children: [
          Expanded(child: Text(l, style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700, fontWeight: bold ? FontWeight.w800 : null))),
          Text(v, style: TextStyle(fontSize: 13, fontWeight: bold ? FontWeight.w800 : FontWeight.w600, color: color)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final b = _bill;
    double n(String k) => (b?[k] as num?)?.toDouble() ?? 0;
    final free = ((b?['vendors'] as List?) ?? const []).expand((v) => ((v as Map)['free_items'] as List?) ?? const []).toList();
    return Container(
      height: MediaQuery.of(context).size.height * 0.92,
      padding: EdgeInsets.fromLTRB(16, 10, 16, 14 + MediaQuery.of(context).viewInsets.bottom),
      decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      child: Column(children: [
        Row(children: [
          Expanded(child: Text('Edit Order #$_orderId', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
          IconButton(onPressed: () => Navigator.of(context).pop(false), icon: const Icon(Icons.close_rounded)),
        ]),
        Expanded(
          child: ListView(children: [
            Row(children: [
              const Expanded(child: Text('Items', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800))),
              TextButton.icon(onPressed: _addItems, icon: const Icon(Icons.add_rounded, color: kGoldDark),
                  label: const Text('Add Item', style: TextStyle(color: kGoldDark, fontWeight: FontWeight.w700))),
            ]),
            ..._lines.map(_lineRow),
            const SizedBox(height: 8),
            Row(children: [
              const Expanded(child: Text('Add-on charges (added on invoice)', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800))),
              TextButton.icon(
                onPressed: () { _charges.add(_Charge(_chargeNames.first, 0)); setState(() {}); },
                icon: const Icon(Icons.add_rounded, color: kGoldDark),
                label: const Text('Charge', style: TextStyle(color: kGoldDark, fontWeight: FontWeight.w700)),
              ),
            ]),
            ..._charges.map(_chargeRow),
            const Divider(height: 24),
            Row(children: [
              const Expanded(child: Text('New bill', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800))),
              if (_loading) const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: kGold)),
            ]),
            if (_error != null)
              Padding(padding: const EdgeInsets.only(top: 6), child: Text(_error!, style: const TextStyle(color: Color(0xFFC0584C), fontWeight: FontWeight.w600)))
            else if (b != null) ...[
              _billRow('Items (${b['items_count'] ?? 0})', (n('before_discount') - n('delivery_charge')).toStringAsFixed(2)),
              _billRow('Delivery charge', n('delivery_charge') > 0 ? n('delivery_charge').toStringAsFixed(2) : 'Free'),
              if (n('offer_discount') > 0) _billRow('Offer discount', '−${n('offer_discount').toStringAsFixed(2)}', color: const Color(0xFF2F9E57)),
              if (n('promo_discount') > 0) _billRow('Promo discount', '−${n('promo_discount').toStringAsFixed(2)}', color: const Color(0xFF2F9E57)),
              for (final f in free) _billRow('Free: ${(f as Map)['name']} × ${f['quantity']}', '₹0', color: const Color(0xFF2F9E57)),
              for (final c in (b['charges'] as List?) ?? const [])
                _billRow('${(c as Map)['name']}${c['remarks'] != null ? ' (${c['remarks']})' : ''} — on invoice', '${(c['amount'] as num) < 0 ? '−' : '+'}${(c['amount'] as num).abs().toStringAsFixed(2)}', color: kGoldDark),
              if (n('round_off') != 0)
                _billRow('Round off — on invoice', '${n('round_off') < 0 ? '−' : '+'}${n('round_off').abs().toStringAsFixed(2)}', color: kGoldDark),
              const Divider(height: 18),
              _billRow('Order total', '₹${n('total').toStringAsFixed(2)}', bold: true),
            ],
          ]),
        ),
        SizedBox(
          width: double.infinity,
          height: 46,
          child: ElevatedButton(
            onPressed: _saving || _loading || _bill == null || _error != null ? null : _save,
            style: ElevatedButton.styleFrom(backgroundColor: kGold, foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            child: _saving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text(_bill == null ? 'Save changes' : 'Save changes  |  ₹${n('total').toStringAsFixed(0)}',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          ),
        ),
      ]),
    );
  }
}

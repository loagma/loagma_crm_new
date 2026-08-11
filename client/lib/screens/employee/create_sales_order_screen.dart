import 'package:flutter/material.dart';

import '../../services/api_service.dart';
import '../../widgets/order_item_form_sheet.dart';

/// Lightweight "Take Order" flow reached from Order Details (order_funnel_screen).
/// Reuses the same item-picker sheet and createSalesOrder API the telecaller
/// voucher screen uses — this is the plain-order equivalent for a salesman,
/// without the GST/financial-year fields that only apply to that voucher.
class CreateSalesOrderScreen extends StatefulWidget {
  final String buyerUserId;
  final String shopName;
  final String ownerName;
  final String address;
  final double? latitude;
  final double? longitude;
  final String? areaName;

  const CreateSalesOrderScreen({
    super.key,
    required this.buyerUserId,
    required this.shopName,
    this.ownerName = '',
    this.address = '',
    this.latitude,
    this.longitude,
    this.areaName,
  });

  @override
  State<CreateSalesOrderScreen> createState() => _CreateSalesOrderScreenState();
}

class _CreateSalesOrderScreenState extends State<CreateSalesOrderScreen> {
  static const _gold = Color(0xFFD7BE69);
  static const _green = Color(0xFF43A047);

  final List<Map<String, dynamic>> _items = [];
  final _narrationCtrl = TextEditingController();
  final _discountCtrl = TextEditingController(text: '0');
  final _deliveryChargeCtrl = TextEditingController(text: '0');

  bool _saving = false;
  int? _nextOrderId;

  @override
  void initState() {
    super.initState();
    _loadNextOrderId();
  }

  @override
  void dispose() {
    _narrationCtrl.dispose();
    _discountCtrl.dispose();
    _deliveryChargeCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadNextOrderId() async {
    final next = await ApiService.getNextSalesOrderId();
    if (mounted) setState(() => _nextOrderId = next);
  }

  double _toDouble(String raw) => double.tryParse(raw.trim()) ?? 0;
  double get _discount => _toDouble(_discountCtrl.text);
  double get _deliveryCharge => _toDouble(_deliveryChargeCtrl.text);
  double get _beforeDiscount =>
      _items.fold(0.0, (s, i) => s + ((i['item_total'] as num?)?.toDouble() ?? 0));
  double get _grandTotal {
    final t = _beforeDiscount - _discount + _deliveryCharge;
    return t < 0 ? 0 : t;
  }

  Future<void> _addItem() async {
    final result = await showOrderItemFormSheet(context, itemNumber: _items.length + 1);
    if (result == null || !mounted) return;
    setState(() => _items.add(result));
  }

  Future<void> _editItem(int index) async {
    final result = await showOrderItemFormSheet(context, initial: _items[index], itemNumber: index + 1);
    if (result == null || !mounted) return;
    setState(() => _items[index] = result);
  }

  void _removeItem(int index) => setState(() => _items.removeAt(index));

  String _isoToday() {
    final d = DateTime.now();
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  Future<void> _placeOrder() async {
    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one item before placing the order')),
      );
      return;
    }

    setState(() => _saving = true);
    final hasDeliveryInfo = widget.address.isNotEmpty ||
        (widget.latitude != null && widget.longitude != null);

    final result = await ApiService.createSalesOrder(
      buyerUserId: widget.buyerUserId,
      items: _items
          .map((i) => {
                'product_id': i['product_id'],
                'quantity': i['quantity'],
                'item_price': i['item_price'],
                'unit': i['unit'] ?? 'PCS',
              })
          .toList(),
      discount: _discount,
      deliveryCharge: _deliveryCharge,
      narration: _narrationCtrl.text.trim().isEmpty ? null : _narrationCtrl.text.trim(),
      areaName: widget.areaName?.isNotEmpty == true ? widget.areaName : null,
      documentDate: _isoToday(),
      deliveryInfo: hasDeliveryInfo
          ? {
              'name': widget.shopName,
              'address': widget.address,
              'latitude': widget.latitude,
              'longitude': widget.longitude,
            }
          : null,
    );

    if (!mounted) return;
    setState(() => _saving = false);

    if (result == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not create the order. Try again.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final orderId = result['order_id']?.toString() ?? '';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(orderId.isEmpty ? 'Order placed' : 'Order #$orderId placed successfully'),
        backgroundColor: _green,
      ),
    );
    Navigator.of(context).pop(orderId);
  }

  InputDecoration _decor({String? hint}) => InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
        isDense: true,
        filled: true,
        fillColor: const Color(0xFFFAFAFA),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(11), borderSide: BorderSide(color: Colors.grey.shade300)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(11), borderSide: BorderSide(color: Colors.grey.shade300)),
        focusedBorder:
            OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: const BorderSide(color: _gold)),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: Text(_nextOrderId != null ? 'New Order · #$_nextOrderId' : 'New Sales Order'),
        backgroundColor: _gold,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(14),
              children: [
                _accountCard(),
                const SizedBox(height: 14),
                _itemsCard(),
                const SizedBox(height: 14),
                _chargesCard(),
                const SizedBox(height: 14),
              ],
            ),
          ),
          _bottomBar(),
        ],
      ),
    );
  }

  Widget _card({required Widget child}) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFEEEEEE)),
          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 1))],
        ),
        child: child,
      );

  Widget _accountCard() => _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.shopName.isEmpty ? '—' : widget.shopName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            if (widget.ownerName.isNotEmpty) ...[
              const SizedBox(height: 3),
              Text(widget.ownerName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            ],
            if (widget.address.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(widget.address,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            ],
          ],
        ),
      );

  Widget _itemsCard() => _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text('Items',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                ),
                GestureDetector(
                  onTap: _addItem,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: _gold.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: _gold.withValues(alpha: 0.4)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.add_rounded, size: 15, color: Color(0xFFB89A3E)),
                        SizedBox(width: 5),
                        Text('Add Item',
                            style: TextStyle(
                                fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFFB89A3E))),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (_items.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text('No items added yet. Tap "Add Item" to start.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600)),
              )
            else
              ..._items.asMap().entries.map((e) => _itemRow(e.key, e.value)),
          ],
        ),
      );

  Widget _itemRow(int index, Map<String, dynamic> item) {
    final name = (item['name'] ?? 'Item').toString();
    final pack = (item['pack_size'] ?? '').toString();
    final qty = (item['quantity'] as num?)?.toInt() ?? 0;
    final unit = (item['unit'] ?? 'PCS').toString();
    final total = (item['item_total'] as num?)?.toDouble() ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAFA),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                if (pack.isNotEmpty)
                  Text(pack, style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                Text('Qty: $qty $unit',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text('₹${total.toStringAsFixed(2)}',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: () => _editItem(index),
            child: Container(
              width: 30, height: 30,
              decoration: BoxDecoration(
                  color: _gold.withValues(alpha: 0.12), shape: BoxShape.circle),
              child: const Icon(Icons.edit_rounded, size: 14, color: Color(0xFFD7BE69)),
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: () => _removeItem(index),
            child: Container(
              width: 30, height: 30,
              decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.10), shape: BoxShape.circle),
              child: const Icon(Icons.delete_outline_rounded, size: 14, color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chargesCard() => _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Charges & Notes',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Discount (₹)', style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
                      const SizedBox(height: 5),
                      TextField(
                        controller: _discountCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        onChanged: (_) => setState(() {}),
                        decoration: _decor(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Delivery Charge (₹)', style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
                      const SizedBox(height: 5),
                      TextField(
                        controller: _deliveryChargeCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        onChanged: (_) => setState(() {}),
                        decoration: _decor(),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text('Notes', style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
            const SizedBox(height: 5),
            TextField(
              controller: _narrationCtrl,
              maxLines: 2,
              decoration: _decor(hint: 'Optional notes for this order...'),
            ),
            const Divider(height: 26),
            _summaryRow('Before Discount', _beforeDiscount),
            _summaryRow('Discount', -_discount),
            _summaryRow('Delivery Charge', _deliveryCharge),
            const SizedBox(height: 4),
            _summaryRow('Grand Total', _grandTotal, bold: true),
          ],
        ),
      );

  Widget _summaryRow(String label, double value, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Expanded(
              child: Text(label,
                  style: TextStyle(
                      fontSize: bold ? 13.5 : 12.5,
                      fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
                      color: bold ? Colors.black87 : Colors.grey.shade600)),
            ),
            Text('₹${value.toStringAsFixed(2)}',
                style: TextStyle(
                    fontSize: bold ? 13.5 : 12.5,
                    fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                    color: bold ? Colors.black87 : Colors.grey.shade800)),
          ],
        ),
      );

  Widget _bottomBar() => SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8, offset: const Offset(0, -2))],
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Total', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                    Text('₹${_grandTotal.toStringAsFixed(2)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton(
                onPressed: _saving ? null : _placeOrder,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _gold,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 18, height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Place Order',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
      );
}

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/api_service.dart';
import '../../services/invoice_printer.dart';
import '../../widgets/single_location_map_screen.dart';
import 'order_list_screen.dart';

class OrderDetailScreen extends StatefulWidget {
  final String orderId;
  final List<String>? orderIds; // sibling order IDs to swipe through, if opened from a list
  final int initialIndex;

  const OrderDetailScreen({
    super.key,
    required this.orderId,
    this.orderIds,
    this.initialIndex = 0,
  });

  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen> {
  static const _gold = Color(0xFFD7BE69);

  bool _loading = true;
  Map<String, dynamic>? _order;
  late int _index;

  String get _currentOrderId =>
      (widget.orderIds != null && widget.orderIds!.isNotEmpty)
          ? widget.orderIds![_index]
          : widget.orderId;

  bool get _hasPrev => widget.orderIds != null && _index > 0;
  bool get _hasNext => widget.orderIds != null && _index < widget.orderIds!.length - 1;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final data = await ApiService.getOrderDetail(_currentOrderId);
    if (!mounted) return;
    setState(() { _order = data; _loading = false; });
  }

  void _goPrev() {
    if (!_hasPrev) return;
    setState(() => _index--);
    _load();
  }

  void _goNext() {
    if (!_hasNext) return;
    setState(() => _index++);
    _load();
  }

  Future<void> _launch(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  void _call(String phone) => _launch('tel:$phone');

  void _whatsapp(String phone) {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    final number = digits.length == 10 ? '91$digits' : digits;
    _launch('https://wa.me/$number');
  }

  void _printInvoice() => InvoicePrinter.print(context, _currentOrderId, preloaded: _order);

  double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: Text('Order #$_currentOrderId'),
        backgroundColor: _gold,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: _load),
        ],
      ),
      body: Stack(
        children: [
          _loading
              ? const Center(child: CircularProgressIndicator(color: _gold))
              : _order == null
                  ? Center(
                      child: Text('Order not found', style: TextStyle(fontSize: 14, color: Colors.grey.shade500)),
                    )
                  : _buildBody(_order!),
          if (widget.orderIds != null) ...[
            Positioned(
              left: 6,
              top: 0, bottom: 0,
              child: Center(child: _navArrow(Icons.chevron_left_rounded, _hasNext ? _goNext : null)),
            ),
            Positioned(
              right: 6,
              top: 0, bottom: 0,
              child: Center(child: _navArrow(Icons.chevron_right_rounded, _hasPrev ? _goPrev : null)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _navArrow(IconData icon, VoidCallback? onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 36, height: 36,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: onTap != null ? 0.92 : 0.5),
        shape: BoxShape.circle,
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
      ),
      child: Icon(icon, size: 22, color: onTap != null ? Colors.black87 : Colors.black26),
    ),
  );

  Widget _buildBody(Map<String, dynamic> o) {
    final shop        = (o['shop_name'] ?? '').toString();
    final ownerName   = (o['owner_name'] ?? '').toString();
    final ownerContact = (o['owner_contact'] ?? '').toString();
    final address     = (o['delivery_address'] ?? '').toString();
    final lat         = _toDouble(o['latitude']);
    final lng         = _toDouble(o['longitude']);
    final state       = (o['order_state'] ?? '').toString();
    final payment     = (o['payment_status'] ?? '').toString();
    final method      = (o['payment_method'] ?? '').toString();
    final total       = _toDouble(o['order_total']) ?? 0;
    final beforeDisc  = _toDouble(o['before_discount']) ?? 0;
    final discount    = _toDouble(o['discount']) ?? 0;
    final deliveryChg = _toDouble(o['delivery_charge']) ?? 0;
    final items       = (o['items'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final itemsCount  = (o['items_count'] as int?) ?? items.length;
    final orderDt     = (o['order_datetime'] ?? '').toString();
    final deliveryW   = (o['delivery_window'] ?? '').toString();
    final driver      = o['driver'] as Map<String, dynamic>?;
    final buyerId     = (o['buyer_userid'] ?? '').toString();

    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        // ── Owner card ────────────────────────────────────────────────
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _label('Shop Name'),
                        Text(shop.isEmpty ? '—' : shop,
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 8),
                        _label('Owner Name'),
                        Text(ownerName.isEmpty ? '—' : ownerName,
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        _label('Owner Contact'),
                        Text(ownerContact.isEmpty ? '—' : ownerContact,
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                  Column(
                    children: [
                      const Text('Actions', style: TextStyle(fontSize: 11, color: Colors.black45)),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          if (ownerContact.isNotEmpty) ...[
                            _iconBtn(Icons.call_rounded, const Color(0xFF1976D2), () => _call(ownerContact)),
                            const SizedBox(width: 6),
                            _iconBtn(Icons.chat_rounded, const Color(0xFF25D366), () => _whatsapp(ownerContact)),
                            const SizedBox(width: 6),
                          ],
                          _iconBtn(Icons.print_rounded, const Color(0xFF43A047), _printInvoice),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
              if (address.isNotEmpty) ...[
                const SizedBox(height: 10),
                _label('Delivery Address'),
                GestureDetector(
                  onTap: (lat != null && lng != null)
                      ? () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => SingleLocationMapScreen(
                              title: shop.isNotEmpty ? shop : ownerName,
                              subtitle: address,
                              latitude: lat,
                              longitude: lng,
                            ),
                          ),
                        )
                      : null,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(address, style: const TextStyle(fontSize: 12.5, color: Colors.black87)),
                      ),
                      if (lat != null && lng != null) ...[
                        const SizedBox(width: 6),
                        const Icon(Icons.location_on_rounded, size: 16, color: Color(0xFFE53935)),
                      ],
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _tabBtn('Owner Order History', _gold, () {
                      if (buyerId.isEmpty) return;
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => OrderListScreen(
                            buyerUserId: buyerId,
                            title: ownerName.isEmpty ? 'Owner Orders' : "$ownerName's Orders",
                          ),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _tabBtn('Product-wise History', const Color(0xFF37474F), () {
                      if (buyerId.isEmpty) return;
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => _ProductHistoryScreen(buyerUserId: buyerId, ownerName: ownerName),
                        ),
                      );
                    }),
                  ),
                ],
              ),
            ],
          ),
        ),

        // ── Status / Payment / Total ─────────────────────────────────────
        _card(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          child: Row(
            children: [
              Expanded(child: _statBox('Status', state, _stateColor(state))),
              Expanded(child: _statBox('Payment', payment, _paymentColor(payment))),
              Expanded(child: _statBox('Total', '₹${total.toStringAsFixed(2)}', Colors.black87)),
            ],
          ),
        ),

        // ── Driver details ────────────────────────────────────────────────
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionHeader(Icons.local_shipping_rounded, 'Driver Details'),
              const SizedBox(height: 10),
              if (driver == null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text('Driver not assigned yet.',
                      style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600)),
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text((driver['name'] ?? '').toString(),
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                          Text((driver['mobile'] ?? '').toString(),
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                        ],
                      ),
                    ),
                    if ((driver['mobile'] ?? '').toString().isNotEmpty)
                      _iconBtn(Icons.call_rounded, const Color(0xFF1976D2),
                          () => _call((driver['mobile']).toString())),
                  ],
                ),
            ],
          ),
        ),

        // ── Items ─────────────────────────────────────────────────────────
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionHeader(Icons.shopping_bag_rounded, 'Items ($itemsCount)'),
              const SizedBox(height: 10),
              ...items.map((item) {
                final name  = (item['name'] ?? 'Item').toString();
                final pack  = (item['pack_size'] ?? '').toString();
                final qty   = (item['quantity'] as int?) ?? 0;
                final deliv = (item['qty_delivered'] as int?) ?? 0;
                final total = _toDouble(item['item_total']) ?? 0;
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFAFAFA),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 44, height: 44,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.image_outlined, color: Colors.grey, size: 20),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(name,
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                                maxLines: 2, overflow: TextOverflow.ellipsis),
                            if (pack.isNotEmpty)
                              Text(pack, style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                            Text('Qty: $qty  |  Delivered: $deliv',
                                style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                          ],
                        ),
                      ),
                      Text('₹${total.toStringAsFixed(2)}',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),

        // ── Order summary ────────────────────────────────────────────────
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionHeader(Icons.receipt_long_rounded, 'Order Summary'),
              const SizedBox(height: 10),
              _summaryRow('Status', state),
              _summaryRow('Payment', payment),
              _summaryRow('Method', method),
              _summaryRow('Time Slot', deliveryW),
              _summaryRow('Order Date', orderDt),
              _summaryRow('Items', '$itemsCount'),
              _summaryRow('Before Discount', '₹${beforeDisc.toStringAsFixed(2)}'),
              _summaryRow('Discount', '₹${discount.toStringAsFixed(2)}'),
              _summaryRow('Delivery Charge', '₹${deliveryChg.toStringAsFixed(2)}'),
              _summaryRow('Total', '₹${total.toStringAsFixed(2)}', bold: true),
            ],
          ),
        ),
      ],
    );
  }

  // ── Small helpers ─────────────────────────────────────────────────────────

  Color _stateColor(String s) => const {
    'pending':    Color(0xFFD7BE69),
    'registered': Color(0xFF607D8B),
    'invoiced':   Color(0xFF1976D2),
    'completed':  Color(0xFF43A047),
    'cancelled':  Color(0xFFE53935),
  }[s] ?? Colors.grey;

  Color _paymentColor(String s) => const {
    'paid':           Color(0xFF43A047),
    'not_paid':       Color(0xFFE53935),
    'partially_paid': Color(0xFFFB8C00),
    'pending':        Color(0xFF757575),
  }[s] ?? Colors.grey;

  Widget _card({required Widget child, EdgeInsetsGeometry? padding}) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 12),
    padding: padding ?? const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: const Color(0xFFEEEEEE)),
      boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))],
    ),
    child: child,
  );

  Widget _label(String text) =>
      Text(text, style: TextStyle(fontSize: 10.5, color: Colors.grey.shade500));

  Widget _sectionHeader(IconData icon, String title) => Row(
    children: [
      Icon(icon, size: 18, color: _gold),
      const SizedBox(width: 8),
      Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
    ],
  );

  Widget _statBox(String label, String value, Color color) => Padding(
    padding: const EdgeInsets.all(6),
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFEEEEEE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 10.5, color: Colors.grey.shade500)),
          const SizedBox(height: 3),
          Text(
            value.isEmpty ? '—' : (value[0].toUpperCase() + value.substring(1)),
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: color),
            maxLines: 1, overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    ),
  );

  Widget _tabBtn(String label, Color color, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      alignment: Alignment.center,
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(10)),
      child: Text(label,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
    ),
  );

  Widget _iconBtn(IconData icon, Color color, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 32, height: 32,
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
      child: Icon(icon, size: 16, color: color),
    ),
  );

  Widget _summaryRow(String label, String value, {bool bold = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Text(label, style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600)),
        const Spacer(),
        Text(value.isEmpty ? '—' : value,
            style: TextStyle(fontSize: 12.5, fontWeight: bold ? FontWeight.w800 : FontWeight.w600)),
      ],
    ),
  );
}

// ── Product-wise history screen ────────────────────────────────────────────

class _ProductHistoryScreen extends StatefulWidget {
  final String buyerUserId;
  final String ownerName;

  const _ProductHistoryScreen({required this.buyerUserId, required this.ownerName});

  @override
  State<_ProductHistoryScreen> createState() => _ProductHistoryScreenState();
}

class _ProductHistoryScreenState extends State<_ProductHistoryScreen> {
  static const _gold = Color(0xFFD7BE69);

  bool _loading = true;
  List<Map<String, dynamic>> _products = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final data = await ApiService.getOwnerProductHistory(widget.buyerUserId);
    if (!mounted) return;
    setState(() { _products = data; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: Text(widget.ownerName.isEmpty ? 'Product History' : "${widget.ownerName}'s Products"),
        backgroundColor: _gold,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _gold))
          : _products.isEmpty
              ? Center(child: Text('No purchase history found', style: TextStyle(color: Colors.grey.shade500)))
              : ListView.separated(
                  padding: const EdgeInsets.all(14),
                  itemCount: _products.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final p = _products[i];
                    final name   = (p['name'] ?? 'Item').toString();
                    final qty    = (p['total_qty'] as int?) ?? 0;
                    final amount = (p['total_amount'] as num?)?.toDouble() ?? 0;
                    final orders = (p['order_count'] as int?) ?? 0;
                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFEEEEEE)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(name, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                                const SizedBox(height: 3),
                                Text('Qty: $qty  •  $orders order${orders == 1 ? '' : 's'}',
                                    style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
                              ],
                            ),
                          ),
                          Text('₹${amount.toStringAsFixed(2)}',
                              style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800)),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}

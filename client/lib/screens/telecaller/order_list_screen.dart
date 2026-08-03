import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/api_service.dart';
import '../../services/invoice_printer.dart';
import '../../widgets/single_location_map_screen.dart';
import 'order_detail_screen.dart';

class OrderListScreen extends StatefulWidget {
  final String? buyerUserId; // set to scope this list to one owner's orders
  final String? title;

  const OrderListScreen({super.key, this.buyerUserId, this.title});

  @override
  State<OrderListScreen> createState() => _OrderListScreenState();
}

class _OrderListScreenState extends State<OrderListScreen> {
  static const _gold = Color(0xFFD7BE69);

  final _scrollCtrl = ScrollController();
  final List<Map<String, dynamic>> _orders = [];

  int    _page      = 1;
  int    _lastPage  = 1;
  int    _total     = 0;
  bool   _loading   = false;
  bool   _hasMore   = true;
  String _query     = '';
  String? _paymentStatus; // null = all

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
    _loadPage(reset: true);
  }

  @override
  void dispose() {
    _scrollCtrl.removeListener(_onScroll);
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_hasMore || _loading) return;
    if (_scrollCtrl.position.pixels >= _scrollCtrl.position.maxScrollExtent - 150) {
      _loadPage();
    }
  }

  Future<void> _loadPage({bool reset = false}) async {
    if (_loading) return;
    setState(() => _loading = true);

    final page = reset ? 1 : _page;
    final res = await ApiService.getOrders(
      page: page,
      perPage: 20,
      q: _query.isEmpty ? null : _query,
      paymentStatus: _paymentStatus,
      buyerUserId: widget.buyerUserId,
    );

    if (!mounted) return;

    final raw  = res['data'];
    final list = raw is List ? List<Map<String, dynamic>>.from(raw) : <Map<String, dynamic>>[];
    final meta = res['meta'] as Map<String, dynamic>?;

    setState(() {
      if (reset) {
        _orders
          ..clear()
          ..addAll(list);
      } else {
        _orders.addAll(list);
      }
      _lastPage = (meta?['last_page'] as int?) ?? 1;
      _total    = (meta?['total'] as int?) ?? _orders.length;
      _page     = page + 1;
      _hasMore  = page < _lastPage;
      _loading  = false;
    });
  }

  void _refresh() => _loadPage(reset: true);

  Future<void> _launch(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _showFilterSheet() async {
    final searchCtrl = TextEditingController(text: _query);
    String? selected = _paymentStatus;

    const statuses = [
      (null, 'All'),
      ('paid', 'Paid'),
      ('not_paid', 'Not Paid'),
      ('partially_paid', 'Partially Paid'),
      ('pending', 'Pending'),
    ];

    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(
            left: 18, right: 18, top: 18,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 18,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Filter Orders', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 14),
              TextField(
                controller: searchCtrl,
                decoration: InputDecoration(
                  hintText: 'Order ID, shop, name, contact…',
                  prefixIcon: const Icon(Icons.search_rounded, color: _gold),
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 14),
              const Text('Payment status', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black54)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8, runSpacing: 8,
                children: statuses.map((s) {
                  final active = selected == s.$1;
                  return GestureDetector(
                    onTap: () => setSheetState(() => selected = s.$1),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                      decoration: BoxDecoration(
                        color: active ? _gold : Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: active ? _gold : Colors.grey.shade300),
                      ),
                      child: Text(s.$2,
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                              color: active ? Colors.white : Colors.black87)),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 46,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _gold, foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () => Navigator.pop(ctx, {'q': searchCtrl.text.trim(), 'status': selected}),
                  child: const Text('Apply'),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (result != null) {
      setState(() {
        _query = result['q'] as String? ?? '';
        _paymentStatus = result['status'] as String?;
      });
      _loadPage(reset: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: Text(widget.title ?? 'Order List'),
        backgroundColor: _gold,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: _refresh),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: _gold,
        onPressed: _showFilterSheet,
        child: const Icon(Icons.filter_list_rounded, color: Colors.white),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
            child: Row(
              children: [
                Text('$_total order${_total == 1 ? '' : 's'}',
                    style: const TextStyle(fontSize: 12, color: Colors.black54)),
                const Spacer(),
                Text('Page ${_orders.isEmpty ? 0 : _page - 1} / $_lastPage',
                    style: const TextStyle(fontSize: 12, color: Colors.black54)),
              ],
            ),
          ),
          Expanded(
            child: _orders.isEmpty && !_loading
                ? Center(
                    child: Text('No orders found', style: TextStyle(fontSize: 14, color: Colors.grey.shade500)),
                  )
                : RefreshIndicator(
                    color: _gold,
                    onRefresh: () async => _refresh(),
                    child: ListView.builder(
                      controller: _scrollCtrl,
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 90),
                      itemCount: _orders.length + (_hasMore ? 1 : 0),
                      itemBuilder: (context, i) {
                        if (i >= _orders.length) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 16),
                            child: Center(child: CircularProgressIndicator(color: _gold)),
                          );
                        }
                        return _OrderCard(
                          order: _orders[i],
                          onLaunch: _launch,
                          onTap: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => OrderDetailScreen(
                                  orderId: (_orders[i]['order_id'] ?? '').toString(),
                                  orderIds: _orders.map((o) => (o['order_id'] ?? '').toString()).toList(),
                                  initialIndex: i,
                                ),
                              ),
                            );
                            if (mounted) _refresh();
                          },
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

// ── Order card ────────────────────────────────────────────────────────────────

class _OrderCard extends StatelessWidget {
  final Map<String, dynamic> order;
  final void Function(String url) onLaunch;
  final VoidCallback? onTap;

  const _OrderCard({required this.order, required this.onLaunch, this.onTap});

  static const _gold = Color(0xFFD7BE69);

  static const _stateColors = {
    'pending':    Color(0xFFD7BE69),
    'registered': Color(0xFF607D8B),
    'invoiced':   Color(0xFF1976D2),
    'completed':  Color(0xFF43A047),
    'cancelled':  Color(0xFFE53935),
  };

  static const _paymentColors = {
    'paid':            Color(0xFF43A047),
    'not_paid':        Color(0xFFE53935),
    'partially_paid':  Color(0xFFFB8C00),
    'pending':         Color(0xFF757575),
  };

  double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  Future<void> _call(String phone) async => onLaunch('tel:$phone');

  Future<void> _whatsapp(String phone) async {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    final number = digits.length == 10 ? '91$digits' : digits;
    onLaunch('https://wa.me/$number');
  }

  Future<void> _cloudCall(BuildContext context, String buyerUserId, String phone,
      [String name = '', String shopName = '', String address = '', String area = '']) async {
    await context.push('/telecaller/call', extra: {
      'account': {
        'id':            buyerUserId,
        'contactNumber': phone,
        'businessName':  shopName.isNotEmpty ? shopName : name,
        'personName':    name,
        'address':       address,
        'area':          area,
      },
      'accountType': 'customer',
    });
  }

  @override
  Widget build(BuildContext context) {
    final orderId   = (order['order_id'] ?? '').toString();
    final state     = (order['order_state'] ?? '').toString();
    final payment   = (order['payment_status'] ?? '').toString();
    final shop      = (order['shop_name'] ?? '').toString();
    final name      = (order['contact_name'] ?? '').toString();
    final address   = (order['address'] ?? '').toString();
    final area      = (order['area_name'] ?? '').toString();
    final adminName = (order['admin_name'] ?? '').toString();
    final orderDt   = (order['order_datetime'] ?? '').toString();
    final deliveryW = (order['delivery_window'] ?? '').toString();
    final total     = _toDouble(order['order_total']) ?? 0;
    final items     = (order['items_count'] as int?) ?? 0;
    final phone     = (order['contact_number'] ?? '').toString();
    final buyerId   = (order['buyer_userid'] ?? '').toString();
    final lat       = _toDouble(order['latitude']);
    final lng       = _toDouble(order['longitude']);

    final stateColor   = _stateColors[state] ?? Colors.grey;
    final paymentColor = _paymentColors[payment] ?? Colors.grey;

    return GestureDetector(
      onTap: onTap,
      child: Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFEEEEEE)),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Status chip + action icons ──────────────────────────────────
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: stateColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: stateColor.withValues(alpha: 0.4)),
                ),
                child: Text(
                  state.isEmpty ? '—' : state[0].toUpperCase() + state.substring(1),
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: stateColor),
                ),
              ),
              const Spacer(),
              _iconBtn(
                const Icon(Icons.print_rounded, size: 16, color: Colors.black54),
                () => InvoicePrinter.print(context, orderId),
              ),
              if (phone.isNotEmpty) ...[
                const SizedBox(width: 6),
                _iconBtn(
                  const Icon(Icons.call_rounded, size: 16, color: Color(0xFF1976D2)),
                  () => _call(phone),
                  bg: const Color(0xFF1976D2).withValues(alpha: 0.12),
                ),
                const SizedBox(width: 6),
                _iconBtn(
                  const Icon(Icons.ring_volume_rounded, size: 16, color: Color(0xFF8E24AA)),
                  () => _cloudCall(context, buyerId, phone, name, shop, address, area),
                  bg: const Color(0xFF8E24AA).withValues(alpha: 0.12),
                ),
                const SizedBox(width: 6),
                _iconBtn(
                  const FaIcon(FontAwesomeIcons.whatsapp, size: 16, color: Color(0xFF25D366)),
                  () => _whatsapp(phone),
                  bg: const Color(0xFF25D366).withValues(alpha: 0.12),
                ),
              ],
              if (lat != null && lng != null) ...[
                const SizedBox(width: 6),
                _iconBtn(
                  const Icon(Icons.location_on_rounded, size: 16, color: Color(0xFFE53935)),
                  () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => SingleLocationMapScreen(
                          title: shop.isNotEmpty ? shop : name,
                          subtitle: address,
                          latitude: lat,
                          longitude: lng,
                        ),
                      ),
                    );
                  },
                  bg: const Color(0xFFE53935).withValues(alpha: 0.12),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),

          Text('Order ID: $orderId', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          if (shop.isNotEmpty) Text('Shop: $shop', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          if (name.isNotEmpty) Text('Name: $name', style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600)),
          if (address.isNotEmpty)
            Text('Address: $address', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          if (area.isNotEmpty) Text('Area Name: $area', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
          if (adminName.isNotEmpty) Text('Admin Name: $adminName', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),

          const SizedBox(height: 10),

          // ── Order date / delivery window ────────────────────────────────
          Row(
            children: [
              Expanded(child: _infoBox(Icons.event_rounded, 'Order Date & Time', orderDt)),
              const SizedBox(width: 8),
              Expanded(child: _infoBox(Icons.local_shipping_rounded, 'Delivery Date & Time', deliveryW)),
            ],
          ),
          const SizedBox(height: 10),

          // ── Order total ──────────────────────────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F5F5),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Text('Order Total', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                const Spacer(),
                Text('₹${total.toStringAsFixed(0)}',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
              ],
            ),
          ),
          const SizedBox(height: 8),

          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: paymentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: paymentColor.withValues(alpha: 0.4)),
                ),
                child: Text(payment.toUpperCase(),
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: paymentColor)),
              ),
              const SizedBox(width: 8),
              Text('$items item${items == 1 ? '' : 's'}',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            ],
          ),
        ],
      ),
      ),
    );
  }

  Widget _iconBtn(Widget icon, VoidCallback onTap, {Color bg = const Color(0x14000000)}) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 32, height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      child: icon,
    ),
  );

  Widget _infoBox(IconData icon, String label, String value) => Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: const Color(0xFFFAFAFA),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: const Color(0xFFEEEEEE)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 12, color: _gold),
            const SizedBox(width: 4),
            Expanded(
              child: Text(label,
                  style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
        const SizedBox(height: 3),
        Text(value.isEmpty ? '—' : value,
            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
            maxLines: 2, overflow: TextOverflow.ellipsis),
      ],
    ),
  );
}

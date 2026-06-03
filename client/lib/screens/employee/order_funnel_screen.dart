import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class OrderFunnelScreen extends StatefulWidget {
  final String accountId;
  final Map<String, dynamic>? account;

  const OrderFunnelScreen({
    super.key,
    required this.accountId,
    this.account,
  });

  @override
  State<OrderFunnelScreen> createState() => _OrderFunnelScreenState();
}

class _OrderFunnelScreenState extends State<OrderFunnelScreen> {
  static const _gold  = Color(0xFFD7BE69);
  static const _green = Color(0xFF43A047);

  bool _visitedIn  = false;
  bool _visitedOut = false;

  Map<String, dynamic> get _acc => widget.account ?? {};

  String? get _scheduleLabel {
    switch (_acc['frequency'] as String?) {
      case 'weekly':
        return 'WEEKLY';
      case 'monthly':
        return 'MONTHLY';
      case 'n_days':
        final n = _acc['interval_days'];
        return n == null ? 'RECURRING' : 'EVERY $n DAYS';
      default:
        return null;
    }
  }

  List<String> get _dayChips {
    if ((_acc['frequency'] as String?) == 'weekly') {
      return (_acc['days'] as List?)?.map((e) => e.toString()).toList() ?? [];
    }
    return [];
  }

  Future<void> _launch(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  void _whatsapp(String phone) {
    final d = phone.replaceAll(RegExp(r'\D'), '');
    final n = d.length == 10 ? '91$d' : d;
    _launch('https://wa.me/$n');
  }

  @override
  Widget build(BuildContext context) {
    final code    = _acc['accountCode']   as String? ?? '';
    final owner   = _acc['personName']    as String? ?? '';
    final shop    = _acc['businessName']  as String? ?? '—';
    final address = _acc['address']       as String? ?? '';
    final phone   = _acc['contactNumber'] as String? ?? '';
    final lat     = _acc['latitude'];
    final lng     = _acc['longitude'];

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text('Order Details'),
        backgroundColor: _gold,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Account card ──────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFEEEEEE)),
                boxShadow: const [BoxShadow(
                    color: Colors.black12, blurRadius: 6, offset: Offset(0, 2))],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Code + owner (single row)
                  Row(
                    children: [
                      Text(code,
                          style: const TextStyle(
                              fontSize: 12, color: Colors.black45,
                              letterSpacing: 0.4)),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text('Owner Name : $owner',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Schedule chips + visit buttons
                  Row(
                    children: [
                      if (_scheduleLabel != null)
                        _Chip(label: _scheduleLabel!,
                            bg: _green.withValues(alpha: 0.10), fg: const Color(0xFF2E7D32)),
                      const SizedBox(width: 6),
                      ..._dayChips.map((d) => Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: _Chip(label: d,
                            bg: Colors.grey.shade200, fg: Colors.black54),
                      )),
                      const Spacer(),
                      // Visit In
                      _VisitBtn(
                        label: 'Visit In',
                        active: !_visitedIn,
                        onTap: _visitedIn ? null : () => setState(() => _visitedIn = true),
                      ),
                      const SizedBox(width: 6),
                      // Visit Out
                      _VisitBtn(
                        label: 'Visit Out',
                        active: _visitedIn && !_visitedOut,
                        onTap: (_visitedIn && !_visitedOut)
                            ? () => setState(() => _visitedOut = true)
                            : null,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // Shop name
                  Text('Shop Name : $shop',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  if (address.isNotEmpty)
                    Text('Address : $address',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                  const SizedBox(height: 12),
                  // Actions + take order
                  Row(
                    children: [
                      _ActionBtn(
                        icon: Icons.call_rounded,
                        color: _green,
                        onTap: phone.isNotEmpty ? () => _launch('tel:$phone') : null,
                      ),
                      const SizedBox(width: 10),
                      _ActionBtn(
                        icon: Icons.chat_rounded,
                        color: const Color(0xFF25D366),
                        onTap: phone.isNotEmpty ? () => _whatsapp(phone) : null,
                      ),
                      const SizedBox(width: 10),
                      _ActionBtn(
                        icon: Icons.map_rounded,
                        color: const Color(0xFF1565C0),
                        onTap: (lat != null && lng != null)
                            ? () => _launch(
                                'https://www.google.com/maps/search/?api=1&query=$lat,$lng')
                            : null,
                      ),
                      const Spacer(),
                      ElevatedButton.icon(
                        onPressed: () {},
                        icon: const Icon(Icons.shopping_cart_rounded, size: 16),
                        label: const Text('Take Order',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _gold,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // ── Tabs row ──────────────────────────────────────────────────
            Row(
              children: [
                Expanded(child: _TabBtn(label: 'Order History', onTap: () {})),
                const SizedBox(width: 10),
                Expanded(child: _TabBtn(label: 'Order Funnel', onTap: () {})),
                const SizedBox(width: 10),
                Expanded(child: _TabBtn(label: 'Transaction', onTap: () {})),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

class _Chip extends StatelessWidget {
  final String label;
  final Color  bg, fg;
  const _Chip({required this.label, required this.bg, required this.fg});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
        child: Text(label,
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: fg)),
      );
}

class _VisitBtn extends StatelessWidget {
  final String       label;
  final bool         active;
  final VoidCallback? onTap;
  const _VisitBtn({required this.label, required this.active, this.onTap});

  static const _gold = Color(0xFFD7BE69);

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: active ? _gold : Colors.grey.shade300,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700,
                  color: active ? Colors.white : Colors.grey.shade600)),
        ),
      );
}

class _ActionBtn extends StatelessWidget {
  final IconData      icon;
  final Color         color;
  final VoidCallback? onTap;
  const _ActionBtn({required this.icon, required this.color, this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 38, height: 38,
          decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
          child: Icon(icon, size: 19, color: color),
        ),
      );
}

class _TabBtn extends StatelessWidget {
  final String       label;
  final VoidCallback onTap;
  const _TabBtn({required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFEEEEEE)),
            boxShadow: const [BoxShadow(
                color: Colors.black12, blurRadius: 3, offset: Offset(0, 1))],
          ),
          child: Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 12.5, fontWeight: FontWeight.w600,
                  color: Colors.black87)),
        ),
      );
}

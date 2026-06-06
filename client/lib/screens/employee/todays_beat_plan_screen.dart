import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/api_service.dart';

class TodaysBeatPlanScreen extends StatefulWidget {
  const TodaysBeatPlanScreen({super.key});

  @override
  State<TodaysBeatPlanScreen> createState() => _TodaysBeatPlanScreenState();
}

class _TodaysBeatPlanScreenState extends State<TodaysBeatPlanScreen> {
  static const _gold = Color(0xFFD7BE69);

  bool   _loading = true;
  String _error   = '';
  int    _total   = 0;
  List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = ''; });
    try {
      final res = await ApiService.getTodayBeatPlan();
      if (!mounted) return;
      if (res['success'] == true) {
        final raw = res['data'];
        final items = raw is List
            ? raw.map((e) => Map<String, dynamic>.from(e as Map)).toList()
            : <Map<String, dynamic>>[];
        setState(() {
          _items   = items;
          _total   = (res['total'] as int?) ?? items.length;
          _loading = false;
        });
      } else {
        setState(() { _loading = false; _error = 'Failed to load beat plan.'; });
      }
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = 'Error loading beat plan.'; });
    }
  }

  String get _todayLabel {
    final now = DateTime.now();
    const dayNames = ['Sunday','Monday','Tuesday','Wednesday','Thursday','Friday','Saturday'];
    final d = now.day.toString().padLeft(2, '0');
    final m = now.month.toString().padLeft(2, '0');
    return '${dayNames[now.weekday % 7]} | $d/$m/${now.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text('My Beat Plan'),
        backgroundColor: _gold,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _gold))
          : _error.isNotEmpty
              ? Center(child: Text(_error,
                    style: const TextStyle(color: Colors.red)))
              : RefreshIndicator(
                  onRefresh: _load,
                  color: _gold,
                  child: ListView(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
                  children: [
                    // Summary card
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: const [BoxShadow(
                            color: Colors.black12, blurRadius: 6,
                            offset: Offset(0, 2))],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            const Text('Today Beat Plan',
                                style: TextStyle(
                                    fontSize: 15, fontWeight: FontWeight.w700)),
                            const Spacer(),
                            Text(_todayLabel,
                                style: TextStyle(
                                    fontSize: 12, color: Colors.grey.shade600)),
                          ]),
                          const SizedBox(height: 10),
                          Row(children: [
                            _Chip(label: 'Total Planned: $_total',
                                color: const Color(0xFF1976D2)),
                            const SizedBox(width: 8),
                            _Chip(
                                label: 'Shown: ${_items.length}',
                                color: const Color(0xFF43A047)),
                            const SizedBox(width: 8),
                            OutlinedButton.icon(
                              onPressed: () {},
                              icon: const Icon(Icons.map_outlined, size: 13),
                              label: const Text('Show in Map',
                                  style: TextStyle(fontSize: 11)),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.blueGrey,
                                side: BorderSide(
                                    color: Colors.blueGrey.shade400),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 5),
                                minimumSize: Size.zero,
                                tapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(20)),
                              ),
                            ),
                          ]),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    if (_items.isEmpty)
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 40),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.today_outlined,
                                  size: 72, color: Colors.grey.shade300),
                              const SizedBox(height: 14),
                              Text('No accounts scheduled for today',
                                  style: TextStyle(
                                      fontSize: 15,
                                      color: Colors.grey.shade500)),
                            ],
                          ),
                        ),
                      )
                    else
                      ...List.generate(_items.length, (i) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _CustomerCard(item: _items[i]),
                      )),
                  ],
                  ),
                ),
    );
  }
}

// ── Customer card ─────────────────────────────────────────────────────────────

class _CustomerCard extends StatelessWidget {
  final Map<String, dynamic> item;
  const _CustomerCard({required this.item});

  static const _gold   = Color(0xFFD7BE69);
  static const _cardBg = Color(0xFFFFF0EE);

  Map<String, dynamic> get _account =>
      (item['account'] as Map<String, dynamic>?) ?? {};

  Future<void> _launch(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  String _freqLabel(String freq, List<dynamic>? days) {
    switch (freq) {
      case 'weekly':
        final d = days?.cast<dynamic>() ?? [];
        return d.isEmpty ? 'WEEKLY' : d.join(', ').toUpperCase();
      case 'monthly':
        final md = item['month_date'];
        return md == null ? 'MONTHLY' : 'DAY $md / MONTH';
      case 'n_days':
        final n = item['interval_days'];
        return n == null ? 'RECURRING' : 'EVERY $n DAYS';
      default:
        return freq.toUpperCase();
    }
  }

  @override
  Widget build(BuildContext context) {
    final acc        = _account;
    final code       = acc['accountCode']   as String? ?? '';
    final name       = acc['businessName']  as String? ?? '—';
    final person     = acc['personName']    as String? ?? '';
    final phone      = acc['contactNumber'] as String? ?? '';
    final address    = acc['address']       as String? ?? '';
    final area       = acc['area']          as String? ?? '';
    final pin        = acc['pincode']       as String? ?? '';
    final freq       = item['frequency']    as String? ?? 'weekly';
    final days       = item['days']         as List?;
    final visited    = item['visited_today'] == true;
    final accountType = item['account_type'] as String? ?? 'lead';

    return GestureDetector(
      onTap: () {
        final id = acc['id'] as String?;
        if (id != null && id.isNotEmpty) {
          context.push('/lead-accounts/$id', extra: acc);
        }
      },
      child: Container(
        decoration: BoxDecoration(
          color: visited ? const Color(0xFFF0FFF4) : _cardBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: visited
                ? const Color(0xFFC8E6C9)
                : const Color(0xFFFFD8D2),
          ),
          boxShadow: const [
            BoxShadow(color: Colors.black12, blurRadius: 4,
                offset: Offset(0, 2))
          ],
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Code + freq chip + account type
            Row(children: [
              Text(code,
                  style: const TextStyle(
                      fontSize: 11, color: Colors.grey,
                      letterSpacing: 0.5)),
              const Spacer(),
              _Tag(
                label: accountType.toUpperCase(),
                bg: accountType == 'customer'
                    ? const Color(0xFFE3F2FD)
                    : const Color(0xFFFFF3E0),
                fg: accountType == 'customer'
                    ? const Color(0xFF1976D2)
                    : const Color(0xFFF57C00),
              ),
              const SizedBox(width: 6),
              if (visited)
                _Tag(label: '✓ Visited',
                    bg: const Color(0xFFE8F5E9),
                    fg: const Color(0xFF2E7D32))
              else
                _Tag(
                  label: _freqLabel(freq, days),
                  bg: const Color(0xFFE8F5E9),
                  fg: const Color(0xFF2E7D32),
                ),
            ]),
            const SizedBox(height: 6),
            // Name + salesman + proceed
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Text(name,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w800)),
              ),
              const SizedBox(width: 8),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                if (person.isNotEmpty)
                  Text(person,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                if (!visited)
                  GestureDetector(
                    onTap: () => context.push(
                        '/order-funnel/${acc['id'] ?? ''}',
                        extra: {
                          ...acc,
                          'beat_plan_id':  item['beat_plan_id'],
                          'frequency':     item['frequency'],
                          'days':          item['days'],
                          'month_date':    item['month_date'],
                          'interval_days': item['interval_days'],
                        }),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 7),
                      decoration: BoxDecoration(
                        color: _gold,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text('Proceed',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Colors.white)),
                    ),
                  ),
              ]),
            ]),
            const SizedBox(height: 4),
            if (address.isNotEmpty)
              Text('Address : $address',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            if (area.isNotEmpty)
              Text('Main area : $area',
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600)),
            if (pin.isNotEmpty)
              Text('PIN : $pin',
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w500)),
            const SizedBox(height: 10),
            // Phone + actions
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.phone_rounded, size: 13,
                      color: Colors.grey.shade600),
                  const SizedBox(width: 5),
                  Text(phone,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600)),
                ]),
              ),
              const Spacer(),
              _ActionBtn(
                icon: Icons.visibility_outlined,
                color: Colors.grey.shade600,
                onTap: () {
                  final id = acc['id'] as String?;
                  if (id != null && id.isNotEmpty) {
                    context.push('/lead-accounts/$id', extra: acc);
                  }
                },
              ),
              const SizedBox(width: 6),
              _ActionBtn(
                icon: Icons.call_rounded,
                color: Colors.grey.shade600,
                onTap: phone.isNotEmpty
                    ? () => _launch('tel:$phone')
                    : null,
              ),
              const SizedBox(width: 6),
              _ActionBtn(
                icon: Icons.chat_rounded,
                color: const Color(0xFF25D366),
                onTap: phone.isNotEmpty
                    ? () {
                        final d = phone.replaceAll(RegExp(r'\D'), '');
                        final n = d.length == 10 ? '91$d' : d;
                        _launch('https://wa.me/$n');
                      }
                    : null,
              ),
              const SizedBox(width: 6),
              _ActionBtn(
                icon: Icons.map_rounded,
                color: const Color(0xFF1565C0),
                onTap: (acc['latitude'] != null && acc['longitude'] != null)
                    ? () => _launch(
                        'https://www.google.com/maps/search/?api=1&query=${acc['latitude']},${acc['longitude']}')
                    : null,
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

// ── Small helpers ─────────────────────────────────────────────────────────────

class _Tag extends StatelessWidget {
  final String label;
  final Color  bg, fg;
  const _Tag({required this.label, required this.bg, required this.fg});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
        child: Text(label,
            style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.w700, color: fg)),
      );
}

class _Chip extends StatelessWidget {
  final String label;
  final Color  color;
  const _Chip({required this.label, required this.color});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.30)),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w600, color: color)),
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
          width: 36, height: 36,
          decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
          child: Icon(icon, size: 18, color: color),
        ),
      );
}

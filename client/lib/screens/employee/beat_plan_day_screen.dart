import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/api_service.dart';
import '../../widgets/account_map_screen.dart';

class BeatPlanDayScreen extends StatefulWidget {
  final String date; // YYYY-MM-DD

  const BeatPlanDayScreen({super.key, required this.date});

  @override
  State<BeatPlanDayScreen> createState() => _BeatPlanDayScreenState();
}

class _BeatPlanDayScreenState extends State<BeatPlanDayScreen> {
  static const _gold = Color(0xFFD7BE69);

  bool   _loading = true;
  String _error   = '';
  List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = ''; });
    try {
      final res = await ApiService.getWeekBeatPlan(date: widget.date);
      if (!mounted) return;
      if (res['success'] == true) {
        final raw = res['data'];
        setState(() {
          _items = raw is List
              ? raw.map((e) => Map<String, dynamic>.from(e as Map)).toList()
              : [];
          _loading = false;
        });
      } else {
        setState(() { _loading = false; _error = 'Failed to load.'; });
      }
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = 'Error loading.'; });
    }
  }

  String get _displayDate {
    try {
      final d = DateTime.parse(widget.date);
      const days = ['Sun','Mon','Tue','Wed','Thu','Fri','Sat'];
      return '${days[d.weekday % 7]}  •  ${d.day.toString().padLeft(2,'0')}/${d.month.toString().padLeft(2,'0')}/${d.year}';
    } catch (_) { return widget.date; }
  }

  Future<void> _launch(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  String? _scheduleLabel(Map<String, dynamic> item) {
    switch (item['frequency'] as String?) {
      case 'weekly':
        final d = (item['days'] as List?)?.cast<dynamic>() ?? [];
        return d.isEmpty ? null : d.join(', ');
      case 'monthly':
        final m = item['month_date'];
        return m == null ? null : 'Day $m / month';
      case 'n_days':
        final n = item['interval_days'];
        return n == null ? null : 'Every $n days';
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: Text(_displayDate),
        backgroundColor: _gold,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (_items.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.map_rounded),
              tooltip: 'Show in Map',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AccountMapScreen(
                    title: '$_displayDate — Map',
                    accounts: _items.map((item) {
                      final acc = Map<String, dynamic>.from(
                          item['account'] as Map? ?? {});
                      acc['_type'] = item['account_type'] ?? 'lead';
                      return acc;
                    }).toList(),
                  ),
                ),
              ),
            ),
          IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _gold))
          : _error.isNotEmpty
              ? Center(child: Text(_error,
                    style: const TextStyle(color: Colors.red)))
              : _items.isEmpty
                  ? Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.event_available_outlined,
                            size: 72, color: Colors.grey.shade300),
                        const SizedBox(height: 14),
                        Text('No accounts scheduled for this day',
                            style: TextStyle(
                                fontSize: 15, color: Colors.grey.shade500)),
                      ]),
                    )
                  : Column(children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        color: _gold.withValues(alpha: 0.08),
                        child: Row(children: [
                          const Icon(Icons.people_alt_rounded,
                              size: 15, color: _gold),
                          const SizedBox(width: 6),
                          Text('${_items.length} account${_items.length == 1 ? '' : 's'}',
                              style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: _gold)),
                        ]),
                      ),
                      Expanded(
                        child: RefreshIndicator(
                          onRefresh: _load,
                          child: ListView.separated(
                            padding: const EdgeInsets.all(12),
                            itemCount: _items.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 8),
                            itemBuilder: (_, i) {
                              final item    = _items[i];
                              final acc     = (item['account'] as Map<String, dynamic>?) ?? {};
                              final name    = acc['businessName']  as String? ?? '—';
                              final code    = acc['accountCode']   as String? ?? '';
                              final phone   = acc['contactNumber'] as String? ?? '';
                              final address = acc['address']       as String? ?? '';
                              final area    = acc['area']          as String? ?? '';
                              final pin     = acc['pincode']       as String? ?? '';
                              final visited    = item['visited_today'] == true;
                              final sched      = _scheduleLabel(item);
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
                                    color: visited
                                        ? const Color(0xFFF0FFF4)
                                        : Colors.white,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                        color: visited
                                            ? const Color(0xFFC8E6C9)
                                            : const Color(0xFFEEEEEE)),
                                    boxShadow: const [BoxShadow(
                                        color: Colors.black12,
                                        blurRadius: 4,
                                        offset: Offset(0, 2))],
                                  ),
                                  padding: const EdgeInsets.all(12),
                                  child: Row(children: [
                                    CircleAvatar(
                                      radius: 22,
                                      backgroundColor:
                                          _gold.withValues(alpha: 0.12),
                                      child: Text(
                                        name.isNotEmpty
                                            ? name[0].toUpperCase()
                                            : '?',
                                        style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            color: _gold),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(children: [
                                            Expanded(
                                              child: Text(name,
                                                  style: const TextStyle(
                                                      fontSize: 14,
                                                      fontWeight:
                                                          FontWeight.w700)),
                                            ),
                                            Container(
                                              padding: const EdgeInsets
                                                  .symmetric(
                                                  horizontal: 6,
                                                  vertical: 2),
                                              decoration: BoxDecoration(
                                                color: accountType == 'customer'
                                                    ? const Color(0xFFE3F2FD)
                                                    : const Color(0xFFFFF3E0),
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                              child: Text(
                                                  accountType.toUpperCase(),
                                                  style: TextStyle(
                                                      fontSize: 9,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      color: accountType ==
                                                              'customer'
                                                          ? const Color(
                                                              0xFF1976D2)
                                                          : const Color(
                                                              0xFFF57C00))),
                                            ),
                                            const SizedBox(width: 6),
                                            if (visited)
                                              Container(
                                                padding: const EdgeInsets
                                                    .symmetric(
                                                    horizontal: 8,
                                                    vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: const Color(
                                                      0xFFE8F5E9),
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                          10),
                                                ),
                                                child: const Text('✓ Visited',
                                                    style: TextStyle(
                                                        fontSize: 10,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        color: Color(
                                                            0xFF2E7D32))),
                                              ),
                                          ]),
                                          Text(code,
                                              style: TextStyle(
                                                  fontSize: 11,
                                                  color: Colors.grey.shade500)),
                                          if (address.isNotEmpty || area.isNotEmpty)
                                            Text(
                                              [if (address.isNotEmpty) address,
                                                if (area.isNotEmpty) area]
                                                  .join(' • '),
                                              style: TextStyle(
                                                  fontSize: 11,
                                                  color: Colors.grey.shade500),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          if (phone.isNotEmpty || pin.isNotEmpty)
                                            Text(
                                              [if (phone.isNotEmpty) phone,
                                                if (pin.isNotEmpty) 'PIN $pin']
                                                  .join('  •  '),
                                              style: TextStyle(
                                                  fontSize: 11,
                                                  color: Colors.grey.shade500),
                                            ),
                                          if (sched != null) ...[
                                            const SizedBox(height: 5),
                                            Container(
                                              padding: const EdgeInsets
                                                  .symmetric(
                                                  horizontal: 8, vertical: 3),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFF43A047)
                                                    .withValues(alpha: 0.10),
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                                border: Border.all(
                                                    color: const Color(
                                                            0xFF43A047)
                                                        .withValues(
                                                            alpha: 0.30)),
                                              ),
                                              child: Row(
                                                mainAxisSize:
                                                    MainAxisSize.min,
                                                children: [
                                                  const Icon(
                                                      Icons.event_repeat_rounded,
                                                      size: 12,
                                                      color: Color(0xFF2E7D32)),
                                                  const SizedBox(width: 4),
                                                  Text(sched,
                                                      style: const TextStyle(
                                                          fontSize: 10.5,
                                                          fontWeight:
                                                              FontWeight.w700,
                                                          color: Color(
                                                              0xFF2E7D32))),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Column(children: [
                                      _SmallBtn(
                                        icon: Icons.call_rounded,
                                        color: Colors.grey.shade600,
                                        onTap: phone.isNotEmpty
                                            ? () => _launch('tel:$phone')
                                            : null,
                                      ),
                                      const SizedBox(height: 6),
                                      _SmallBtn(
                                        icon: Icons.chat_rounded,
                                        color: const Color(0xFF25D366),
                                        onTap: phone.isNotEmpty
                                            ? () {
                                                final d = phone.replaceAll(
                                                    RegExp(r'\D'), '');
                                                final n = d.length == 10
                                                    ? '91$d'
                                                    : d;
                                                _launch('https://wa.me/$n');
                                              }
                                            : null,
                                      ),
                                    ]),
                                  ]),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ]),
    );
  }
}

class _SmallBtn extends StatelessWidget {
  final IconData      icon;
  final Color         color;
  final VoidCallback? onTap;
  const _SmallBtn({required this.icon, required this.color, this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 32, height: 32,
          decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
          child: Icon(icon, size: 16, color: color),
        ),
      );
}

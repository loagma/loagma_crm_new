import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../services/api_service.dart';
import '../../widgets/account_map_screen.dart';

class AllBeatPlanScreen extends StatefulWidget {
  const AllBeatPlanScreen({super.key});

  @override
  State<AllBeatPlanScreen> createState() => _AllBeatPlanScreenState();
}

class _AllBeatPlanScreenState extends State<AllBeatPlanScreen> {
  static const _gold = Color(0xFFD7BE69);

  bool   _loading = true;
  String _error   = '';

  int    _total     = 0;
  int    _planned   = 0;
  int    _visited   = 0;
  int    _remaining = 0;
  String _weekStart = '';
  String _weekEnd   = '';

  // {dayName: {date, count}}
  Map<String, Map<String, dynamic>> _days = {};

  bool _mapLoading = false;

  static const _dayOrder = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = ''; });
    try {
      final res = await ApiService.getWeekBeatPlan();
      if (!mounted) return;
      if (res['success'] == true) {
        final daysRaw = res['days'] as Map<String, dynamic>? ?? {};
        final days = <String, Map<String, dynamic>>{};
        for (final d in _dayOrder) {
          final entry = daysRaw[d] as Map<String, dynamic>?;
          days[d] = {
            'date':  entry?['date']  as String? ?? '',
            'count': entry?['count'] as int?    ?? 0,
          };
        }
        setState(() {
          _total     = (res['total']     as int?) ?? 0;
          _planned   = (res['planned']   as int?) ?? 0;
          _visited   = (res['visited']   as int?) ?? 0;
          _remaining = (res['remaining'] as int?) ?? 0;
          _weekStart = (res['week_start'] as String?) ?? '';
          _weekEnd   = (res['week_end']   as String?) ?? '';
          _days      = days;
          _loading   = false;
        });
      } else {
        setState(() { _loading = false; _error = 'Failed to load beat plan.'; });
      }
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = 'Error loading beat plan.'; });
    }
  }

  Future<void> _openWeekMap() async {
    final dates = _dayOrder
        .map((d) => _days[d]?['date'] as String? ?? '')
        .where((d) => d.isNotEmpty)
        .toSet() // a plan can span multiple weekdays with the same date (shouldn't normally), dedupe fetches
        .toList();

    if (dates.isEmpty) return;

    setState(() => _mapLoading = true);
    try {
      final results = await Future.wait(
          dates.map((d) => ApiService.getWeekBeatPlan(date: d)));

      // Merge all days, de-duplicating the same account if it's scheduled
      // more than once across the week (e.g. weekly plans hitting several days).
      final seen = <String>{};
      final accounts = <Map<String, dynamic>>[];
      for (final res in results) {
        if (res['success'] != true) continue;
        final raw = res['data'];
        if (raw is! List) continue;
        for (final e in raw) {
          final item = Map<String, dynamic>.from(e as Map);
          final acc  = Map<String, dynamic>.from(item['account'] as Map? ?? {});
          final type = item['account_type'] ?? 'lead';
          final key  = '$type:${acc['id']}';
          if (!seen.add(key)) continue;
          acc['_type'] = type;
          accounts.add(acc);
        }
      }

      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => AccountMapScreen(
            title: 'This Week — Map',
            accounts: accounts,
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _mapLoading = false);
    }
  }

  String _formatDate(String iso) {
    if (iso.isEmpty) return '';
    try {
      final d = DateTime.parse(iso);
      return '${d.day.toString().padLeft(2,'0')}/${d.month.toString().padLeft(2,'0')}/${d.year}';
    } catch (_) { return iso; }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text('All Beat Plan'),
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
              ? Center(child: Text(_error, style: const TextStyle(color: Colors.red)))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    children: [
                      // Summary card
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFEEEEEE)),
                          boxShadow: const [BoxShadow(
                              color: Colors.black12, blurRadius: 6,
                              offset: Offset(0, 2))],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              const Expanded(
                                child: Text('All Beat Plan',
                                    style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700)),
                              ),
                              Text(
                                '${_formatDate(_weekStart)} – ${_formatDate(_weekEnd)}',
                                style: TextStyle(
                                    fontSize: 11, color: Colors.grey.shade500),
                              ),
                            ]),
                            const SizedBox(height: 10),
                            Row(children: [
                              Flexible(child: Wrap(spacing: 6, runSpacing: 4, children: [
                                _Chip(label: 'Total: $_total',       color: _gold),
                                _Chip(label: 'Planned: $_planned',   color: const Color(0xFF43A047)),
                                _Chip(label: 'Visited: $_visited',   color: const Color(0xFF1976D2)),
                                _Chip(label: 'Unassigned: $_remaining', color: const Color(0xFFEF5350)),
                              ])),
                              const SizedBox(width: 8),
                              OutlinedButton.icon(
                                onPressed: _mapLoading ? null : _openWeekMap,
                                icon: _mapLoading
                                    ? const SizedBox(
                                        width: 12, height: 12,
                                        child: CircularProgressIndicator(strokeWidth: 1.5),
                                      )
                                    : const Icon(Icons.map_outlined, size: 13),
                                label: const Text('Show All in Map',
                                    style: TextStyle(fontSize: 10)),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.blueGrey,
                                  side: BorderSide(color: Colors.blueGrey.shade400),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 5),
                                  minimumSize: Size.zero,
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(20)),
                                ),
                              ),
                            ]),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Day grid — tap opens that day's accounts
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          childAspectRatio: 1.4,
                        ),
                        itemCount: _dayOrder.length,
                        itemBuilder: (_, i) {
                          final name  = _dayOrder[i];
                          final d     = _days[name] ?? {};
                          final date  = d['date']  as String? ?? '';
                          final count = d['count'] as int? ?? 0;
                          return GestureDetector(
                            onTap: date.isNotEmpty
                                ? () => context.push(
                                    '/beat-plan/day?date=$date')
                                : null,
                            child: Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                    color: const Color(0xFFEEEEEE)),
                                boxShadow: const [BoxShadow(
                                    color: Colors.black12, blurRadius: 4,
                                    offset: Offset(0, 2))],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(name,
                                      style: const TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.w800)),
                                  const SizedBox(height: 2),
                                  Text(_formatDate(date),
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey.shade500)),
                                  const Spacer(),
                                  Text(
                                    count > 0 ? 'Planned' : 'No plan',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: count > 0
                                            ? const Color(0xFF43A047)
                                            : Colors.grey,
                                        fontWeight: FontWeight.w600),
                                  ),
                                  const SizedBox(height: 2),
                                  Text('Accounts: $count',
                                      style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500)),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final Color  color;
  const _Chip({required this.label, required this.color});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.30)),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.w700, color: color)),
      );
}

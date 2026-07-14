import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../services/api_service.dart';
import '../../widgets/account_map_screen.dart';

class AssignmentViewScreen extends StatefulWidget {
  const AssignmentViewScreen({super.key});

  @override
  State<AssignmentViewScreen> createState() => _AssignmentViewScreenState();
}

class _AssignmentViewScreenState extends State<AssignmentViewScreen> {
  static const _gold = Color(0xFFD7BE69);
  static const _dayOrder = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  // Monday of the week being viewed
  late DateTime _monday;

  bool   _loading = true;
  String _error   = '';

  // {dayName: {date, count}}
  Map<String, Map<String, dynamic>> _days = {};

  // expanded day → loaded accounts (null = not loaded yet, [] = loaded empty)
  final Map<String, List<Map<String, dynamic>>?> _dayAccounts = {};
  final Set<String> _expanded = {};
  final Set<String> _loadingDay = {};

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _monday = now.subtract(Duration(days: now.weekday - 1)); // Monday
    _loadWeek();
  }

  String _ymd(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';

  String _dmy(DateTime d) =>
      '${d.day.toString().padLeft(2,'0')}/${d.month.toString().padLeft(2,'0')}/${d.year}';

  String _dmyShort(DateTime d) =>
      '${d.day.toString().padLeft(2,'0')}/${d.month.toString().padLeft(2,'0')}/${d.year.toString().substring(2)}';

  Future<void> _loadWeek() async {
    setState(() { _loading = true; _error = ''; _expanded.clear(); _dayAccounts.clear(); });
    try {
      final res = await ApiService.getWeekBeatPlan(weekOf: _ymd(_monday));
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
        setState(() { _days = days; _loading = false; });
      } else {
        setState(() { _loading = false; _error = 'Failed to load week.'; });
      }
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = 'Error loading week.'; });
    }
  }

  Future<void> _toggleDay(String dayName, String date) async {
    if (_expanded.contains(dayName)) {
      setState(() => _expanded.remove(dayName));
      return;
    }
    setState(() => _expanded.add(dayName));
    if (_dayAccounts[dayName] != null || date.isEmpty) return; // already loaded

    setState(() => _loadingDay.add(dayName));
    try {
      final res = await ApiService.getWeekBeatPlan(date: date);
      if (!mounted) return;
      final raw = res['data'];
      final list = raw is List
          ? raw.map((e) => Map<String, dynamic>.from(e as Map)).toList()
          : <Map<String, dynamic>>[];
      setState(() { _dayAccounts[dayName] = list; _loadingDay.remove(dayName); });
    } catch (e) {
      if (mounted) setState(() { _dayAccounts[dayName] = []; _loadingDay.remove(dayName); });
    }
  }

  void _prevWeek() {
    setState(() => _monday = _monday.subtract(const Duration(days: 7)));
    _loadWeek();
  }

  void _nextWeek() {
    setState(() => _monday = _monday.add(const Duration(days: 7)));
    _loadWeek();
  }

  @override
  Widget build(BuildContext context) {
    final sunday = _monday.add(const Duration(days: 6));

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text('Assignment View'),
        backgroundColor: _gold,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: _loadWeek),
        ],
      ),
      body: Column(
        children: [
          // Week navigator
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left_rounded),
                  onPressed: _prevWeek,
                ),
                Expanded(
                  child: Text(
                    '${_dmy(_monday)} - ${_dmy(sunday)}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right_rounded),
                  onPressed: _nextWeek,
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: _gold))
                : _error.isNotEmpty
                    ? Center(child: Text(_error,
                          style: const TextStyle(color: Colors.red)))
                    : ListView.separated(
                        padding: const EdgeInsets.all(14),
                        itemCount: _dayOrder.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (_, i) {
                          final name  = _dayOrder[i];
                          final d     = _days[name] ?? {};
                          final date  = d['date']  as String? ?? '';
                          final count = d['count'] as int? ?? 0;
                          final dt    = _monday.add(Duration(days: i));
                          return _DayCard(
                            dayName:   name,
                            dateLabel: _dmyShort(dt),
                            count:     count,
                            expanded:  _expanded.contains(name),
                            loading:   _loadingDay.contains(name),
                            accounts:  _dayAccounts[name],
                            onToggle:  () => _toggleDay(name, date),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

// ── Day card (expandable) ─────────────────────────────────────────────────────

class _DayCard extends StatelessWidget {
  final String  dayName;
  final String  dateLabel;
  final int     count;
  final bool    expanded;
  final bool    loading;
  final List<Map<String, dynamic>>? accounts;
  final VoidCallback onToggle;

  static const _gold = Color(0xFFD7BE69);

  const _DayCard({
    required this.dayName,
    required this.dateLabel,
    required this.count,
    required this.expanded,
    required this.loading,
    required this.accounts,
    required this.onToggle,
  });

  // Build a short schedule label from a day item's plan fields
  String? _scheduleLabel(Map<String, dynamic> item) {
    final freq = item['frequency'] as String?;
    if (freq == null) return null;

    switch (freq) {
      case 'weekly':
        final days = (item['days'] as List?)?.cast<dynamic>() ?? [];
        final alt = item['week_anchor_date'] != null ? ' (Alt)' : '';
        return days.isEmpty ? 'Weekly$alt' : 'Weekly: ${days.join(', ')}$alt';
      case 'monthly':
        final d = item['month_date'];
        return d == null ? 'Monthly' : 'Monthly: Day $d';
      case 'specific_dates':
        final dates = (item['specific_dates'] as List?)?.cast<String>() ?? [];
        if (dates.isEmpty) return 'Specific Dates';
        return dates.length == 1 ? 'Specific: ${dates[0]}' : 'Specific: ${dates.length} dates';
      case 'appointment':
        final apt = item['appointment_date'] as String?;
        if (apt == null) return 'Appointment';
        try {
          final dt = DateTime.parse(apt);
          return 'Appt: ${dt.day}/${dt.month} ${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}';
        } catch (e) {
          return 'Appointment';
        }
      case 'n_days':
        final n = item['interval_days'];
        return n == null ? 'N Days' : 'Every $n days';
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFEEEEEE)),
        boxShadow: const [BoxShadow(
            color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))],
      ),
      child: Column(
        children: [
          // Header
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('$dayName - $count assigned account(s)',
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 3),
                        Text('Date : $dateLabel',
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey.shade600)),
                      ],
                    ),
                  ),
                  if (expanded && (accounts ?? []).isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.map_rounded, size: 20, color: Color(0xFF8A6D1B)),
                      tooltip: 'Show in Map',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => AccountMapScreen(
                            title: '$dayName ($dateLabel) — Map',
                            accounts: accounts!.map((item) {
                              final acc = Map<String, dynamic>.from(
                                  item['account'] as Map? ?? {});
                              acc['_type'] = item['account_type'] ?? 'lead';
                              return acc;
                            }).toList(),
                          ),
                        ),
                      ),
                    ),
                  Icon(expanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                      color: Colors.black45),
                ],
              ),
            ),
          ),

          // Expanded body
          if (expanded) ...[
            const Divider(height: 1),
            if (loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(
                    child: SizedBox(
                        width: 22, height: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: _gold))),
              )
            else if ((accounts ?? []).isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 18),
                child: Center(
                  child: Text('No accounts assigned on this day',
                      style: TextStyle(
                          fontSize: 13, color: Colors.grey.shade500)),
                ),
              )
            else
              ...accounts!.map((item) {
                final acc     = (item['account'] as Map<String, dynamic>?) ?? {};
                final id      = (acc['id'] as dynamic)?.toString() ?? '';
                final name    = (acc['businessName'] as dynamic)?.toString() ?? '—';
                final code    = (acc['accountCode'] as dynamic)?.toString() ?? '';
                final phone   = (acc['contactNumber'] as dynamic)?.toString() ?? '';
                final area       = (acc['area'] as dynamic)?.toString() ?? '';
                final pin        = (acc['pincode'] as dynamic)?.toString() ?? '';
                final visited    = item['visited_today'] == true;
                final sched      = _scheduleLabel(item);
                final accountType = item['account_type'] as String? ?? 'lead';

                return InkWell(
                  onTap: id.isNotEmpty
                      ? () => context.push('/lead-accounts/$id', extra: acc)
                      : null,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 11),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CircleAvatar(
                          radius: 18,
                          backgroundColor: _gold.withValues(alpha: 0.12),
                          child: Text(
                            name.isNotEmpty ? name[0].toUpperCase() : '?',
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.bold,
                                color: _gold),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w700)),
                              const SizedBox(height: 1),
                              Text(
                                [if (code.isNotEmpty) code,
                                  if (phone.isNotEmpty) phone].join('  •  '),
                                style: TextStyle(
                                    fontSize: 11, color: Colors.grey.shade500),
                              ),
                              if (area.isNotEmpty || pin.isNotEmpty) ...[
                                const SizedBox(height: 1),
                                Text(
                                  [if (area.isNotEmpty) area,
                                    if (pin.isNotEmpty) 'PIN $pin'].join('  •  '),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: 11, color: Colors.grey.shade500),
                                ),
                              ],
                              const SizedBox(height: 5),
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: accountType == 'customer'
                                          ? const Color(0xFFE3F2FD)
                                          : const Color(0xFFFFF3E0),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      accountType.toUpperCase(),
                                      style: TextStyle(
                                          fontSize: 8.5,
                                          fontWeight: FontWeight.w700,
                                          color: accountType == 'customer'
                                              ? const Color(0xFF1976D2)
                                              : const Color(0xFFF57C00)),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  if (sched != null)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF43A047)
                                            .withValues(alpha: 0.10),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                            color: const Color(0xFF43A047)
                                                .withValues(alpha: 0.30)),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.event_repeat_rounded,
                                              size: 12, color: Color(0xFF2E7D32)),
                                          const SizedBox(width: 4),
                                          Text(sched,
                                              style: const TextStyle(
                                                  fontSize: 10.5,
                                                  fontWeight: FontWeight.w700,
                                                  color: Color(0xFF2E7D32))),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (visited)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE8F5E9),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Text('✓ Visited',
                                style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF2E7D32))),
                          )
                        else
                          const Icon(Icons.chevron_right_rounded,
                              size: 18, color: Colors.grey),
                      ],
                    ),
                  ),
                );
              }),
            const SizedBox(height: 6),
          ],
        ],
      ),
    );
  }
}

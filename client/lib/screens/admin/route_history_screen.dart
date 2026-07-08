import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../services/api_service.dart';
import '../../utils/distance_format.dart';

/// Admin: day list of a salesman's past routes (Phase 5 history).
///
/// Reuses the admin attendance month endpoint — every attendance day is a
/// route day. One fetch per month navigation, NO polling.
class RouteHistoryScreen extends StatefulWidget {
  final String mobile;
  final String name;

  const RouteHistoryScreen(
      {super.key, required this.mobile, required this.name});

  @override
  State<RouteHistoryScreen> createState() => _RouteHistoryScreenState();
}

class _RouteHistoryScreenState extends State<RouteHistoryScreen> {
  static const _gold = Color(0xFFD7BE69);
  static const _wk = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _mo = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];

  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  List<Map<String, dynamic>> _records = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final rows = await ApiService.adminAttendanceMonth(
        widget.mobile, _month.year, _month.month);
    if (!mounted) return;
    rows.sort((a, b) =>
        (b['date'] as String? ?? '').compareTo(a['date'] as String? ?? ''));
    setState(() {
      _records = rows.where((r) => r['punch_in_time'] != null).toList();
      _loading = false;
    });
  }

  bool get _atCurrentMonth {
    final now = DateTime.now();
    return _month.year == now.year && _month.month == now.month;
  }

  void _changeMonth(int delta) {
    setState(() => _month = DateTime(_month.year, _month.month + delta));
    _load();
  }

  DateTime? _parseLocal(String? raw) =>
      raw == null ? null : DateTime.tryParse(raw)?.toLocal();

  String _fmtDay(String? raw) {
    final d = _parseLocal(raw);
    if (d == null) return raw ?? '—';
    return '${_wk[d.weekday - 1]}, ${d.day.toString().padLeft(2, '0')} ${_mo[d.month - 1]} ${d.year}';
  }

  String _fmtTime(String? raw) {
    final d = _parseLocal(raw);
    if (d == null) return '—';
    return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  String _duration(Map<String, dynamic> r) {
    final inAt = _parseLocal(r['punch_in_time'] as String?);
    final outAt = _parseLocal(r['punch_out_time'] as String?);
    if (inAt == null) return '—';
    if (outAt == null) return 'ongoing';
    final d = outAt.difference(inAt);
    return '${d.inHours}h ${d.inMinutes % 60}m';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F6F6),
      appBar: AppBar(
        backgroundColor: _gold,
        foregroundColor: Colors.white,
        title: Text('${widget.name} — Route History',
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: Column(
        children: [
          _monthBar(),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _monthBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: () => _changeMonth(-1),
          ),
          Text(
            '${_mo[_month.month - 1]} ${_month.year}',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: _atCurrentMonth ? null : () => _changeMonth(1),
          ),
        ],
      ),
    );
  }

  /// Route days keyed 'yyyy-mm-dd' for the calendar grid.
  Map<String, Map<String, dynamic>> get _byDate => {
        for (final r in _records)
          if ((r['date'] as String? ?? '').isNotEmpty) r['date'] as String: r,
      };

  void _openDay(Map<String, dynamic> r) {
    final date = r['date'] as String? ?? '';
    if (date.isEmpty) return;
    context.push('/route-view', extra: {
      'mobile': widget.mobile,
      'name': widget.name,
      'date': date,
    });
  }

  /// Month calendar: tinted day cells have a recorded route — tap to open it.
  Widget _calendar() {
    final byDate = _byDate;
    final first = DateTime(_month.year, _month.month, 1);
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final leadingBlanks = first.weekday - 1; // Monday-first grid
    final today = DateTime.now();

    final cells = <Widget>[
      for (final w in _wk)
        Center(
            child: Text(w.substring(0, 2),
                style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade500))),
      for (var i = 0; i < leadingBlanks; i++) const SizedBox.shrink(),
      for (var d = 1; d <= daysInMonth; d++)
        _dayCell(d, byDate[
            '${_month.year}-${_month.month.toString().padLeft(2, '0')}-${d.toString().padLeft(2, '0')}'],
            isToday: today.year == _month.year &&
                today.month == _month.month &&
                today.day == d),
    ];

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
      child: GridView.count(
        crossAxisCount: 7,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        childAspectRatio: 1.25,
        children: cells,
      ),
    );
  }

  Widget _dayCell(int day, Map<String, dynamic>? r, {required bool isToday}) {
    final hasRoute = r != null;
    final interrupted =
        r?['was_interrupted'] == true || r?['was_interrupted'] == 1;
    final km = r?['total_distance_km'] as num?;

    return InkWell(
      onTap: hasRoute ? () => _openDay(r) : null,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: hasRoute
              ? (interrupted ? Colors.orange.shade50 : const Color(0xFFEAF3EC))
              : null,
          borderRadius: BorderRadius.circular(8),
          border: isToday ? Border.all(color: _gold, width: 1.5) : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('$day',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: hasRoute ? FontWeight.w700 : FontWeight.w400,
                    color: hasRoute ? Colors.black87 : Colors.grey.shade500)),
            if (hasRoute)
              Text(km != null ? formatDistance(km) : '•',
                  style: TextStyle(
                      fontSize: 8.5,
                      color: interrupted
                          ? Colors.orange.shade800
                          : const Color(0xFF2F7D46))),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: _gold));
    }
    if (_records.isEmpty) {
      return Center(
        child: Text('No routes this month',
            style: TextStyle(fontSize: 15, color: Colors.grey.shade600)),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _records.length + 1,
      itemBuilder: (context, i) => i == 0 ? _calendar() : _row(_records[i - 1]),
    );
  }

  Widget _row(Map<String, dynamic> r) {
    final interrupted = r['was_interrupted'] == true || r['was_interrupted'] == 1;
    final autoClosed = r['auto_closed'] == true || r['auto_closed'] == 1;
    final km = r['total_distance_km'] as num?;
    final date = r['date'] as String? ?? '';

    return Card(
      elevation: 1,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        onTap: date.isEmpty
            ? null
            : () => context.push('/route-view', extra: {
                  'mobile': widget.mobile,
                  'name': widget.name,
                  'date': date,
                }),
        title: Row(
          children: [
            Flexible(
              child: Text(_fmtDay(date),
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 14.5, fontWeight: FontWeight.w600)),
            ),
            if (interrupted) ...[
              const SizedBox(width: 6),
              const Tooltip(
                message: kGapWarningText,
                child: Text('⚠️', style: TextStyle(fontSize: 13)),
              ),
            ],
            if (autoClosed) ...[
              const SizedBox(width: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.orange.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('auto-closed',
                    style: TextStyle(
                        fontSize: 10, color: Colors.orange.shade900)),
              ),
            ],
          ],
        ),
        subtitle: Text(
          'In ${_fmtTime(r['punch_in_time'] as String?)} · '
          'Out ${_fmtTime(r['punch_out_time'] as String?)} · '
          '${_duration(r)}',
          style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
        ),
        trailing: Text(
          formatDistance(km),
          style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}

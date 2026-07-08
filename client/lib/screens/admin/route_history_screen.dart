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
      itemCount: _records.length,
      itemBuilder: (context, i) => _row(_records[i]),
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

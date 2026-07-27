import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../services/api_service.dart';
import '../../utils/distance_format.dart';

/// Admin: date-first route-history roster.
///
/// Opened from the calendar button on the live-salesmen screen. Lists everyone
/// who was on duty on the selected date with their on-duty window + distance;
/// tapping a salesman opens that day's route (/route-view, road-snapped for
/// closed days). One fetch per date change, NO polling — this is history.
class HistoryRosterScreen extends StatefulWidget {
  final String date; // yyyy-mm-dd

  const HistoryRosterScreen({super.key, required this.date});

  @override
  State<HistoryRosterScreen> createState() => _HistoryRosterScreenState();
}

class _HistoryRosterScreenState extends State<HistoryRosterScreen> {
  static const _gold = Color(0xFFD7BE69);
  static const _wk = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _mo = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];

  late DateTime _date;
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _date = _parseDate(widget.date) ?? _today();
    _load();
  }

  static DateTime _today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  DateTime? _parseDate(String raw) {
    final d = DateTime.tryParse(raw);
    return d == null ? null : DateTime(d.year, d.month, d.day);
  }

  String _fmtDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  bool get _atToday {
    final t = _today();
    return _date.year == t.year && _date.month == t.month && _date.day == t.day;
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final res = await ApiService.getRoster(date: _fmtDate(_date));
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res != null && res['success'] == true) {
        _error = null;
        _items = List<Map<String, dynamic>>.from(res['data'] as List);
      } else {
        _error = 'Could not load roster';
        _items = [];
      }
    });
  }

  void _changeDay(int delta) {
    setState(() => _date = DateTime(_date.year, _date.month, _date.day + delta));
    _load();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(_today().year - 1, 1, 1),
      lastDate: _today(),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: Theme.of(context)
              .colorScheme
              .copyWith(primary: _gold, onPrimary: Colors.white),
        ),
        child: child!,
      ),
    );
    if (picked == null || !mounted) return;
    setState(() => _date = DateTime(picked.year, picked.month, picked.day));
    _load();
  }

  // ── Formatting: server sends UTC-Z; show local (timezone convention). ──
  DateTime? _parseLocal(String? raw) =>
      raw == null ? null : DateTime.tryParse(raw)?.toLocal();

  String _dayLabel(DateTime d) =>
      '${_wk[d.weekday - 1]}, ${d.day.toString().padLeft(2, '0')} ${_mo[d.month - 1]} ${d.year}';

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
        title: const Text('Route History',
            style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: Column(
        children: [
          _dateBar(),
          Expanded(
            child: RefreshIndicator(
              color: _gold,
              onRefresh: _load,
              child: _buildBody(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dateBar() {
    return Material(
      color: Colors.white,
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left),
              tooltip: 'Previous day',
              onPressed: () => _changeDay(-1),
            ),
            Expanded(
              child: InkWell(
                onTap: _pickDate,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.calendar_month, size: 18, color: _gold),
                      const SizedBox(width: 8),
                      Text(_dayLabel(_date),
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              tooltip: 'Next day',
              onPressed: _atToday ? null : () => _changeDay(1),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: _gold));
    }
    if (_error != null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 160),
          Icon(Icons.cloud_off, size: 56, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          Center(
              child: Text(_error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade600))),
        ],
      );
    }
    if (_items.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 160),
          Icon(Icons.event_busy, size: 56, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          Center(
            child: Text('No salesmen on duty on this date',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Colors.grey.shade600)),
          ),
        ],
      );
    }
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(12),
      itemCount: _items.length,
      itemBuilder: (context, i) => _row(_items[i]),
    );
  }

  Widget _row(Map<String, dynamic> item) {
    final interrupted = item['was_interrupted'] == true;
    final autoClosed = item['auto_closed'] == true;
    final name = (item['name'] as String?) ??
        (item['employee_mobile'] as String?) ??
        '?';
    final initial = name.isNotEmpty ? name.substring(0, 1).toUpperCase() : '?';

    return Card(
      elevation: 1,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        onTap: () => context.push('/route-view', extra: {
          'mobile': item['employee_mobile'],
          'name': name,
          'date': _fmtDate(_date),
        }),
        leading: CircleAvatar(
          backgroundColor: _gold.withValues(alpha: 0.2),
          child: Text(initial,
              style: const TextStyle(
                  color: Color(0xFF8A6D1F), fontWeight: FontWeight.bold)),
        ),
        title: Row(
          children: [
            Flexible(
              child: Text(name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
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
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.orange.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('auto-closed',
                    style:
                        TextStyle(fontSize: 10, color: Colors.orange.shade900)),
              ),
            ],
          ],
        ),
        subtitle: Text(
          'In ${_fmtTime(item['punch_in_time'] as String?)} · '
          'Out ${_fmtTime(item['punch_out_time'] as String?)} · '
          '${_duration(item)} · '
          '📏 ${formatDistance(item['distance_km'] as num?, hasGaps: item['has_gaps'] == true)}',
          style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
        ),
        trailing: const Icon(Icons.chevron_right, size: 20),
      ),
    );
  }
}

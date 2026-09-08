import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../services/api_service.dart';
import '../../widgets/attendance_day_card.dart';

class AttendanceEmployeeScreen extends StatefulWidget {
  final String employeeMobile;
  final Map<String, dynamic>? initialEmployee;

  const AttendanceEmployeeScreen({
    super.key,
    required this.employeeMobile,
    this.initialEmployee,
  });

  @override
  State<AttendanceEmployeeScreen> createState() =>
      _AttendanceEmployeeScreenState();
}

class _AttendanceEmployeeScreenState extends State<AttendanceEmployeeScreen> {
  static const _gold = Color(0xFFD7BE69);

  // ── Adjustable spacing knobs ────────────────────────────────────────────────
  // Tweak these to make the whole layout tighter or roomier.
  static const double _pagePad     = 12; // outer page padding
  static const double _sectionGap  = 14; // gap between major sections
  static const double _cellGap     = 6;  // gap between calendar day cells
  static const double _cellRadius  = 10; // day-cell corner radius

  // ── Status palette (also used for legend + dots) ────────────────────────────
  static const _green  = Color(0xFF43A047);
  static const _red    = Color(0xFFE53935);
  static const _orange = Color(0xFFF59E0B);
  static const _blue   = Color(0xFF1E88E5);
  static const _teal   = Color(0xFF00ACC1);

  // first day of the month shown; initialised at declaration so a hot reload
  // (which doesn't re-run initState) can never leave it uninitialised.
  DateTime  _visibleMonth = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime? _selectedDay  = DateTime.now();   // currently tapped day
  final Map<String, Map<String, dynamic>> _byDate = {}; // 'yyyy-mm-dd' → record
  bool    _loading = false;
  String? _error;

  String get _name =>
      widget.initialEmployee?['name'] as String? ?? widget.employeeMobile;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _visibleMonth = DateTime(now.year, now.month, 1);
    _selectedDay  = DateTime(now.year, now.month, now.day);
    _loadMonth();
  }

  Future<void> _loadMonth() async {
    setState(() => _loading = true);
    try {
      final records = await ApiService.adminAttendanceMonth(
          widget.employeeMobile, _visibleMonth.year, _visibleMonth.month);
      if (!mounted) return;
      _byDate.clear();
      for (final r in records) {
        final key = _keyOf(r['date'] as String?);
        if (key != null) _byDate[key] = r;
      }
      setState(() { _error = null; _loading = false; });
    } catch (_) {
      if (mounted) setState(() { _error = 'Failed to load'; _loading = false; });
    }
  }

  void _changeMonth(int delta) {
    setState(() {
      _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month + delta, 1);
      _selectedDay  = null;
    });
    _loadMonth();
  }

  // ── Date helpers ─────────────────────────────────────────────────────────────
  static const _wk = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];
  static const _mo = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];

  String _dayKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';

  /// Extract the 'yyyy-mm-dd' portion from a record's date string.
  /// Parses and converts to local time first: a UTC-serialized date
  /// ("...T18:30:00Z") substring'd directly lands on the previous day.
  String? _keyOf(String? raw) {
    if (raw == null) return null;
    final d = DateTime.tryParse(raw)?.toLocal();
    if (d != null) {
      return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    }
    return raw.length >= 10 ? raw.substring(0, 10) : raw;
  }

  String _fmtDate(String? raw) {
    if (raw == null) return '—';
    try {
      final d = DateTime.parse(raw).toLocal();
      return '${_wk[d.weekday-1]}, ${d.day.toString().padLeft(2,'0')} ${_mo[d.month-1]} ${d.year}';
    } catch (_) { return raw; }
  }

  String _fmtTime(String? raw) {
    if (raw == null) return '—';
    try {
      final d = DateTime.parse(raw).toLocal();
      final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
      final m = d.minute.toString().padLeft(2, '0');
      return '$h:$m ${d.hour < 12 ? "AM" : "PM"}';
    } catch (_) { return raw; }
  }

  String _fmtMins(int? mins) {
    if (mins == null || mins == 0) return '—';
    final h = mins ~/ 60, m = mins % 60;
    return h > 0 ? '${h}h ${m}m' : '${m}m';
  }

  Color _dayColor(Map<String, dynamic> r) {
    final status = (r['status'] as String?) ?? 'on_time';
    if (r['is_late'] == true) return _red;
    return switch (status) {
      'approved' => _blue,
      'rejected' => _red,
      'pending'  => _orange,
      'early_in' => _teal,
      _          => _green,
    };
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_name,
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
            const Text('Attendance Calendar',
                style: TextStyle(fontSize: 11, color: Colors.white70)),
          ],
        ),
        backgroundColor: _gold,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Shift Settings',
            onPressed: () => context.push(
              '/attendance-manage/${widget.employeeMobile}/settings',
              extra: widget.initialEmployee,
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadMonth,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(_pagePad, _pagePad, _pagePad, 28),
          children: [
            _buildMonthHeader(),
            const SizedBox(height: _sectionGap),
            _buildCalendar(),
            const SizedBox(height: _sectionGap),
            _buildSummary(),
            const SizedBox(height: _sectionGap),
            _buildSelectedDetail(),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Center(child: Text(_error!, style: const TextStyle(color: Colors.red))),
            ],
          ],
        ),
      ),
    );
  }

  // ── Month navigator ──────────────────────────────────────────────────────────
  Widget _buildMonthHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(
            color: Colors.black.withValues(alpha: 0.05), blurRadius: 4, offset: const Offset(0, 1))],
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left_rounded),
            onPressed: () => _changeMonth(-1),
          ),
          Expanded(
            child: Center(
              child: Text(
                '${_mo[_visibleMonth.month - 1]} ${_visibleMonth.year}',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
              ),
            ),
          ),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(12),
              child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else
            IconButton(
              icon: const Icon(Icons.chevron_right_rounded),
              onPressed: () => _changeMonth(1),
            ),
        ],
      ),
    );
  }

  // ── Calendar grid ──────────────────────────────────────────────────────────
  Widget _buildCalendar() {
    final year = _visibleMonth.year, month = _visibleMonth.month;
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final leading = DateTime(year, month, 1).weekday - 1; // Mon-based offset
    final totalCells = ((leading + daysInMonth) / 7).ceil() * 7;
    final today = DateTime.now();

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(
            color: Colors.black.withValues(alpha: 0.05), blurRadius: 4, offset: const Offset(0, 1))],
      ),
      child: Column(
        children: [
          // Weekday header
          Row(
            children: _wk.map((w) => Expanded(
              child: Center(
                child: Text(w,
                    style: TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w700,
                        color: Colors.grey.shade500)),
              ),
            )).toList(),
          ),
          const SizedBox(height: 6),
          // Day grid
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: totalCells,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisSpacing: _cellGap,
              crossAxisSpacing: _cellGap,
              childAspectRatio: 1,
            ),
            itemBuilder: (ctx, i) {
              final dayNum = i - leading + 1;
              if (dayNum < 1 || dayNum > daysInMonth) return const SizedBox.shrink();

              final date = DateTime(year, month, dayNum);
              final key  = _dayKey(date);
              final rec  = _byDate[key];
              final isToday = date.year == today.year &&
                  date.month == today.month && date.day == today.day;
              final isSelected = _selectedDay != null &&
                  _dayKey(_selectedDay!) == key;
              final isFuture = date.isAfter(DateTime(today.year, today.month, today.day));

              final color = rec != null ? _dayColor(rec) : null;

              return GestureDetector(
                onTap: () => setState(() => _selectedDay = date),
                child: Container(
                  decoration: BoxDecoration(
                    color: isSelected
                        ? (color ?? _gold)
                        : (color != null ? color.withValues(alpha: 0.10) : Colors.transparent),
                    borderRadius: BorderRadius.circular(_cellRadius),
                    border: Border.all(
                      color: isToday
                          ? _gold
                          : (isSelected ? (color ?? _gold) : Colors.transparent),
                      width: isToday ? 1.5 : 1,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '$dayNum',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: isToday || isSelected ? FontWeight.w800 : FontWeight.w500,
                          color: isSelected
                              ? Colors.white
                              : (isFuture ? Colors.grey.shade400 : Colors.black87),
                        ),
                      ),
                      const SizedBox(height: 3),
                      // status dot
                      Container(
                        width: 6, height: 6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isSelected
                              ? Colors.white
                              : (color ?? Colors.transparent),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  // ── Month performance summary ────────────────────────────────────────────────
  Widget _buildSummary() {
    final records = _byDate.values.toList();
    final present = records.where((r) => r['punch_in_time'] != null).length;
    final late    = records.where((r) => r['is_late'] == true).length;
    final early   = records.where((r) => r['is_early_out'] == true).length;
    final totalWork = records.fold<int>(
        0, (s, r) => s + ((r['total_work_minutes'] as int?) ?? 0));

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(
            color: Colors.black.withValues(alpha: 0.05), blurRadius: 4, offset: const Offset(0, 1))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.insights_rounded, size: 16, color: _gold),
              const SizedBox(width: 6),
              Text('${_mo[_visibleMonth.month - 1]} Performance',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _stat('Present', '$present', _green),
              _stat('Late', '$late', _red),
              _stat('Early Out', '$early', _orange),
              _stat('Work', _fmtMins(totalWork), _blue),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stat(String label, String value, Color color) {
    return Expanded(
      child: Column(
        children: [
          Text(value,
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: color)),
          const SizedBox(height: 2),
          Text(label,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
        ],
      ),
    );
  }

  // ── Selected day detail ──────────────────────────────────────────────────────
  Widget _buildSelectedDetail() {
    if (_selectedDay == null) {
      return _emptyDetail('Tap a date to see its details');
    }
    final key = _dayKey(_selectedDay!);
    final rec = _byDate[key];
    final headerDate = _fmtDate(_selectedDay!.toIso8601String());

    if (rec == null) {
      final isFuture = _selectedDay!.isAfter(DateTime.now());
      return _emptyDetail(isFuture
          ? '$headerDate\nUpcoming — no attendance yet'
          : '$headerDate\nNo attendance recorded');
    }

    return AttendanceDayCard(
      record:  rec,
      fmtDate: _fmtDate,
      fmtTime: _fmtTime,
      fmtMins: _fmtMins,
    );
  }

  Widget _emptyDetail(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFEEEEEE)),
      ),
      child: Column(
        children: [
          const Icon(Icons.event_note_outlined, size: 40, color: Colors.black26),
          const SizedBox(height: 8),
          Text(text,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.black45, fontSize: 13)),
        ],
      ),
    );
  }
}

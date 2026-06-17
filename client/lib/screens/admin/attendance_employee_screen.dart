import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/api_service.dart';
import '../../services/api_config.dart';

Future<void> _openMaps(double lat, double lng) async {
  final uri = Uri.parse('https://maps.google.com/?q=$lat,$lng');
  if (await canLaunchUrl(uri)) launchUrl(uri);
}

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
  String? _keyOf(String? raw) {
    if (raw == null) return null;
    return raw.length >= 10 ? raw.substring(0, 10) : raw;
  }

  String _fmtDate(String? raw) {
    if (raw == null) return '—';
    try {
      final d = DateTime.parse(raw);
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

    return _AttendanceCard(
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

// ═══════════════════════════════════════════════════════════════════════════════
// Attendance Card — display only, no approval actions
// ═══════════════════════════════════════════════════════════════════════════════

class _AttendanceCard extends StatelessWidget {
  final Map<String, dynamic> record;
  final String Function(String?) fmtDate;
  final String Function(String?) fmtTime;
  final String Function(int?)    fmtMins;

  const _AttendanceCard({
    required this.record,
    required this.fmtDate,
    required this.fmtTime,
    required this.fmtMins,
  });

  static const _green  = Color(0xFF43A047);
  static const _red    = Color(0xFFE53935);
  static const _orange = Color(0xFFF59E0B);
  static const _blue   = Color(0xFF1E88E5);

  static const _teal = Color(0xFF00ACC1);

  Color _statusColor(String s) => switch (s) {
    'approved' => _blue,
    'rejected' => _red,
    'pending'  => _orange,
    'early_in' => _teal,
    _          => _green,
  };

  String _statusLabel(String s) => switch (s) {
    'approved' => 'Approved',
    'rejected' => 'Rejected',
    'pending'  => 'Pending',
    'early_in' => 'Early In',
    _          => 'On Time',
  };

  IconData _statusIcon(String s) => switch (s) {
    'approved' => Icons.check_circle_outline,
    'rejected' => Icons.cancel_outlined,
    'pending'  => Icons.hourglass_empty_rounded,
    'early_in' => Icons.alarm_rounded,
    _          => Icons.check_circle_outline,
  };

  @override
  Widget build(BuildContext context) {
    final r          = record;
    final status     = (r['status'] as String?) ?? 'on_time';
    final isLate     = r['is_late']      == true;
    final isEarly    = r['is_early_out'] == true;
    final isEarlyIn  = r['is_early_in']  == true;
    final workMins   = r['total_work_minutes']  as int?;
    final breakMins  = r['total_break_minutes'] as int?;
    final inPhoto    = r['punch_in_photo']  as String?;
    final outPhoto   = r['punch_out_photo'] as String?;
    final inLoc      = r['punch_in_location']  as Map?;
    final outLoc     = r['punch_out_location'] as Map?;
    final breaks     = r['break_details']  as List?;
    final lateReason    = r['late_reason']       as String?;
    final earlyReason   = r['early_out_reason']  as String?;
    final earlyInReason = r['early_in_reason']   as String?;
    final adminNotes    = r['admin_notes']        as String?;

    final sc = _statusColor(status);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: sc.withValues(alpha: 0.18), width: 1),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 4, offset: const Offset(0, 1)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          // ── Header ─────────────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: sc.withValues(alpha: 0.06),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
            ),
            child: Row(
              children: [
                Icon(Icons.calendar_today_rounded, size: 13, color: sc),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    fmtDate(r['date'] as String?),
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w700,
                        color: Colors.black87),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: sc.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(_statusIcon(status), size: 11, color: sc),
                      const SizedBox(width: 3),
                      Text(_statusLabel(status),
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: sc)),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── Body ───────────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [

                // ── Punch In / Out side by side ──────────────────────────────
                Row(
                  children: [
                    Expanded(child: _PunchCell(
                      icon: Icons.login_rounded,
                      label: 'Punch In',
                      time: fmtTime(r['punch_in_time'] as String?),
                      flag: isLate ? 'LATE' : (isEarlyIn ? 'EARLY' : null),
                      flagColor: isLate ? _red : _teal,
                      location: inLoc,
                    )),
                    Container(width: 1, height: 56, color: const Color(0xFFEEEEEE)),
                    Expanded(child: _PunchCell(
                      icon: Icons.logout_rounded,
                      label: 'Punch Out',
                      time: fmtTime(r['punch_out_time'] as String?),
                      flag: isEarly ? 'EARLY' : null,
                      flagColor: _orange,
                      location: outLoc,
                    )),
                  ],
                ),

                // ── Work / Break chips ────────────────────────────────────────
                if ((workMins ?? 0) > 0) ...[
                  const SizedBox(height: 10),
                  const Divider(height: 1, color: Color(0xFFF0F0F0)),
                  const SizedBox(height: 8),
                  Row(children: [
                    _Chip(Icons.timer_outlined, fmtMins(workMins), _green, 'Work'),
                    if ((breakMins ?? 0) > 0) ...[
                      const SizedBox(width: 8),
                      _Chip(Icons.local_cafe_outlined, fmtMins(breakMins), _orange, 'Break'),
                    ],
                  ]),
                ],

                // ── Reasons ──────────────────────────────────────────────────
                if (isLate && (lateReason?.isNotEmpty ?? false)) ...[
                  const SizedBox(height: 8),
                  _ReasonRow(Icons.schedule_rounded, 'Late reason', lateReason!, _red),
                ],
                if (isEarlyIn && (earlyInReason?.isNotEmpty ?? false)) ...[
                  const SizedBox(height: 6),
                  _ReasonRow(Icons.alarm_rounded, 'Early-in reason', earlyInReason!, _teal),
                ],
                if (isEarly && (earlyReason?.isNotEmpty ?? false)) ...[
                  const SizedBox(height: 6),
                  _ReasonRow(Icons.exit_to_app_rounded, 'Early-out reason', earlyReason!, _orange),
                ],
                if (adminNotes?.isNotEmpty ?? false) ...[
                  const SizedBox(height: 6),
                  _ReasonRow(Icons.admin_panel_settings_outlined, 'Admin note', adminNotes!, _blue),
                ],

                // ── Photos ────────────────────────────────────────────────────
                if (inPhoto != null || outPhoto != null) ...[
                  const SizedBox(height: 10),
                  const Divider(height: 1, color: Color(0xFFF0F0F0)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      if (inPhoto != null)
                        Expanded(child: _PhotoThumb('In', ApiConfig.baseUrl + inPhoto)),
                      if (inPhoto != null && outPhoto != null)
                        const SizedBox(width: 6),
                      if (outPhoto != null)
                        Expanded(child: _PhotoThumb('Out', ApiConfig.baseUrl + outPhoto)),
                    ],
                  ),
                ],

                // ── Breaks ────────────────────────────────────────────────────
                if (breaks != null && breaks.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  const Divider(height: 1, color: Color(0xFFF0F0F0)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: breaks.map((b) {
                      final bm    = b as Map;
                      final type  = (bm['type'] as String? ?? '').toUpperCase();
                      final start = _fmtBreak(bm['start'] as String?);
                      final end   = _fmtBreak(bm['end']   as String?);
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: _orange.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: _orange.withValues(alpha: 0.22)),
                        ),
                        child: Text(
                          '$type  $start → ${end ?? "ongoing"}',
                          style: const TextStyle(fontSize: 10, color: Color(0xFFF59E0B),
                              fontWeight: FontWeight.w600),
                        ),
                      );
                    }).toList(),
                  ),
                ],

              ],
            ),
          ),
        ],
      ),
    );
  }

  static String? _fmtBreak(String? raw) {
    if (raw == null) return null;
    try {
      final d = DateTime.parse(raw).toLocal();
      final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
      return '$h:${d.minute.toString().padLeft(2,'0')} ${d.hour<12?"AM":"PM"}';
    } catch (_) { return raw; }
  }
}

// ─── Punch cell ───────────────────────────────────────────────────────────────

class _PunchCell extends StatelessWidget {
  final IconData icon;
  final String   label;
  final String   time;
  final String?  flag;
  final Color    flagColor;
  final Map?     location;

  const _PunchCell({
    required this.icon,
    required this.label,
    required this.time,
    required this.flagColor,
    this.flag,
    this.location,
  });

  @override
  Widget build(BuildContext context) {
    final hasLoc  = location?['lat'] != null && location?['lng'] != null;
    final lat     = hasLoc ? (location!['lat'] as num).toDouble() : 0.0;
    final lng     = hasLoc ? (location!['lng'] as num).toDouble() : 0.0;
    final iColor  = flag != null ? flagColor : const Color(0xFF43A047);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Label row
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 12, color: iColor),
              const SizedBox(width: 4),
              Text(label,
                  style: TextStyle(
                      fontSize: 10, fontWeight: FontWeight.w600, color: iColor)),
              if (flag != null) ...[
                const SizedBox(width: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: flagColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(flag!,
                      style: TextStyle(
                          fontSize: 8, fontWeight: FontWeight.w800, color: flagColor)),
                ),
              ],
            ],
          ),
          const SizedBox(height: 3),
          // Time
          Text(time,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 3),
          // Location
          if (hasLoc)
            GestureDetector(
              onTap: () => _openMaps(lat, lng),
              child: Text.rich(
                TextSpan(children: [
                  const WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: Icon(Icons.location_on_rounded, size: 10,
                        color: Color(0xFF1E88E5)),
                  ),
                  TextSpan(
                    text: ' ${lat.toStringAsFixed(3)}, ${lng.toStringAsFixed(3)}',
                    style: const TextStyle(
                        fontSize: 9,
                        color: Color(0xFF1E88E5),
                        decoration: TextDecoration.underline),
                  ),
                ]),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            )
          else
            const Text('No location',
                style: TextStyle(fontSize: 9, color: Colors.black38)),
        ],
      ),
    );
  }
}

// ─── Work / Break chip ────────────────────────────────────────────────────────

class _Chip extends StatelessWidget {
  final IconData icon;
  final String   value;
  final Color    color;
  final String   label;

  const _Chip(this.icon, this.value, this.color, this.label);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.20)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: TextStyle(fontSize: 9, color: color, fontWeight: FontWeight.w500)),
              Text(value,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Reason row ───────────────────────────────────────────────────────────────

class _ReasonRow extends StatelessWidget {
  final IconData icon;
  final String   label;
  final String   text;
  final Color    color;

  const _ReasonRow(this.icon, this.label, this.text, this.color);

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 11, color: color),
        ),
        const SizedBox(width: 5),
        Expanded(
          child: Text.rich(
            TextSpan(children: [
              TextSpan(
                text: '$label: ',
                style: TextStyle(
                    fontSize: 10, fontWeight: FontWeight.w700, color: color),
              ),
              TextSpan(
                text: text,
                style: const TextStyle(fontSize: 10, color: Colors.black87),
              ),
            ]),
          ),
        ),
      ],
    );
  }
}

// ─── Photo thumbnail ──────────────────────────────────────────────────────────

class _PhotoThumb extends StatelessWidget {
  final String label;
  final String url;

  const _PhotoThumb(this.label, this.url);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => showDialog(
        context: context,
        builder: (_) => Dialog(
          insetPadding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: Text('$label Photo',
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 14)),
              ),
              ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(bottom: Radius.circular(8)),
                child: Image.network(url,
                    fit: BoxFit.contain,
                    errorBuilder: (ctx, e, st) => const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('Image unavailable',
                            style: TextStyle(color: Colors.grey)))),
              ),
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close')),
            ],
          ),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          children: [
            Image.network(url,
                width: double.infinity,
                height: 64,
                fit: BoxFit.cover,
                errorBuilder: (ctx, e, st) => Container(
                    width: double.infinity,
                    height: 64,
                    color: Colors.grey.shade100,
                    child: const Icon(Icons.broken_image_outlined,
                        color: Colors.grey, size: 22))),
            Positioned(
              bottom: 0, left: 0, right: 0,
              child: Container(
                color: Colors.black38,
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 9, fontWeight: FontWeight.w600,
                        color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../services/api_config.dart';
import '../../services/api_service.dart';
import '../../services/user_service.dart';
import '../../widgets/attendance_day_card.dart';
import '../../widgets/call_recording_player.dart';
import '../../widgets/single_location_map_screen.dart';
import '../telecaller/call_date_filter.dart';
import '../telecaller/telecaller_mock_data.dart'
    show kGold, kGoldDark, kBg, kOutcomeColors, kOutcomeLabels, money;

/// A single person's full day(s), read-only: every attendance record (via the
/// shared [AttendanceDayCard]), every completed shop visit, and every call.
///
/// Two modes:
///  - **Team drill-in** — [mobile] is a subordinate; date range comes fixed via
///    [from]/[to] from [TeamReportScreen]. No date filter here.
///  - **Self ("My Report")** — [mobile] omitted; uses the logged-in staff
///    member and carries its own date-range filter. Any salesman / telecaller
///    can open it; the server's `/team/my-report` has no role gate.
class TeamReportEmployeeScreen extends StatefulWidget {
  final String? mobile;
  final String name;
  final String role;
  final String? from;
  final String? to;

  const TeamReportEmployeeScreen({
    super.key,
    this.mobile,
    this.name = '',
    this.role = '',
    this.from,
    this.to,
  });

  @override
  State<TeamReportEmployeeScreen> createState() => _TeamReportEmployeeScreenState();
}

enum _Show { all, attendance, visits, calls }

const _showLabels = <_Show, String>{
  _Show.all: 'Everything',
  _Show.attendance: 'Attendance',
  _Show.visits: 'Visits',
  _Show.calls: 'Calls',
};

class _TeamReportEmployeeScreenState extends State<TeamReportEmployeeScreen> {
  bool _loading = true;
  String _error = '';
  Map<String, dynamic>? _data;

  // Self-mode ("My Report") date filter — ignored in team drill-in mode.
  CallDateFilter _dateFilter = CallDateFilter.today;
  DateTimeRange? _customRange;
  _Show _show = _Show.all;

  bool get _selfMode => widget.mobile == null || widget.mobile!.isEmpty;
  String get _mobile => _selfMode ? (UserService.currentMobile ?? '') : widget.mobile!;
  String get _name =>
      _selfMode ? (UserService.currentName ?? 'My Report') : widget.name;

  bool get _isTeleadminViewer =>
      (UserService.currentRole ?? '').toLowerCase().replaceAll(' ', '') == 'teleadmin';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final Map<String, dynamic>? res;
    if (_selfMode) {
      final r = callDateRangeYmd(_dateFilter, _customRange);
      res = await ApiService.getMyReport(from: r.from, to: r.to);
    } else {
      res = await ApiService.getTeamReportEmployee(widget.mobile!,
          from: widget.from, to: widget.to);
    }
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res == null) {
        _error = _selfMode
            ? "Couldn't load your report — check your connection and retry."
            : "Couldn't load this employee's report — you may not have access, "
                'or the connection dropped.';
        _data = null;
      } else {
        _error = '';
        _data = (res['data'] as Map?)?.cast<String, dynamic>();
      }
    });
  }

  List<Map<String, dynamic>> _list(String key) =>
      ((_data?[key] as List?) ?? const [])
          .map((e) => (e as Map).cast<String, dynamic>())
          .toList();

  // ── formatters shared with AttendanceDayCard ─────────────────────────────
  static const _wk = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _mo = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];

  String _fmtDate(String? raw) {
    if (raw == null) return '—';
    try {
      final d = DateTime.parse(raw).toLocal();
      return '${_wk[d.weekday - 1]}, ${d.day.toString().padLeft(2, '0')} ${_mo[d.month - 1]} ${d.year}';
    } catch (_) {
      return raw;
    }
  }

  String _fmtTime(String? raw) {
    if (raw == null) return '—';
    try {
      final d = DateTime.parse(raw).toLocal();
      final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
      return '$h:${d.minute.toString().padLeft(2, '0')} ${d.hour < 12 ? "AM" : "PM"}';
    } catch (_) {
      return raw;
    }
  }

  String _fmtMins(int? mins) {
    if (mins == null || mins == 0) return '—';
    final h = mins ~/ 60, m = mins % 60;
    return h > 0 ? '${h}h ${m}m' : '${m}m';
  }

  String _fmtDateTime(String? iso) {
    if (iso == null || iso.isEmpty) return '—';
    final d = DateTime.tryParse(iso)?.toLocal();
    if (d == null) return '—';
    final day = '${d.day.toString().padLeft(2, '0')} ${_mo[d.month - 1]}';
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    return '$day · $h:${d.minute.toString().padLeft(2, '0')} ${d.hour < 12 ? "AM" : "PM"}';
  }

  String _dur(num? seconds) {
    final s = (seconds ?? 0).toInt();
    if (s <= 0) return '—';
    final h = s ~/ 3600, m = (s % 3600) ~/ 60, sec = s % 60;
    if (h > 0) return '${h}h ${m}m';
    return m > 0 ? '${m}m ${sec}s' : '${sec}s';
  }

  String _titleCase(String s) => s.isEmpty
      ? s
      : s
          .split(RegExp(r'[_\s]+'))
          .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
          .join(' ');

  bool _showAtt() => _show == _Show.all || _show == _Show.attendance;
  bool _showVis() => _show == _Show.all || _show == _Show.visits;
  bool _showCal() => _show == _Show.all || _show == _Show.calls;

  @override
  Widget build(BuildContext context) {
    final title = _selfMode
        ? 'My Report'
        : (_name.isEmpty ? (_mobile.isEmpty ? 'Report' : _mobile) : _name);
    final hasActiveFilter = _selfMode &&
        (_dateFilter != CallDateFilter.today || _show != _Show.all);

    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kGold,
        foregroundColor: Colors.white,
        title: _selfMode
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('My Report',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  Text(callDateChipLabel(_dateFilter, _customRange),
                      style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                          color: Colors.white70)),
                ],
              )
            : Text(title, overflow: TextOverflow.ellipsis),
        actions: [
          if (_selfMode)
            IconButton(
              icon: Icon(Icons.filter_list_rounded,
                  color: hasActiveFilter ? Colors.white : Colors.white70),
              tooltip: 'Filter',
              onPressed: _openFilterSheet,
            ),
          IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: kGold))
          : _error.isNotEmpty
              ? _message(_error, retry: true)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 28),
                    children: [
                      _headerCard(),
                      if (_showAtt()) ...[
                        const SizedBox(height: 14),
                        _section('Attendance', Icons.fingerprint_rounded),
                        ..._attendanceSection(),
                      ],
                      if (_showVis()) ...[
                        const SizedBox(height: 14),
                        _section('Visits', Icons.storefront_rounded),
                        ..._visitsSection(),
                      ],
                      if (_showCal()) ...[
                        const SizedBox(height: 14),
                        _section('Calls', Icons.call_rounded),
                        ..._callsSection(),
                      ],
                    ],
                  ),
                ),
    );
  }

  // ── filter sheet (self mode) ─────────────────────────────────────────────
  Future<void> _openFilterSheet() async {
    var tDate = _dateFilter;
    var tRange = _customRange;
    DateTime? tFrom = _customRange?.start;
    DateTime? tTo = _customRange?.end;
    var tShow = _show;

    await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Filter my report',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 14),
                  _sheetLabel('Period'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: CallDateFilter.values.map((f) {
                      final sel = tDate == f;
                      return ChoiceChip(
                        label: Text(callDateFilterLabels[f]!),
                        selected: sel,
                        selectedColor: kGold.withValues(alpha: 0.25),
                        labelStyle: TextStyle(
                            fontSize: 12,
                            color: sel ? kGoldDark : Colors.black87,
                            fontWeight: FontWeight.w600),
                        onSelected: (_) => setSheet(() => tDate = f),
                      );
                    }).toList(),
                  ),
                  if (tDate == CallDateFilter.custom) ...[
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(
                        child: _dateField(ctx, 'From', tFrom, (d) => setSheet(() {
                              tFrom = d;
                              if (tTo != null && tTo!.isBefore(d)) tTo = d;
                            })),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _dateField(ctx, 'To', tTo, (d) => setSheet(() {
                              tTo = d;
                              if (tFrom != null && tFrom!.isAfter(d)) tFrom = d;
                            })),
                      ),
                    ]),
                  ],
                  const SizedBox(height: 16),
                  _sheetLabel('Show'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _Show.values.map((s) {
                      final sel = tShow == s;
                      return ChoiceChip(
                        label: Text(_showLabels[s]!),
                        selected: sel,
                        selectedColor: kGold.withValues(alpha: 0.25),
                        labelStyle: TextStyle(
                            fontSize: 12,
                            color: sel ? kGoldDark : Colors.black87,
                            fontWeight: FontWeight.w600),
                        onSelected: (_) => setSheet(() => tShow = s),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 14),
                  Row(children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => setSheet(() {
                          tDate = CallDateFilter.today;
                          tRange = null;
                          tFrom = null;
                          tTo = null;
                          tShow = _Show.all;
                        }),
                        child: const Text('Reset'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                            backgroundColor: kGold, foregroundColor: Colors.white),
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Apply'),
                      ),
                    ),
                  ]),
                ],
              ),
            ),
          ),
        ),
      ),
    ).then((applied) {
      if (applied != true || !mounted) return;
      if (tDate == CallDateFilter.custom) {
        final a = tFrom ?? tTo ?? DateTime.now();
        final b = tTo ?? tFrom ?? DateTime.now();
        tRange = DateTimeRange(
            start: a.isAfter(b) ? b : a, end: a.isAfter(b) ? a : b);
      }
      final needsRefetch =
          tDate != _dateFilter || tRange != _customRange;
      setState(() {
        _dateFilter = tDate;
        _customRange = tDate == CallDateFilter.custom ? tRange : null;
        _show = tShow;
      });
      if (needsRefetch) _load();
    });
  }

  Widget _sheetLabel(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(t,
            style: const TextStyle(
                fontSize: 12, fontWeight: FontWeight.w700, color: Colors.black54)),
      );

  Widget _dateField(
    BuildContext ctx,
    String label,
    DateTime? value,
    ValueChanged<DateTime> onPick,
  ) {
    final now = DateTime.now();
    return OutlinedButton(
      onPressed: () async {
        final d = await showDatePicker(
          context: ctx,
          initialDate: value ?? now,
          firstDate: DateTime(now.year - 2),
          lastDate: now,
        );
        if (d != null) onPick(d);
      },
      style: OutlinedButton.styleFrom(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        side: BorderSide(color: Colors.grey.shade300),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 9.5, color: Colors.grey.shade500)),
          const SizedBox(height: 2),
          Row(children: [
            Icon(Icons.event_rounded, size: 13, color: Colors.grey.shade500),
            const SizedBox(width: 5),
            Text(value == null ? 'Pick date' : fmtDay(value),
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: value == null ? Colors.grey.shade400 : Colors.black87)),
          ]),
        ],
      ),
    );
  }

  // ── header ───────────────────────────────────────────────────────────────
  Widget _headerCard() {
    final emp = (_data?['employee'] as Map?)?.cast<String, dynamic>() ?? const {};
    final range = (_data?['range'] as Map?)?.cast<String, dynamic>() ?? const {};
    final role = '${emp['role'] ?? (widget.role.isNotEmpty ? widget.role : (UserService.currentRole ?? '')).toLowerCase()}';
    final isTele = role == 'telecaller';
    final rangeLabel = (range['from'] == range['to'])
        ? _fmtDate('${range['from']}')
        : '${_fmtDate('${range['from']}')}  →  ${_fmtDate('${range['to']}')}';

    return _card(Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(_name.isEmpty ? _mobile : _name,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: (isTele ? const Color(0xFF00838F) : const Color(0xFF43A047))
                    .withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(isTele ? 'TELECALLER' : 'SALESMAN',
                  style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      color: isTele
                          ? const Color(0xFF00838F)
                          : const Color(0xFF43A047))),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text('${emp['mobile'] ?? _mobile}'
            '${(emp['city'] ?? '').toString().isEmpty ? '' : ' · ${emp['city']}'}',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        const SizedBox(height: 6),
        Row(children: [
          Icon(Icons.date_range_rounded, size: 13, color: Colors.grey.shade500),
          const SizedBox(width: 5),
          Text(rangeLabel,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
      ],
    ));
  }

  Widget _section(String title, IconData icon) => Padding(
        padding: const EdgeInsets.only(bottom: 8, left: 2),
        child: Row(children: [
          Icon(icon, size: 16, color: kGoldDark),
          const SizedBox(width: 6),
          Text(title,
              style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800)),
        ]),
      );

  // ── attendance ───────────────────────────────────────────────────────────
  List<Widget> _attendanceSection() {
    final rows = _list('attendance');
    if (rows.isEmpty) {
      return [_placeholder('No attendance in this period.')];
    }
    return rows.map((r) {
      final hasRoute = r['has_route'] == true;
      final date = '${r['date'] ?? ''}';
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AttendanceDayCard(
              record: r,
              fmtDate: _fmtDate,
              fmtTime: _fmtTime,
              fmtMins: _fmtMins,
            ),
            if (hasRoute && !_selfMode && !_isTeleadminViewer)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => context.push('/route-view', extra: {
                    'mobile': _mobile,
                    'name': _name,
                    'date': date,
                  }),
                  icon: const Icon(Icons.map_rounded, size: 15),
                  label: const Text('View route on map'),
                  style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF1565C0),
                      padding: const EdgeInsets.symmetric(horizontal: 4)),
                ),
              ),
          ],
        ),
      );
    }).toList();
  }

  // ── visits ───────────────────────────────────────────────────────────────
  List<Widget> _visitsSection() {
    final rows = _list('visits');
    if (rows.isEmpty) {
      return [_placeholder('No completed visits in this period.')];
    }
    return rows.map(_visitCard).toList();
  }

  Widget _visitCard(Map<String, dynamic> v) {
    final name = '${v['account_name'] ?? v['account_id'] ?? 'Customer'}';
    final phone = '${v['account_phone'] ?? ''}';
    final area = '${v['account_area'] ?? ''}';
    final outcome = '${v['outcome_name'] ?? ''}'.trim().isNotEmpty
        ? '${v['outcome_name']}'
        : _titleCase('${v['outcome_slug'] ?? v['call_outcome'] ?? ''}');
    final inAt = _fmtDateTime('${v['check_in_at'] ?? ''}');
    final outAt = _fmtDateTime('${v['check_out_at'] ?? ''}');
    final dur = v['duration_seconds'] as num?;
    final pay = v['payment_collected'];
    final payNum = pay is num ? pay : num.tryParse('$pay');
    final notes = [
      '${v['general_notes'] ?? ''}',
      '${v['conversation_notes'] ?? ''}',
      '${v['discussion_points'] ?? ''}',
      '${v['market_note'] ?? ''}',
    ].where((s) => s.trim().isNotEmpty).join('\n').trim();
    final images = ((v['images'] as List?) ?? const []).whereType<String>().toList();
    // check_in_lat/lng and check_out_lat/lng arrive as strings (uncast decimal
    // columns) — parse defensively and fall back to the check-out fix.
    double? asDbl(dynamic x) => x == null ? null : double.tryParse('$x');
    final gpsLat = asDbl(v['check_in_lat']) ?? asDbl(v['check_out_lat']);
    final gpsLng = asDbl(v['check_in_lng']) ?? asDbl(v['check_out_lng']);
    final gpsIsCheckout = asDbl(v['check_in_lat']) == null && gpsLat != null;

    return _card(Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Expanded(
            child: Text(name,
                style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800)),
          ),
          if (outcome.isNotEmpty) _pill(outcome, kGoldDark),
        ]),
        if (phone.isNotEmpty || area.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
                [phone, area].where((s) => s.isNotEmpty).join(' · '),
                style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
          ),
        const SizedBox(height: 6),
        _kv('Check-in', inAt),
        _kv('Check-out', outAt),
        if ((dur ?? 0) > 0) _kv('Duration', _dur(dur)),
        if ((payNum ?? 0) > 0)
          _kv('Payment', '${money(payNum)} ${v['payment_mode'] ?? ''}'.trim()),
        if ('${v['order_no'] ?? ''}'.trim().isNotEmpty)
          _kv('Order no', '#${v['order_no']}'),
        if ('${v['follow_up_date'] ?? ''}'.trim().isNotEmpty)
          _kv('Follow-up', '${v['follow_up_date']}'),
        if (notes.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(notes, style: TextStyle(fontSize: 12, color: Colors.grey.shade800)),
        ],
        if (gpsLat != null && gpsLng != null) ...[
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => SingleLocationMapScreen(
                  title: '$name — ${gpsIsCheckout ? "check-out" : "check-in"}',
                  latitude: gpsLat,
                  longitude: gpsLng,
                ),
              ),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.location_on_rounded, size: 13, color: Color(0xFF1565C0)),
              const SizedBox(width: 3),
              Text(
                  '${gpsIsCheckout ? "Check-out" : "Check-in"} '
                  '${gpsLat.toStringAsFixed(4)}, ${gpsLng.toStringAsFixed(4)}',
                  style: const TextStyle(
                      fontSize: 10.5,
                      color: Color(0xFF1565C0),
                      decoration: TextDecoration.underline)),
            ]),
          ),
        ],
        if (images.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: images
                .map((p) => ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network('${ApiConfig.baseUrl}$p',
                          width: 60,
                          height: 60,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Container(
                              width: 60,
                              height: 60,
                              color: Colors.grey.shade200,
                              child: const Icon(Icons.broken_image_rounded,
                                  size: 18, color: Colors.black26))),
                    ))
                .toList(),
          ),
        ],
      ],
    ));
  }

  // ── calls ────────────────────────────────────────────────────────────────
  List<Widget> _callsSection() {
    final rows = _list('calls');
    if (rows.isEmpty) {
      return [_placeholder('No calls in this period.')];
    }
    return rows.map(_callCard).toList();
  }

  Widget _callCard(Map<String, dynamic> c) {
    final name = '${c['account_name'] ?? c['account_id'] ?? 'Customer'}';
    final outcome = '${c['outcome'] ?? ''}';
    final color = kOutcomeColors[outcome] ?? const Color(0xFF5A6472);
    final label = kOutcomeLabels[outcome] ?? _titleCase(outcome);
    final dur = (c['duration_seconds'] as num?)?.toInt() ?? 0;
    final hasRec = c['has_recording'] == true;
    final id = (c['id'] as num?)?.toInt();
    final notes = '${c['notes'] ?? ''}'.trim();

    return _card(Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(name,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          ),
          Text(_fmtDateTime('${c['called_at'] ?? ''}'),
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
        ]),
        const SizedBox(height: 4),
        Row(children: [
          _pill(label, color),
          const SizedBox(width: 8),
          if ('${c['source'] ?? ''}'.isNotEmpty)
            Text('${c['source']}',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
          const Spacer(),
          if (dur > 0)
            Text(_dur(dur),
                style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
        ]),
        if (notes.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(notes, style: TextStyle(fontSize: 12, color: Colors.grey.shade800)),
        ],
        if (hasRec && id != null) ...[
          const SizedBox(height: 8),
          CallRecordingPlayer(callLogId: id, accentColor: kGoldDark),
        ],
      ],
    ));
  }

  // ── shared bits ──────────────────────────────────────────────────────────
  Widget _card(Widget child) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFEEEEEE)),
          boxShadow: const [
            BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))
          ],
        ),
        child: child,
      );

  Widget _placeholder(String t) => _card(Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Text(t,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12.5, color: Colors.black54)),
        ),
      ));

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 1.5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
                width: 84,
                child: Text(k,
                    style: TextStyle(
                        fontSize: 11.5,
                        color: Colors.grey.shade500,
                        fontWeight: FontWeight.w600))),
            Expanded(child: Text(v, style: const TextStyle(fontSize: 12.5))),
          ],
        ),
      );

  Widget _pill(String t, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(
            color: c.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20)),
        child: Text(t,
            style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.w700, color: c)),
      );

  Widget _message(String text, {bool retry = false}) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off_rounded, size: 52, color: Colors.grey.shade300),
              const SizedBox(height: 12),
              Text(text,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
              if (retry) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _load,
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text('Retry'),
                ),
              ],
            ],
          ),
        ),
      );
}

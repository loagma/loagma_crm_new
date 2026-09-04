import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../services/api_config.dart';
import '../../services/api_service.dart';
import '../../services/user_service.dart';
import '../../widgets/attendance_day_card.dart';
import '../../widgets/call_recording_player.dart';
import '../../widgets/single_location_map_screen.dart';
import '../telecaller/telecaller_mock_data.dart'
    show kGold, kGoldDark, kBg, kOutcomeColors, kOutcomeLabels, money;

/// Team Report drill-in — one subordinate's full day(s), read-only: every
/// attendance record (via the shared [AttendanceDayCard]), every completed
/// shop visit, and every call. Reached from [TeamReportScreen]; no actions.
class TeamReportEmployeeScreen extends StatefulWidget {
  final String mobile;
  final String name;
  final String role;
  final String? from;
  final String? to;

  const TeamReportEmployeeScreen({
    super.key,
    required this.mobile,
    required this.name,
    required this.role,
    this.from,
    this.to,
  });

  @override
  State<TeamReportEmployeeScreen> createState() => _TeamReportEmployeeScreenState();
}

class _TeamReportEmployeeScreenState extends State<TeamReportEmployeeScreen> {
  bool _loading = true;
  String _error = '';
  Map<String, dynamic>? _data;

  bool get _isTeleadminViewer =>
      (UserService.currentRole ?? '').toLowerCase().replaceAll(' ', '') == 'teleadmin';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final res = await ApiService.getTeamReportEmployee(widget.mobile,
        from: widget.from, to: widget.to);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res == null) {
        _error = "Couldn't load this employee's report — you may not have access, "
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

  @override
  Widget build(BuildContext context) {
    final title = widget.name.isEmpty ? widget.mobile : widget.name;
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kGold,
        foregroundColor: Colors.white,
        title: Text(title, overflow: TextOverflow.ellipsis),
        actions: [
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
                      const SizedBox(height: 14),
                      _section('Attendance', Icons.fingerprint_rounded),
                      ..._attendanceSection(),
                      const SizedBox(height: 14),
                      _section('Visits', Icons.storefront_rounded),
                      ..._visitsSection(),
                      const SizedBox(height: 14),
                      _section('Calls', Icons.call_rounded),
                      ..._callsSection(),
                    ],
                  ),
                ),
    );
  }

  // ── header ───────────────────────────────────────────────────────────────
  Widget _headerCard() {
    final emp = (_data?['employee'] as Map?)?.cast<String, dynamic>() ?? const {};
    final range = (_data?['range'] as Map?)?.cast<String, dynamic>() ?? const {};
    final role = '${emp['role'] ?? widget.role}';
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
              child: Text(widget.name.isEmpty ? widget.mobile : widget.name,
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
        Text('${emp['mobile'] ?? widget.mobile}'
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
            if (hasRoute && !_isTeleadminViewer)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => context.push('/route-view', extra: {
                    'mobile': widget.mobile,
                    'name': widget.name,
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

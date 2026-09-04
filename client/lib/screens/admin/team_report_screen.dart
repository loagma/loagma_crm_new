import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../services/api_service.dart';
import '../telecaller/call_date_filter.dart';
import '../telecaller/telecaller_mock_data.dart'
    show kGold, kGoldDark, kBg, avatarColorFor, money;

/// Team Report — read-only rollup of a senior's subordinates' activity
/// (attendance punch in/out + distance, completed shop visits, calls) over a
/// day or a date range. One card per employee; tap for the full per-employee
/// day breakdown. No actions anywhere.
///
/// Shares the roster + filter-sheet + chip-strip language of
/// telecaller/team_call_agents_screen.dart, and the date presets of
/// call_date_filter.dart, so the two team screens read the same.
class TeamReportScreen extends StatefulWidget {
  const TeamReportScreen({super.key});

  @override
  State<TeamReportScreen> createState() => _TeamReportScreenState();
}

enum _Activity { all, visits, calls, attention }

const _activityLabels = <_Activity, String>{
  _Activity.all: 'All',
  _Activity.visits: 'Has visits',
  _Activity.calls: 'Has calls',
  _Activity.attention: 'Needs attention',
};

enum _RoleFilter { all, salesman, telecaller }

const _roleLabels = <_RoleFilter, String>{
  _RoleFilter.all: 'Everyone',
  _RoleFilter.salesman: 'Salesmen',
  _RoleFilter.telecaller: 'Telecallers',
};

enum _Sort { active, name, recent }

const _sortLabels = <_Sort, String>{
  _Sort.active: 'Most active',
  _Sort.name: 'Name (A-Z)',
  _Sort.recent: 'Recently active',
};

class _TeamReportScreenState extends State<TeamReportScreen> {
  bool _loading = true;
  String _error = '';
  Map<String, dynamic>? _data;

  CallDateFilter _dateFilter = CallDateFilter.today;
  DateTimeRange? _customRange;
  String _query = '';
  String _employeeFilter = 'all'; // 'all' or a mobile
  _Activity _activity = _Activity.all;
  _RoleFilter _roleFilter = _RoleFilter.all;
  _Sort _sort = _Sort.active;
  bool _includeLocked = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  ({String? from, String? to}) get _ymd => callDateRangeYmd(_dateFilter, _customRange);

  Future<void> _load() async {
    setState(() => _loading = true);
    final r = _ymd;
    final res = await ApiService.getTeamReport(
      from: r.from,
      to: r.to,
      includeLocked: _includeLocked,
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res == null) {
        _error = "Couldn't load the team report. You may not have access, or the "
            'connection dropped — pull to retry.';
        _data = null;
      } else {
        _error = '';
        _data = (res['data'] as Map?)?.cast<String, dynamic>();
      }
    });
  }

  // ── payload accessors ────────────────────────────────────────────────────
  List<Map<String, dynamic>> get _employees =>
      ((_data?['employees'] as List?) ?? const [])
          .map((e) => (e as Map).cast<String, dynamic>())
          .toList();
  Map<String, dynamic> get _caps =>
      ((_data?['capabilities'] as Map?) ?? const {}).cast<String, dynamic>();
  Map<String, dynamic> get _totals =>
      ((_data?['totals'] as Map?) ?? const {}).cast<String, dynamic>();
  Map<String, dynamic> get _range =>
      ((_data?['range'] as Map?) ?? const {}).cast<String, dynamic>();

  bool get _showCalls => _caps['show_calls'] == true;
  bool get _isSingleDay => _range['is_single_day'] == true;
  bool get _hasSalesmen => _employees.any((e) => e['role'] == 'salesman');
  bool get _hasTelecallers => _employees.any((e) => e['role'] == 'telecaller');

  bool get _hasActiveFilter =>
      _dateFilter != CallDateFilter.today ||
      _activity != _Activity.all ||
      _roleFilter != _RoleFilter.all ||
      _sort != _Sort.active ||
      _employeeFilter != 'all' ||
      _includeLocked;

  int _visitCount(Map<String, dynamic> e) =>
      ((e['visits'] as Map?)?['count'] as num?)?.toInt() ?? 0;
  int _callCount(Map<String, dynamic> e) =>
      ((e['calls'] as Map?)?['count'] as num?)?.toInt() ?? 0;
  int _activityScore(Map<String, dynamic> e) => _visitCount(e) + _callCount(e);

  bool _needsAttention(Map<String, dynamic> e) {
    final att = e['attendance'] as Map?;
    if (att == null) return true; // absent for the whole range
    if (_isSingleDay) {
      final latest = att['latest'] as Map?;
      return latest?['is_late'] == true || latest?['was_interrupted'] == true;
    }
    return ((att['late_count'] as num?)?.toInt() ?? 0) > 0;
  }

  String? _lastActivityIso(Map<String, dynamic> e) {
    final att = (e['attendance'] as Map?)?['latest'] as Map?;
    return (att?['punch_out_time'] ?? att?['punch_in_time']) as String?;
  }

  List<Map<String, dynamic>> get _visible {
    final q = _query.trim().toLowerCase();
    final list = _employees.where((e) {
      final matchesQuery = q.isEmpty ||
          '${e['name'] ?? ''}'.toLowerCase().contains(q) ||
          '${e['mobile'] ?? ''}'.contains(q) ||
          '${e['city'] ?? ''}'.toLowerCase().contains(q);
      final matchesEmp = _employeeFilter == 'all' || '${e['mobile']}' == _employeeFilter;
      final matchesRole = switch (_roleFilter) {
        _RoleFilter.all => true,
        _RoleFilter.salesman => e['role'] == 'salesman',
        _RoleFilter.telecaller => e['role'] == 'telecaller',
      };
      final matchesActivity = switch (_activity) {
        _Activity.all => true,
        _Activity.visits => _visitCount(e) > 0,
        _Activity.calls => _callCount(e) > 0,
        _Activity.attention => _needsAttention(e),
      };
      return matchesQuery && matchesEmp && matchesRole && matchesActivity;
    }).toList();

    switch (_sort) {
      case _Sort.active:
        list.sort((a, b) {
          final byScore = _activityScore(b).compareTo(_activityScore(a));
          return byScore != 0 ? byScore : '${a['name']}'.compareTo('${b['name']}');
        });
      case _Sort.name:
        list.sort((a, b) =>
            '${a['name']}'.toLowerCase().compareTo('${b['name']}'.toLowerCase()));
      case _Sort.recent:
        list.sort((a, b) {
          final at = DateTime.tryParse(_lastActivityIso(a) ?? '');
          final bt = DateTime.tryParse(_lastActivityIso(b) ?? '');
          if (at == null && bt == null) return '${a['name']}'.compareTo('${b['name']}');
          if (at == null) return 1;
          if (bt == null) return -1;
          return bt.compareTo(at);
        });
    }
    return list;
  }

  // ── formatting ───────────────────────────────────────────────────────────
  String _clock(String? iso) {
    if (iso == null || iso.isEmpty) return '—';
    final d = DateTime.tryParse(iso)?.toLocal();
    if (d == null) return '—';
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    return '$h:${d.minute.toString().padLeft(2, '0')} ${d.hour < 12 ? "AM" : "PM"}';
  }

  String _hm(num? minutes) {
    final m = (minutes ?? 0).toInt();
    if (m <= 0) return '0m';
    final h = m ~/ 60, mm = m % 60;
    return h > 0 ? '${h}h ${mm}m' : '${mm}m';
  }

  String _dur(num? seconds) => _hm((seconds ?? 0) / 60);

  String _km(num? v) => '${((v ?? 0).toDouble()).toStringAsFixed(1)} km';

  // ── build ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final items = _visible;
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kGold,
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Team Report', style: TextStyle(fontWeight: FontWeight.w700)),
            Text(
              callDateChipLabel(_dateFilter, _customRange),
              style: const TextStyle(
                  fontSize: 11.5, fontWeight: FontWeight.w500, color: Colors.white70),
            ),
          ],
        ),
        actions: [
          IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: _load),
        ],
      ),
      body: Column(
        children: [
          _searchRow(),
          if (_error.isEmpty) _summaryStrip(),
          if (_hasActiveFilter && _error.isEmpty) _activeChips(),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: kGold))
                : _error.isNotEmpty
                    ? _fullMessage(_error, retry: true)
                    : items.isEmpty
                        ? _fullMessage(
                            _employees.isEmpty
                                ? 'Nobody reports to you yet, or nobody has activity for '
                                    'this period.'
                                : 'No employee matches these filters.',
                          )
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView.builder(
                              padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                              itemCount: items.length,
                              itemBuilder: (_, i) => _employeeCard(items[i]),
                            ),
                          ),
          ),
          _visitCaption(),
        ],
      ),
    );
  }

  Widget _visitCaption() {
    if (_error.isNotEmpty || _employees.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 8),
      child: Text(
        'Visits appear here once the employee checks out. Read-only.',
        style: TextStyle(fontSize: 10.5, color: Colors.grey.shade500),
      ),
    );
  }

  Widget _fullMessage(String text, {bool retry = false}) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(retry ? Icons.cloud_off_rounded : Icons.groups_2_outlined,
                  size: 56, color: Colors.grey.shade300),
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

  Widget _searchRow() => Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                onChanged: (v) => setState(() => _query = v),
                decoration: InputDecoration(
                  hintText: 'Search name, number or city…',
                  prefixIcon: const Icon(Icons.search_rounded, color: kGoldDark),
                  isDense: true,
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade200)),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: kGold)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              decoration: BoxDecoration(
                color: _hasActiveFilter ? kGold.withValues(alpha: 0.15) : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: _hasActiveFilter ? kGold : Colors.grey.shade200),
              ),
              child: IconButton(
                icon: Icon(Icons.filter_list_rounded,
                    color: _hasActiveFilter ? kGoldDark : Colors.grey.shade600),
                tooltip: 'Filter',
                onPressed: _openFilterSheet,
              ),
            ),
          ],
        ),
      );

  Widget _summaryStrip() {
    final t = _totals;
    final tiles = <Widget>[
      _summaryTile('People', '${t['employees'] ?? _employees.length}'),
      _summaryTile(_isSingleDay ? 'On duty' : 'Present',
          '${_isSingleDay ? (t['on_duty'] ?? 0) : (t['present'] ?? 0)}'),
      _summaryTile('Visits', '${t['visits'] ?? 0}'),
      if (_showCalls) _summaryTile('Calls', '${t['calls'] ?? 0}'),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Row(
        children: [
          for (var i = 0; i < tiles.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(child: tiles[i]),
          ],
        ],
      ),
    );
  }

  Widget _summaryTile(String label, String value) => Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(value,
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w700, color: kGoldDark)),
            Text(label, style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600)),
          ],
        ),
      );

  Widget _activeChips() {
    String empName() {
      final e = _employees.firstWhere((x) => '${x['mobile']}' == _employeeFilter,
          orElse: () => const {});
      return '${e['name'] ?? _employeeFilter}';
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            if (_dateFilter != CallDateFilter.today)
              _chip(callDateChipLabel(_dateFilter, _customRange), () {
                setState(() {
                  _dateFilter = CallDateFilter.today;
                  _customRange = null;
                });
                _load();
              }),
            if (_employeeFilter != 'all')
              _chip(empName(), () => setState(() => _employeeFilter = 'all')),
            if (_roleFilter != _RoleFilter.all)
              _chip(_roleLabels[_roleFilter]!,
                  () => setState(() => _roleFilter = _RoleFilter.all)),
            if (_activity != _Activity.all)
              _chip(_activityLabels[_activity]!,
                  () => setState(() => _activity = _Activity.all)),
            if (_sort != _Sort.active)
              _chip(_sortLabels[_sort]!, () => setState(() => _sort = _Sort.active)),
            if (_includeLocked)
              _chip('Incl. locked', () {
                setState(() => _includeLocked = false);
                _load();
              }),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, VoidCallback onClear) => Container(
        padding: const EdgeInsets.only(left: 10, right: 4, top: 3, bottom: 3),
        decoration: BoxDecoration(
          color: kGold.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: kGold),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style: const TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w600, color: kGoldDark)),
            InkWell(
              onTap: onClear,
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.close_rounded, size: 14, color: kGoldDark),
              ),
            ),
          ],
        ),
      );

  // ── employee card ────────────────────────────────────────────────────────
  Widget _employeeCard(Map<String, dynamic> e) {
    final name = '${e['name'] ?? ''}';
    final mobile = '${e['mobile'] ?? ''}';
    final role = '${e['role'] ?? ''}';
    final locked = e['is_locked'] == true;
    final avatar = avatarColorFor(name.isEmpty ? mobile : name);
    final visits = (e['visits'] as Map?)?.cast<String, dynamic>() ?? const {};
    final calls = (e['calls'] as Map?)?.cast<String, dynamic>();
    final att = (e['attendance'] as Map?)?.cast<String, dynamic>();

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFEEEEEE)),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 3))
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          final r = _ymd;
          context.push('/team-report/employee', extra: {
            'mobile': mobile,
            'name': name,
            'role': role,
            'from': r.from,
            'to': r.to,
          });
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 42,
                width: 42,
                decoration: BoxDecoration(
                    color: avatar.withValues(alpha: 0.16), shape: BoxShape.circle),
                alignment: Alignment.center,
                child: Text(
                  (name.isNotEmpty ? name[0] : '?').toUpperCase(),
                  style: TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w700, color: avatar),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(name.isEmpty ? mobile : name,
                              style: const TextStyle(
                                  fontSize: 13.5, fontWeight: FontWeight.w700)),
                        ),
                        _rolePill(role),
                        if (locked) ...[
                          const SizedBox(width: 6),
                          Icon(Icons.lock_outline_rounded,
                              size: 14, color: Colors.grey.shade500),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    _attendanceLine(att),
                    const SizedBox(height: 7),
                    _statChips(role, visits, calls),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400),
            ],
          ),
        ),
      ),
    );
  }

  Widget _rolePill(String role) {
    final isTele = role == 'telecaller';
    final c = isTele ? const Color(0xFF00838F) : const Color(0xFF43A047);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
          color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
      child: Text(isTele ? 'TELECALLER' : 'SALESMAN',
          style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: c)),
    );
  }

  Widget _attendanceLine(Map<String, dynamic>? att) {
    const red = Color(0xFFE53935);
    const green = Color(0xFF43A047);
    TextSpan span(String t, {Color? c, FontWeight? w}) => TextSpan(
        text: t,
        style: TextStyle(
            fontSize: 11.5, color: c ?? Colors.grey.shade700, fontWeight: w));

    if (att == null) {
      return Text(_isSingleDay ? 'Absent — no punch-in' : 'No attendance in range',
          style: const TextStyle(
              fontSize: 11.5, color: red, fontWeight: FontWeight.w600));
    }

    if (_isSingleDay) {
      final l = (att['latest'] as Map?)?.cast<String, dynamic>() ?? const {};
      final dist = _km(att['distance_km']);
      if (l['on_duty'] == true) {
        return Text.rich(TextSpan(children: [
          span('On duty ', c: green, w: FontWeight.w700),
          span('since ${_clock(l['punch_in_time'] as String?)} · $dist'),
        ]));
      }
      return Text.rich(TextSpan(children: [
        if (l['is_late'] == true) span('LATE ', c: red, w: FontWeight.w800),
        span('In ${_clock(l['punch_in_time'] as String?)}'),
        span(' · Out ${_clock(l['punch_out_time'] as String?)}'),
        span(' · ${_hm(att['work_minutes'])}'),
        span(' · $dist'),
      ]));
    }

    return Text.rich(TextSpan(children: [
      span('${att['days_present'] ?? 0}/${att['days_in_range'] ?? 0} days',
          w: FontWeight.w700),
      span(' · ${_hm(att['work_minutes'])}'),
      if (((att['late_count'] as num?)?.toInt() ?? 0) > 0)
        span(' · ${att['late_count']} late', c: red, w: FontWeight.w600),
      span(' · ${_km(att['distance_km'])}'),
    ]));
  }

  Widget _statChips(
      String role, Map<String, dynamic> visits, Map<String, dynamic>? calls) {
    final vCount = (visits['count'] as num?)?.toInt() ?? 0;
    final vDur = visits['duration_seconds'] as num?;
    final vPay = visits['payment_collected'] as num?;
    final chips = <Widget>[
      _statChip(Icons.storefront_rounded, '$vCount visits',
          vCount > 0 ? kGoldDark : Colors.grey.shade500),
      if ((vDur ?? 0) > 0)
        _statChip(Icons.timer_outlined, _dur(vDur), Colors.grey.shade600),
      if ((vPay ?? 0) > 0)
        _statChip(Icons.payments_outlined, money(vPay), const Color(0xFF2E7D32)),
    ];

    if (role == 'telecaller' && _showCalls && calls != null) {
      final c = (calls['count'] as num?)?.toInt() ?? 0;
      final conn = (calls['connected'] as num?)?.toInt() ?? 0;
      final talk = calls['talk_time_seconds'] as num?;
      final rec = (calls['recordings'] as num?)?.toInt() ?? 0;
      chips.addAll([
        _statChip(Icons.call_rounded, '$c calls',
            c > 0 ? const Color(0xFF00838F) : Colors.grey.shade500),
        if (conn > 0)
          _statChip(Icons.check_circle_outline_rounded, '$conn answered',
              const Color(0xFF43A047)),
        if ((talk ?? 0) > 0)
          _statChip(Icons.schedule_rounded, _dur(talk), Colors.grey.shade600),
        if (rec > 0)
          _statChip(Icons.play_circle_outline_rounded, '$rec rec',
              const Color(0xFF1E88E5)),
      ]);
    }

    return Wrap(spacing: 6, runSpacing: 6, children: chips);
  }

  Widget _statChip(IconData icon, String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 11, color: color),
            const SizedBox(width: 3),
            Text(text,
                style: TextStyle(
                    fontSize: 10.5, fontWeight: FontWeight.w600, color: color)),
          ],
        ),
      );

  // ── filter sheet ─────────────────────────────────────────────────────────
  Future<void> _openFilterSheet() async {
    var tDate = _dateFilter;
    var tRange = _customRange;
    DateTime? tFrom = _customRange?.start;
    DateTime? tTo = _customRange?.end;
    var tEmp = _employeeFilter;
    var tActivity = _activity;
    var tRole = _roleFilter;
    var tSort = _sort;
    var tLocked = _includeLocked;

    // Snapshot the roster for the employee chips (filtering by employee never
    // refetches, so "all currently-loaded people" is the right list).
    final roster = _employees;
    final showRoleFilter = _hasSalesmen && _hasTelecallers;

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
                  const Text('Filter report',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text('Totals and counts below reflect the selected period.',
                      style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
                  const SizedBox(height: 14),
                  _label('Period'),
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
                  // "Custom" just shows two plain date fields inline — a small
                  // popup calendar each, not the full-screen range picker.
                  if (tDate == CallDateFilter.custom) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
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
                      ],
                    ),
                  ],
                  if (roster.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _label('Employee'),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ChoiceChip(
                          label: const Text('Everyone'),
                          selected: tEmp == 'all',
                          selectedColor: kGold.withValues(alpha: 0.25),
                          labelStyle: TextStyle(
                              fontSize: 12,
                              color: tEmp == 'all' ? kGoldDark : Colors.black87,
                              fontWeight: FontWeight.w600),
                          onSelected: (_) => setSheet(() => tEmp = 'all'),
                        ),
                        for (final e in roster)
                          ChoiceChip(
                            label: Text('${e['name'] ?? e['mobile']}'),
                            selected: tEmp == '${e['mobile']}',
                            selectedColor: kGold.withValues(alpha: 0.25),
                            labelStyle: TextStyle(
                                fontSize: 12,
                                color: tEmp == '${e['mobile']}'
                                    ? kGoldDark
                                    : Colors.black87,
                                fontWeight: FontWeight.w600),
                            onSelected: (_) =>
                                setSheet(() => tEmp = '${e['mobile']}'),
                          ),
                      ],
                    ),
                  ],
                  if (showRoleFilter) ...[
                    const SizedBox(height: 16),
                    _label('Role'),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _RoleFilter.values.map((r) {
                        final sel = tRole == r;
                        return ChoiceChip(
                          label: Text(_roleLabels[r]!),
                          selected: sel,
                          selectedColor: kGold.withValues(alpha: 0.25),
                          labelStyle: TextStyle(
                              fontSize: 12,
                              color: sel ? kGoldDark : Colors.black87,
                              fontWeight: FontWeight.w600),
                          onSelected: (_) => setSheet(() => tRole = r),
                        );
                      }).toList(),
                    ),
                  ],
                  const SizedBox(height: 16),
                  _label('Activity'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _Activity.values.map((f) {
                      final sel = tActivity == f;
                      return ChoiceChip(
                        label: Text(_activityLabels[f]!),
                        selected: sel,
                        selectedColor: kGold.withValues(alpha: 0.25),
                        labelStyle: TextStyle(
                            fontSize: 12,
                            color: sel ? kGoldDark : Colors.black87,
                            fontWeight: FontWeight.w600),
                        onSelected: (_) => setSheet(() => tActivity = f),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  _label('Sort by'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _Sort.values.map((s) {
                      final sel = tSort == s;
                      return ChoiceChip(
                        label: Text(_sortLabels[s]!),
                        selected: sel,
                        selectedColor: kGold.withValues(alpha: 0.25),
                        labelStyle: TextStyle(
                            fontSize: 12,
                            color: sel ? kGoldDark : Colors.black87,
                            fontWeight: FontWeight.w600),
                        onSelected: (_) => setSheet(() => tSort = s),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 6),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    activeThumbColor: kGold,
                    value: tLocked,
                    onChanged: (v) => setSheet(() => tLocked = v),
                    title: const Text('Include disabled staff',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    subtitle: Text('Off = active staff only',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => setSheet(() {
                            tDate = CallDateFilter.today;
                            tRange = null;
                            tFrom = null;
                            tTo = null;
                            tEmp = 'all';
                            tActivity = _Activity.all;
                            tRole = _RoleFilter.all;
                            tSort = _Sort.active;
                            tLocked = false;
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
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ).then((applied) {
      if (applied != true || !mounted) return;
      // Resolve the two custom fields into a range (default missing ends to today).
      if (tDate == CallDateFilter.custom) {
        final a = tFrom ?? tTo ?? DateTime.now();
        final b = tTo ?? tFrom ?? DateTime.now();
        tRange = DateTimeRange(
          start: a.isAfter(b) ? b : a,
          end: a.isAfter(b) ? a : b,
        );
      }
      final needsRefetch =
          tDate != _dateFilter || tRange != _customRange || tLocked != _includeLocked;
      setState(() {
        _dateFilter = tDate;
        _customRange = tDate == CallDateFilter.custom ? tRange : null;
        _employeeFilter = tEmp;
        _activity = tActivity;
        _roleFilter = tRole;
        _sort = tSort;
        _includeLocked = tLocked;
      });
      if (needsRefetch) _load();
    });
  }

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

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text,
            style: const TextStyle(
                fontSize: 12, fontWeight: FontWeight.w700, color: Colors.black54)),
      );
}

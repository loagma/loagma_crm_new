import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../services/api_service.dart';
import 'call_date_filter.dart';
import 'telecaller_actions.dart';
import 'telecaller_mock_data.dart';

/// Team Call History, step 1: who to look at.
///
/// Lists the working telecallers this senior is allowed to see (server-scoped
/// via TelecallerController::teamAgents — admin gets everyone, a teleadmin or
/// incharge only their own descendants), each with their call stats for the
/// selected date window. Tapping one opens that person's full history; the
/// window and outcome filters carry across so the drill-in shows the same
/// slice the card was counting.
///
/// The combined "everyone at once" view the module used to open on is still
/// reachable from the app-bar action.
class TeamCallAgentsScreen extends StatefulWidget {
  const TeamCallAgentsScreen({super.key});

  @override
  State<TeamCallAgentsScreen> createState() => _TeamCallAgentsScreenState();
}

/// How the roster is ordered. Defaults to busiest-first, which is what a
/// senior scanning for "who is and isn't working the phones" wants to see.
enum _AgentSort { calls, name, recent }

const _sortLabels = <_AgentSort, String>{
  _AgentSort.calls: 'Most calls',
  _AgentSort.name: 'Name (A-Z)',
  _AgentSort.recent: 'Recently active',
};

/// Activity filter, evaluated against the selected window's counts.
enum _ActivityFilter { all, calledToday, active, idle }

const _activityLabels = <_ActivityFilter, String>{
  _ActivityFilter.all: 'All',
  _ActivityFilter.calledToday: 'Called today',
  _ActivityFilter.active: 'Has calls',
  _ActivityFilter.idle: 'No calls',
};

class _TeamCallAgentsScreenState extends State<TeamCallAgentsScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _agents = [];
  String _query = '';

  CallDateFilter _dateFilter = CallDateFilter.all;
  DateTimeRange? _customRange;
  _AgentSort _sort = _AgentSort.calls;
  _ActivityFilter _activity = _ActivityFilter.all;
  bool _includeLocked = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// The stats window is applied server-side, so any change to the date filter
  /// or the locked-staff toggle has to refetch rather than re-filter locally.
  Future<void> _load() async {
    setState(() => _loading = true);
    final range = callDateRangeYmd(_dateFilter, _customRange);
    final agents = await ApiService.getTeamCallAgents(
      from: range.from,
      to: range.to,
      includeLocked: _includeLocked,
    );
    if (!mounted) return;
    setState(() {
      _agents = agents;
      _loading = false;
    });
  }

  bool get _hasActiveFilter =>
      _dateFilter != CallDateFilter.all ||
      _activity != _ActivityFilter.all ||
      _sort != _AgentSort.calls ||
      _includeLocked;

  int _calls(Map<String, dynamic> a) => (a['total_calls'] as num?)?.toInt() ?? 0;
  int _today(Map<String, dynamic> a) => (a['calls_today'] as num?)?.toInt() ?? 0;

  String _relative(String? iso) {
    if (iso == null || iso.isEmpty) return 'No calls yet';
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return 'No calls yet';
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} hr ago';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays} days ago';
    return fmtDay(dt);
  }

  List<Map<String, dynamic>> get _visible {
    final q = _query.trim().toLowerCase();
    final list = _agents.where((a) {
      final matchesQuery = q.isEmpty ||
          '${a['name'] ?? ''}'.toLowerCase().contains(q) ||
          '${a['mobile'] ?? ''}'.contains(q) ||
          '${a['city'] ?? ''}'.toLowerCase().contains(q);
      final matchesActivity = switch (_activity) {
        _ActivityFilter.all => true,
        _ActivityFilter.calledToday => _today(a) > 0,
        _ActivityFilter.active => _calls(a) > 0,
        _ActivityFilter.idle => _calls(a) == 0,
      };
      return matchesQuery && matchesActivity;
    }).toList();

    switch (_sort) {
      case _AgentSort.calls:
        // Name breaks ties so the order is stable across refreshes rather than
        // shuffling every agent who currently has zero calls.
        list.sort((a, b) {
          final byCalls = _calls(b).compareTo(_calls(a));
          return byCalls != 0 ? byCalls : '${a['name']}'.compareTo('${b['name']}');
        });
      case _AgentSort.name:
        list.sort((a, b) =>
            '${a['name']}'.toLowerCase().compareTo('${b['name']}'.toLowerCase()));
      case _AgentSort.recent:
        list.sort((a, b) {
          final at = DateTime.tryParse('${a['last_called_at'] ?? ''}');
          final bt = DateTime.tryParse('${b['last_called_at'] ?? ''}');
          if (at == null && bt == null) return '${a['name']}'.compareTo('${b['name']}');
          if (at == null) return 1; // never-called sinks to the bottom
          if (bt == null) return -1;
          return bt.compareTo(at);
        });
    }
    return list;
  }

  void _openAgent(Map<String, dynamic> agent) {
    context.push('/team-call-history/agent', extra: {
      'mobile': '${agent['mobile'] ?? ''}',
      'name': '${agent['name'] ?? ''}',
      'dateFilter': _dateFilter,
      'customRange': _customRange,
    });
  }

  Future<void> _openFilterSheet() async {
    var tempDate = _dateFilter;
    var tempRange = _customRange;
    var tempSort = _sort;
    var tempActivity = _activity;
    var tempLocked = _includeLocked;

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Filter telecallers',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text('Call counts below are for the selected period.',
                      style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
                  const SizedBox(height: 14),
                  _sheetLabel('Period'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: CallDateFilter.values.map((f) {
                      final selected = tempDate == f;
                      return ChoiceChip(
                        label: Text(callDateFilterLabels[f]!),
                        selected: selected,
                        selectedColor: kGold.withValues(alpha: 0.25),
                        labelStyle: TextStyle(
                            fontSize: 12,
                            color: selected ? kGoldDark : Colors.black87,
                            fontWeight: FontWeight.w600),
                        onSelected: (_) async {
                          if (f == CallDateFilter.custom) {
                            final now = DateTime.now();
                            final picked = await showDateRangePicker(
                              context: ctx,
                              firstDate: DateTime(now.year - 2),
                              lastDate: now,
                              initialDateRange: tempRange,
                            );
                            if (picked != null) {
                              setSheetState(() {
                                tempDate = f;
                                tempRange = picked;
                              });
                            }
                          } else {
                            setSheetState(() => tempDate = f);
                          }
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  _sheetLabel('Activity'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _ActivityFilter.values.map((f) {
                      final selected = tempActivity == f;
                      return ChoiceChip(
                        label: Text(_activityLabels[f]!),
                        selected: selected,
                        selectedColor: kGold.withValues(alpha: 0.25),
                        labelStyle: TextStyle(
                            fontSize: 12,
                            color: selected ? kGoldDark : Colors.black87,
                            fontWeight: FontWeight.w600),
                        onSelected: (_) => setSheetState(() => tempActivity = f),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  _sheetLabel('Sort by'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _AgentSort.values.map((s) {
                      final selected = tempSort == s;
                      return ChoiceChip(
                        label: Text(_sortLabels[s]!),
                        selected: selected,
                        selectedColor: kGold.withValues(alpha: 0.25),
                        labelStyle: TextStyle(
                            fontSize: 12,
                            color: selected ? kGoldDark : Colors.black87,
                            fontWeight: FontWeight.w600),
                        onSelected: (_) => setSheetState(() => tempSort = s),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 6),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    activeThumbColor: kGold,
                    value: tempLocked,
                    onChanged: (v) => setSheetState(() => tempLocked = v),
                    title: const Text('Include locked accounts',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    subtitle: Text('Off = working telecallers only',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => setSheetState(() {
                            tempDate = CallDateFilter.all;
                            tempRange = null;
                            tempSort = _AgentSort.calls;
                            tempActivity = _ActivityFilter.all;
                            tempLocked = false;
                          }),
                          child: const Text('Reset'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                              backgroundColor: kGold, foregroundColor: Colors.white),
                          onPressed: () {
                            Navigator.pop(ctx, true);
                          },
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
      final needsRefetch = tempDate != _dateFilter ||
          tempRange != _customRange ||
          tempLocked != _includeLocked;
      setState(() {
        _dateFilter = tempDate;
        _customRange = tempDate == CallDateFilter.custom ? tempRange : null;
        _sort = tempSort;
        _activity = tempActivity;
        _includeLocked = tempLocked;
      });
      // Sort/activity are local; only the server-side window needs a round-trip.
      if (needsRefetch) _load();
    });
  }

  Widget _sheetLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text,
            style: const TextStyle(
                fontSize: 12, fontWeight: FontWeight.w700, color: Colors.black54)),
      );

  @override
  Widget build(BuildContext context) {
    final items = _visible;
    final totalCalls = _agents.fold<int>(0, (sum, a) => sum + _calls(a));
    final activeToday = _agents.where((a) => _today(a) > 0).length;

    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        title: const Text('Team Call History'),
        backgroundColor: kGold,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.groups_rounded),
            tooltip: 'All calls together',
            onPressed: () => context.push('/team-call-history/all'),
          ),
          IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: _load),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    onChanged: (v) => setState(() => _query = v),
                    decoration: InputDecoration(
                      hintText: 'Search telecaller by name, number or city…',
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
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Row(
              children: [
                Expanded(child: _summaryTile('Telecallers', '${_agents.length}')),
                const SizedBox(width: 8),
                Expanded(child: _summaryTile('Calls', '$totalCalls')),
                const SizedBox(width: 8),
                Expanded(child: _summaryTile('Active today', '$activeToday')),
              ],
            ),
          ),
          if (_hasActiveFilter)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (_dateFilter != CallDateFilter.all)
                      _activeFilterChip(
                        callDateChipLabel(_dateFilter, _customRange),
                        () {
                          setState(() {
                            _dateFilter = CallDateFilter.all;
                            _customRange = null;
                          });
                          _load();
                        },
                      ),
                    if (_activity != _ActivityFilter.all)
                      _activeFilterChip(_activityLabels[_activity]!,
                          () => setState(() => _activity = _ActivityFilter.all)),
                    if (_sort != _AgentSort.calls)
                      _activeFilterChip(_sortLabels[_sort]!,
                          () => setState(() => _sort = _AgentSort.calls)),
                    if (_includeLocked)
                      _activeFilterChip('Incl. locked', () {
                        setState(() => _includeLocked = false);
                        _load();
                      }),
                  ],
                ),
              ),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: kGold))
                : items.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            _query.isNotEmpty
                                ? 'No telecaller matches "$_query"'
                                : _agents.isEmpty
                                    ? 'No telecallers assigned to you yet'
                                    : 'No telecaller matches the selected filters',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey.shade500),
                          ),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                          itemCount: items.length,
                          itemBuilder: (_, i) => _agentCard(items[i]),
                        ),
                      ),
          ),
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

  Widget _activeFilterChip(String label, VoidCallback onClear) => Container(
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

  Widget _agentCard(Map<String, dynamic> a) {
    final name = '${a['name'] ?? ''}';
    final mobile = '${a['mobile'] ?? ''}';
    final calls = _calls(a);
    final today = _today(a);
    final connected = (a['connected_calls'] as num?)?.toInt() ?? 0;
    final recordings = (a['recordings'] as num?)?.toInt() ?? 0;
    final talkTime = (a['talk_time_seconds'] as num?)?.toInt() ?? 0;
    final locked = a['is_locked'] == true;
    final avatar = avatarColorFor(name.isEmpty ? mobile : name);

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
        onTap: () => _openAgent(a),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 42,
                width: 42,
                decoration:
                    BoxDecoration(color: avatar.withValues(alpha: 0.16), shape: BoxShape.circle),
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
                        if (today > 0)
                          Container(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                                color: const Color(0xFF43A047).withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(6)),
                            child: Text('$today today',
                                style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF43A047))),
                          ),
                        if (locked) ...[
                          const SizedBox(width: 6),
                          Icon(Icons.lock_outline_rounded,
                              size: 14, color: Colors.grey.shade500),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Icon(Icons.phone_rounded, size: 11, color: Colors.grey.shade400),
                        const SizedBox(width: 3),
                        Text(mobile,
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                        if ('${a['city'] ?? ''}'.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Icon(Icons.place_outlined, size: 11, color: Colors.grey.shade400),
                          const SizedBox(width: 2),
                          Expanded(
                            child: Text('${a['city']}',
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 11, color: Colors.grey.shade500)),
                          ),
                        ] else
                          const Spacer(),
                      ],
                    ),
                    const SizedBox(height: 7),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _statChip(Icons.call_rounded, '$calls calls',
                            calls > 0 ? kGoldDark : Colors.grey.shade500),
                        if (connected > 0)
                          _statChip(Icons.check_circle_outline_rounded,
                              '$connected answered', const Color(0xFF43A047)),
                        if (talkTime > 0)
                          _statChip(Icons.schedule_rounded,
                              formatCallDuration(talkTime), Colors.grey.shade600),
                        if (recordings > 0)
                          _statChip(Icons.play_circle_outline_rounded,
                              '$recordings rec', const Color(0xFF1E88E5)),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text('Last call: ${_relative('${a['last_called_at'] ?? ''}')}',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
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
}

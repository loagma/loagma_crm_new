import 'package:flutter/material.dart';

import '../../services/api_service.dart';
import '../../widgets/call_recording_player.dart';
import 'telecaller_actions.dart';
import 'telecaller_mock_data.dart';

/// Call History (live data). The telecaller's recent calls with outcome, the
/// note from last time and when — so they see the last conversation before
/// dialling again. Searchable; tap to re-call.
class TelecallerCallHistoryScreen extends StatefulWidget {
  const TelecallerCallHistoryScreen({super.key});

  @override
  State<TelecallerCallHistoryScreen> createState() => _TelecallerCallHistoryScreenState();
}

/// Date filter presets for call history.
enum _DateFilter { all, today, yesterday, week, month, custom }

const _dateFilterLabels = <_DateFilter, String>{
  _DateFilter.all: 'All time',
  _DateFilter.today: 'Today',
  _DateFilter.yesterday: 'Yesterday',
  _DateFilter.week: 'Last 7 days',
  _DateFilter.month: 'Last 30 days',
  _DateFilter.custom: 'Custom range',
};

class _TelecallerCallHistoryScreenState extends State<TelecallerCallHistoryScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _items = [];
  String _query = '';
  _DateFilter _dateFilter = _DateFilter.all;
  DateTimeRange? _customRange;
  String? _outcomeFilter;
  /// null = all, 'knowlarity' = cloud calls, 'manual' = manually-logged calls.
  String? _sourceFilter;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final items = await ApiService.getTelecallerCallHistory();
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  String _relative(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt.toLocal());
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} hr ago';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays} days ago';
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}';
  }

  bool get _hasActiveFilter => _dateFilter != _DateFilter.all || _outcomeFilter != null || _sourceFilter != null;

  bool _matchesDate(String? iso) {
    if (_dateFilter == _DateFilter.all) return true;
    final dt = iso == null || iso.isEmpty ? null : DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(dt.year, dt.month, dt.day);
    switch (_dateFilter) {
      case _DateFilter.today:
        return day == today;
      case _DateFilter.yesterday:
        return day == today.subtract(const Duration(days: 1));
      case _DateFilter.week:
        return !day.isBefore(today.subtract(const Duration(days: 6)));
      case _DateFilter.month:
        return !day.isBefore(today.subtract(const Duration(days: 29)));
      case _DateFilter.custom:
        if (_customRange == null) return true;
        final start = DateTime(_customRange!.start.year, _customRange!.start.month, _customRange!.start.day);
        final end = DateTime(_customRange!.end.year, _customRange!.end.month, _customRange!.end.day);
        return !day.isBefore(start) && !day.isAfter(end);
      case _DateFilter.all:
        return true;
    }
  }

  Future<void> _openFilterSheet() async {
    _DateFilter tempDate = _dateFilter;
    DateTimeRange? tempRange = _customRange;
    String? tempOutcome = _outcomeFilter;

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Filter calls', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 12),
                    const Text('Date', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.black54)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _DateFilter.values.map((f) {
                        final selected = tempDate == f;
                        return ChoiceChip(
                          label: Text(_dateFilterLabels[f]!),
                          selected: selected,
                          selectedColor: kGold.withValues(alpha: 0.25),
                          labelStyle: TextStyle(fontSize: 12, color: selected ? kGoldDark : Colors.black87, fontWeight: FontWeight.w600),
                          onSelected: (_) async {
                            if (f == _DateFilter.custom) {
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
                    const Text('Outcome', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.black54)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ChoiceChip(
                          label: const Text('All'),
                          selected: tempOutcome == null,
                          selectedColor: kGold.withValues(alpha: 0.25),
                          labelStyle: TextStyle(fontSize: 12, color: tempOutcome == null ? kGoldDark : Colors.black87, fontWeight: FontWeight.w600),
                          onSelected: (_) => setSheetState(() => tempOutcome = null),
                        ),
                        ...kOutcomeLabels.entries.map((e) {
                          final selected = tempOutcome == e.key;
                          final color = kOutcomeColors[e.key] ?? Colors.grey;
                          return ChoiceChip(
                            label: Text(e.value),
                            selected: selected,
                            selectedColor: color.withValues(alpha: 0.2),
                            labelStyle: TextStyle(fontSize: 12, color: selected ? color : Colors.black87, fontWeight: FontWeight.w600),
                            onSelected: (_) => setSheetState(() => tempOutcome = e.key),
                          );
                        }),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () {
                              setSheetState(() {
                                tempDate = _DateFilter.all;
                                tempRange = null;
                                tempOutcome = null;
                              });
                            },
                            child: const Text('Reset'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(backgroundColor: kGold, foregroundColor: Colors.white),
                            onPressed: () {
                              setState(() {
                                _dateFilter = tempDate;
                                _customRange = tempDate == _DateFilter.custom ? tempRange : null;
                                _outcomeFilter = tempOutcome;
                              });
                              Navigator.pop(ctx);
                            },
                            child: const Text('Apply'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final items = _items.where((h) {
      final matchesQuery = q.isEmpty ||
          '${h['name'] ?? ''}'.toLowerCase().contains(q) ||
          '${h['phone'] ?? ''}'.contains(q);
      final matchesOutcome = _outcomeFilter == null || '${h['outcome'] ?? ''}' == _outcomeFilter;
      final matchesDate = _matchesDate('${h['called_at'] ?? ''}');
      final source = '${h['source'] ?? 'manual'}';
      final matchesSource = _sourceFilter == null || source == _sourceFilter;
      return matchesQuery && matchesOutcome && matchesDate && matchesSource;
    }).toList();
    final cloudCount = _items.where((h) => h['source'] == 'knowlarity').length;
    final manualCount = _items.length - cloudCount;

    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        title: const Text('Call History'),
        backgroundColor: kGold,
        foregroundColor: Colors.white,
        actions: [IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: _load)],
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
                      hintText: 'Search by name or number…',
                      prefixIcon: const Icon(Icons.search_rounded, color: kGoldDark),
                      isDense: true,
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kGold)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  decoration: BoxDecoration(
                    color: _hasActiveFilter ? kGold.withValues(alpha: 0.15) : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _hasActiveFilter ? kGold : Colors.grey.shade200),
                  ),
                  child: IconButton(
                    icon: Icon(Icons.filter_list_rounded, color: _hasActiveFilter ? kGoldDark : Colors.grey.shade600),
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
                Expanded(child: _typeChip('All', null, _items.length)),
                const SizedBox(width: 8),
                Expanded(child: _typeChip('Call', 'manual', manualCount, icon: Icons.call_rounded)),
                const SizedBox(width: 8),
                Expanded(child: _typeChip('Cloud Call', 'knowlarity', cloudCount, icon: Icons.cloud_queue_rounded)),
              ],
            ),
          ),
          if (_hasActiveFilter)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (_dateFilter != _DateFilter.all)
                      _activeFilterChip(
                        _dateFilter == _DateFilter.custom && _customRange != null
                            ? '${_fmtDate(_customRange!.start)} - ${_fmtDate(_customRange!.end)}'
                            : _dateFilterLabels[_dateFilter]!,
                        () => setState(() {
                          _dateFilter = _DateFilter.all;
                          _customRange = null;
                        }),
                      ),
                    if (_outcomeFilter != null)
                      _activeFilterChip(
                        kOutcomeLabels[_outcomeFilter] ?? _outcomeFilter!,
                        () => setState(() => _outcomeFilter = null),
                      ),
                  ],
                ),
              ),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: kGold))
                : items.isEmpty
                    ? Center(
                        child: Text(
                            _query.isNotEmpty
                                ? 'No calls match "$_query"'
                                : _hasActiveFilter
                                    ? 'No calls match the selected filters'
                                    : 'No calls logged yet',
                            style: TextStyle(color: Colors.grey.shade500)))
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 6, 12, 24),
                          itemCount: items.length,
                          itemBuilder: (_, i) => _row(items[i]),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  String _fmtDate(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  /// Quick call-type filter: All / Call (manual) / Cloud Call (Knowlarity).
  Widget _typeChip(String label, String? value, int count, {IconData? icon}) {
    final selected = _sourceFilter == value;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => setState(() => _sourceFilter = value),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: selected ? kGold.withValues(alpha: 0.16) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: selected ? kGold : Colors.grey.shade200),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 13, color: selected ? kGoldDark : Colors.grey.shade600),
                  const SizedBox(width: 4),
                ],
                Text(label,
                    style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: selected ? kGoldDark : Colors.black87)),
              ],
            ),
            Text('$count', style: TextStyle(fontSize: 10, color: selected ? kGoldDark : Colors.grey.shade500)),
          ],
        ),
      ),
    );
  }

  Widget _activeFilterChip(String label, VoidCallback onClear) {
    return Container(
      padding: const EdgeInsets.only(left: 10, right: 4, top: 3, bottom: 3),
      decoration: BoxDecoration(
        color: kGold.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kGold),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: kGoldDark)),
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
  }

  Widget _row(Map<String, dynamic> h) {
    final outcome = '${h['outcome'] ?? ''}';
    final color = kOutcomeColors[outcome] ?? Colors.grey;
    final phone = '${h['phone'] ?? ''}';
    final isCloud = h['source'] == 'knowlarity';
    final duration = (h['duration_seconds'] as num?)?.toInt() ?? 0;
    final hasRecording = '${h['recording_url'] ?? ''}'.isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFEEEEEE)),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 3))],
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _showDetails(h),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 40, width: 40,
                decoration: BoxDecoration(color: color.withValues(alpha: 0.14), shape: BoxShape.circle),
                child: Icon(isCloud ? Icons.cloud_queue_rounded : Icons.history_rounded, color: color, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text('${h['name'] ?? 'Unknown'}', style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700))),
                        Text(_relative('${h['called_at'] ?? ''}'), style: TextStyle(fontSize: 10.5, color: Colors.grey.shade500)),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
                          child: Text(kOutcomeLabels[outcome] ?? outcome,
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color)),
                        ),
                        const SizedBox(width: 8),
                        Expanded(child: Text(phone, style: TextStyle(fontSize: 11, color: Colors.grey.shade500))),
                        if (duration > 0) ...[
                          Icon(Icons.schedule_rounded, size: 11, color: Colors.grey.shade400),
                          const SizedBox(width: 2),
                          Text(formatCallDuration(duration), style: TextStyle(fontSize: 10.5, color: Colors.grey.shade500)),
                        ],
                        if (hasRecording) ...[
                          const SizedBox(width: 6),
                          Icon(Icons.play_circle_outline_rounded, size: 14, color: kGoldDark),
                        ],
                      ],
                    ),
                    if ((h['notes'] ?? '').toString().isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Text('${h['notes']}', style: const TextStyle(fontSize: 12, color: Colors.black54)),
                    ],
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.call_rounded, color: Color(0xFF43A047)),
                tooltip: 'Call again',
                onPressed: () => launchPhoneCall(phone),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Full call details bottom sheet - everything Knowlarity's own call log
  /// reports for this call (source, direction, duration, SR number, call
  /// UUID, recording), not just the outcome shown in the row.
  void _showDetails(Map<String, dynamic> h) {
    final outcome = '${h['outcome'] ?? ''}';
    final color = kOutcomeColors[outcome] ?? Colors.grey;
    final duration = (h['duration_seconds'] as num?)?.toInt() ?? 0;
    final recordingUrl = '${h['recording_url'] ?? ''}';
    final isCloud = h['source'] == 'knowlarity';

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('${h['name'] ?? 'Unknown'}',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
                    child: Text(kOutcomeLabels[outcome] ?? outcome,
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _detailRow('Phone', '${h['phone'] ?? '-'}'),
              _detailRow('Called at', '${h['called_at'] ?? '-'}'),
              _detailRow('Duration', duration > 0 ? formatCallDuration(duration) : '-'),
              _detailRow('Source', isCloud ? 'Cloud call (Knowlarity)' : 'Manual'),
              if (isCloud) ...[
                _detailRow('Direction', '${h['direction'] ?? '-'}'),
                _detailRow('SR Number', '${h['sr_number'] ?? '-'}'),
                _detailRow('Call UUID', '${h['call_uuid'] ?? '-'}'),
              ],
              if ((h['notes'] ?? '').toString().isNotEmpty) _detailRow('Notes', '${h['notes']}'),
              if (recordingUrl.isNotEmpty) ...[
                const SizedBox(height: 14),
                CallRecordingPlayer(url: recordingUrl, accentColor: kGoldDark),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade500, fontWeight: FontWeight.w600)),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 12.5, color: Colors.black87))),
        ],
      ),
    );
  }
}

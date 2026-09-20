import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../services/api_service.dart';
import '../../services/user_service.dart';
import 'telecaller_mock_data.dart';
import 'telecaller_report_customer_screen.dart';

enum _RangeFilter { today, yesterday, thisMonth, custom }

/// New Team/Self Report: a plain table of every customer on the beat-plan
/// route within a date range, with call counts and whether it ended in an
/// order. Tapping a row drills into [TelecallerReportCustomerScreen] for the
/// full visit + call + order detail.
///
/// [selfMode] true → the logged-in telecaller's own report, no picker.
/// [selfMode] false → a senior's Team Report: pick a telecaller first, same
/// roster the Team Call History screen uses (getTeamCallAgents).
class TelecallerDailyReportScreen extends StatefulWidget {
  final bool selfMode;

  const TelecallerDailyReportScreen({super.key, required this.selfMode});

  @override
  State<TelecallerDailyReportScreen> createState() => _TelecallerDailyReportScreenState();
}

class _TelecallerDailyReportScreenState extends State<TelecallerDailyReportScreen> {
  _RangeFilter _filter = _RangeFilter.today;
  DateTimeRange? _customRange;
  bool _loading = true;
  bool _loadingAgents = false;
  List<Map<String, dynamic>> _rows = [];
  List<Map<String, dynamic>> _agents = [];
  String? _selectedMobile;
  String? _selectedName;
  String? _error;
  String _search = '';
  final _searchCtrl = TextEditingController();

  String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  ({String from, String to}) get _range {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    switch (_filter) {
      case _RangeFilter.today:
        return (from: _ymd(today), to: _ymd(today));
      case _RangeFilter.yesterday:
        final y = today.subtract(const Duration(days: 1));
        return (from: _ymd(y), to: _ymd(y));
      case _RangeFilter.thisMonth:
        return (from: _ymd(DateTime(today.year, today.month, 1)), to: _ymd(today));
      case _RangeFilter.custom:
        final r = _customRange;
        return r == null ? (from: _ymd(today), to: _ymd(today)) : (from: _ymd(r.start), to: _ymd(r.end));
    }
  }

  String get _rangeLabel {
    switch (_filter) {
      case _RangeFilter.today: return 'Today';
      case _RangeFilter.yesterday: return 'Yesterday';
      case _RangeFilter.thisMonth: return 'This Month';
      case _RangeFilter.custom:
        final r = _range;
        return r.from == r.to ? r.from : '${r.from} to ${r.to}';
    }
  }

  List<Map<String, dynamic>> get _filteredRows {
    if (_search.trim().isEmpty) return _rows;
    final q = _search.trim().toLowerCase();
    return _rows.where((r) {
      return '${r['name'] ?? ''}'.toLowerCase().contains(q) ||
          '${r['phone'] ?? ''}'.toLowerCase().contains(q);
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    if (widget.selfMode) {
      _load();
    } else {
      _loadAgents();
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAgents() async {
    setState(() => _loadingAgents = true);
    final agents = await ApiService.getTeamCallAgents();
    if (!mounted) return;
    setState(() {
      _agents = agents;
      _loadingAgents = false;
      if (agents.isNotEmpty) {
        _selectedMobile = '${agents.first['mobile']}';
        _selectedName = '${agents.first['name'] ?? ''}';
      }
    });
    if (_selectedMobile != null) _load();
  }

  Future<void> _load() async {
    if (!widget.selfMode && _selectedMobile == null) return;
    setState(() { _loading = true; _error = null; });
    final r = _range;
    final res = await ApiService.getTelecallerReportSummary(
      from: r.from,
      to: r.to,
      telecallerId: widget.selfMode ? UserService.currentMobile : _selectedMobile,
    );
    if (!mounted) return;
    if (res != null && res['success'] == true) {
      final data = (res['data'] as Map?)?.cast<String, dynamic>() ?? {};
      setState(() {
        _rows = ((data['rows'] as List?) ?? []).cast<Map>().map((e) => e.cast<String, dynamic>()).toList();
        _loading = false;
      });
    } else {
      setState(() { _rows = []; _loading = false; _error = 'Could not load the report — pull to retry.'; });
    }
  }

  void _setFilter(_RangeFilter f) {
    setState(() => _filter = f);
    _load();
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: _customRange,
      firstDate: DateTime(2024, 1, 1),
      lastDate: now,
    );
    if (picked == null) return;
    setState(() { _customRange = picked; _filter = _RangeFilter.custom; });
    _load();
  }

  void _openCustomer(Map<String, dynamic> row) {
    final r = _range;
    context.push('/telecaller-report/customer', extra: {
      'accountId':    '${row['account_id']}',
      'accountType':  '${row['account_type'] ?? 'lead'}',
      'name':         '${row['name'] ?? 'Customer'}',
      'from':         r.from,
      'to':           r.to,
      'telecallerId': widget.selfMode ? UserService.currentMobile : _selectedMobile,
    });
  }

  Widget _filterChip(String label, _RangeFilter value) {
    final selected = _filter == value;
    return ChoiceChip(
      label: Text(label, style: TextStyle(fontSize: 12, color: selected ? Colors.white : Colors.black87)),
      selected: selected,
      selectedColor: kGold,
      backgroundColor: const Color(0xFFF0F0F0),
      onSelected: (_) => _setFilter(value),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rows = _filteredRows;
    final totalCalls    = rows.fold<int>(0, (s, r) => s + ((r['calls_total'] as num?)?.toInt() ?? 0));
    final totalAnswered = rows.fold<int>(0, (s, r) => s + ((r['answered'] as num?)?.toInt() ?? 0));
    final totalOrders   = rows.where((r) => r['order_given'] == true).length;

    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kGold,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(widget.selfMode ? 'Self Report' : 'Team Report',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(icon: const Icon(Icons.refresh_rounded, color: Colors.white), onPressed: _load),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!widget.selfMode) ...[
                  _loadingAgents
                      ? const LinearProgressIndicator(minHeight: 2)
                      : DropdownButtonFormField<String>(
                          initialValue: _selectedMobile,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Telecaller',
                            border: OutlineInputBorder(),
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          ),
                          items: _agents
                              .map((a) => DropdownMenuItem(
                                    value: '${a['mobile']}',
                                    child: Text('${a['name'] ?? a['mobile']}', overflow: TextOverflow.ellipsis),
                                  ))
                              .toList(),
                          onChanged: (v) {
                            if (v == null) return;
                            final agent = _agents.firstWhere((a) => '${a['mobile']}' == v, orElse: () => {});
                            setState(() { _selectedMobile = v; _selectedName = '${agent['name'] ?? ''}'; });
                            _load();
                          },
                        ),
                  const SizedBox(height: 10),
                ],
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _filterChip('Today', _RangeFilter.today),
                      const SizedBox(width: 8),
                      _filterChip('Yesterday', _RangeFilter.yesterday),
                      const SizedBox(width: 8),
                      _filterChip('This Month', _RangeFilter.thisMonth),
                      const SizedBox(width: 8),
                      ActionChip(
                        avatar: const Icon(Icons.date_range_rounded, size: 16),
                        label: Text(_filter == _RangeFilter.custom ? _rangeLabel : 'Custom',
                            style: const TextStyle(fontSize: 12)),
                        backgroundColor: _filter == _RangeFilter.custom ? kGold.withValues(alpha: 0.18) : const Color(0xFFF0F0F0),
                        onPressed: _pickCustomRange,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    hintText: 'Search customer name or phone',
                    prefixIcon: const Icon(Icons.search_rounded, size: 20),
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    suffixIcon: _search.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close_rounded, size: 18),
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() => _search = '');
                            },
                          ),
                  ),
                  onChanged: (v) => setState(() => _search = v),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.event_rounded, size: 15, color: Colors.black54),
                    const SizedBox(width: 6),
                    Expanded(child: Text(_rangeLabel, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5))),
                    Text('${rows.length} customers  •  $totalCalls calls  •  $totalAnswered answered  •  $totalOrders orders',
                        style: const TextStyle(fontSize: 11, color: Colors.black54)),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: kGold))
                : _error != null
                    ? Center(child: Text(_error!, style: const TextStyle(color: Colors.black54)))
                    : rows.isEmpty
                        ? Center(
                            child: Text(
                              _rows.isNotEmpty
                                  ? 'No customer matches "$_search".'
                                  : (widget.selfMode
                                      ? 'No customers on your route for this period.'
                                      : (_selectedMobile == null ? 'Pick a telecaller.' : 'No customers on ${_selectedName ?? "their"} route for this period.')),
                              style: const TextStyle(color: Colors.black54),
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: SingleChildScrollView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.all(12),
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: DataTable(
                                  showCheckboxColumn: false,
                                  headingRowColor: WidgetStateProperty.all(const Color(0xFFF3ECD9)),
                                  columnSpacing: 20,
                                  columns: const [
                                    DataColumn(label: Text('Customer', style: TextStyle(fontWeight: FontWeight.w700))),
                                    DataColumn(label: Text('Calls', style: TextStyle(fontWeight: FontWeight.w700))),
                                    DataColumn(label: Text('Ans.', style: TextStyle(fontWeight: FontWeight.w700))),
                                    DataColumn(label: Text('Not Ans.', style: TextStyle(fontWeight: FontWeight.w700))),
                                    DataColumn(label: Text('Visited', style: TextStyle(fontWeight: FontWeight.w700))),
                                    DataColumn(label: Text('Order', style: TextStyle(fontWeight: FontWeight.w700))),
                                  ],
                                  rows: rows.map((r) {
                                    final orderGiven = r['order_given'] == true;
                                    final visited = r['visited'] == true;
                                    return DataRow(
                                      onSelectChanged: (_) => _openCustomer(r),
                                      cells: [
                                        DataCell(SizedBox(
                                          width: 140,
                                          child: Text('${r['name'] ?? 'Unknown'}',
                                              maxLines: 1, overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5)),
                                        )),
                                        DataCell(Text('${r['calls_total'] ?? 0}')),
                                        DataCell(Text('${r['answered'] ?? 0}', style: const TextStyle(color: Color(0xFF43A047), fontWeight: FontWeight.w600))),
                                        DataCell(Text('${r['not_answered'] ?? 0}', style: const TextStyle(color: Color(0xFFE53935)))),
                                        DataCell(Icon(visited ? Icons.check_circle_rounded : Icons.remove_circle_outline_rounded,
                                            size: 18, color: visited ? const Color(0xFF43A047) : Colors.black26)),
                                        DataCell(orderGiven
                                            ? const Icon(Icons.check_circle_rounded, size: 18, color: Color(0xFF2E7D32))
                                            : const Icon(Icons.remove_circle_outline_rounded, size: 18, color: Colors.black26)),
                                      ],
                                    );
                                  }).toList(),
                                ),
                              ),
                            ),
                          ),
          ),
        ],
      ),
    );
  }
}

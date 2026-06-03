import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/api_service.dart';
import '../../services/user_service.dart';

// Flow:
//  1. getAreaAssign(mobile)  → salesman's area IDs
//  2. getLeadAccounts(areaIds: [...]) → all accounts whose areaId is in that list
//  3. Group client-side by account['pincode']
// No dependency on area_crm having pincodes populated.

class AllottedCustomerAccountsScreen extends StatefulWidget {
  const AllottedCustomerAccountsScreen({super.key});

  @override
  State<AllottedCustomerAccountsScreen> createState() =>
      _AllottedCustomerAccountsScreenState();
}

class _AllottedCustomerAccountsScreenState
    extends State<AllottedCustomerAccountsScreen> {
  static const _gold = Color(0xFFD7BE69);

  final _searchCtrl = TextEditingController();
  String _query     = '';

  bool   _loading       = true;
  bool   _actionLoading = false;
  String _error         = '';

  // {pincode, accounts: [...]}
  List<Map<String, dynamic>> _groups = [];

  // {pincode: {existing, assign, remaining}} — from beat-plan/stats API
  Map<String, Map<String, int>> _stats = {};

  // {accountId: beatPlan} — from beat-plan/my-plans API
  Map<String, Map<String, dynamic>> _beatPlans = {};

  final Set<String> _expanded = {};
  final Set<String> _selected = {}; // selected accountCode values

  // ── Load ─────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = ''; _selected.clear(); });

    final mobile = UserService.currentMobile ?? '';
    if (mobile.isEmpty) {
      setState(() { _loading = false; _error = 'Not logged in'; });
      return;
    }

    try {
      // Step 1 — get salesman's assigned area IDs from area_assign_crm
      final assignRes  = await ApiService.getAreaAssign(mobile);
      final assignData = assignRes?['data'];

      final areaIds = <int>[];
      if (assignData is Map) {
        final ids = assignData['area_ids'];
        if (ids is List) {
          for (final id in ids) {
            final n = int.tryParse(id.toString());
            if (n != null) areaIds.add(n);
          }
        }
      }

      if (areaIds.isEmpty) {
        setState(() { _loading = false; _groups = []; });
        return;
      }

      // Step 2 — get pincodes from those areas (parallel), may be empty — that's ok
      final areaResults = await Future.wait(areaIds.map(ApiService.getArea));
      final pincodes = <String>[];
      for (final area in areaResults) {
        if (area == null) continue;
        final raw = area['pincodes'];
        if (raw is List) pincodes.addAll(raw.map((p) => p.toString()));
      }

      // Step 3 — ONE request: match by areaId OR by pincode (OR logic in backend)
      //   Handles accounts with areaId set AND older accounts with only pincode set
      final result = await ApiService.getLeadAccounts(
        areaIds: areaIds,
        pincodes: pincodes, // empty list is fine — backend ignores it
        perPage: 1000,
      );
      final raw = result['data'];
      final allAccounts = raw is List
          ? raw.map((e) => Map<String, dynamic>.from(e as Map)).toList()
          : <Map<String, dynamic>>[];

      // Step 3 — group client-side by pincode
      // Pre-seed with ALL pincodes from areas so empty ones still appear
      final groupMap = <String, List<Map<String, dynamic>>>{
        for (final p in pincodes) p: [],
      };
      for (final a in allAccounts) {
        final pin = ((a['pincode'] as String?) ?? '').trim();
        final key = pin.isEmpty ? 'Unknown' : pin;
        groupMap.putIfAbsent(key, () => []).add(a);
      }

      final groups = groupMap.entries.map((e) => {
        'pincode':  e.key,
        'accounts': e.value,
      }).toList();

      // Sort: most accounts first, then alphabetically by pincode
      groups.sort((a, b) {
        final diff = (b['accounts'] as List).length
            .compareTo((a['accounts'] as List).length);
        return diff != 0 ? diff : (a['pincode'] as String).compareTo(b['pincode'] as String);
      });

      // Auto-expand first pincode
      _expanded.clear();
      if (groups.isNotEmpty) _expanded.add(groups[0]['pincode'] as String);

      // Step 4 — fetch beat plan stats + my-plans in parallel
      final futures = await Future.wait([
        ApiService.getBeatPlanStats(areaIds: areaIds, pincodes: pincodes),
        ApiService.getMyBeatPlans(),
      ]);

      final statsRaw = futures[0]['data'] as Map?;
      final stats = <String, Map<String, int>>{};
      if (statsRaw != null) {
        statsRaw.forEach((pin, s) {
          final m = s as Map<String, dynamic>;
          stats[pin.toString()] = {
            'existing':  (m['existing']  as int?) ?? 0,
            'assign':    (m['assign']    as int?) ?? 0,
            'remaining': (m['remaining'] as int?) ?? 0,
          };
        });
      }

      final plansRaw = futures[1]['data'] as List? ?? [];
      final beatPlans = <String, Map<String, dynamic>>{};
      for (final p in plansRaw) {
        final m = Map<String, dynamic>.from(p as Map);
        beatPlans[m['account_id'] as String] = m;
      }

      setState(() {
        _groups    = groups;
        _stats     = stats;
        _beatPlans = beatPlans;
        _loading   = false;
      });
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = 'Failed to load data. Tap refresh to retry.'; });
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────────

  int get _totalAccounts =>
      _groups.fold(0, (s, g) => s + (g['accounts'] as List).length);

  List<Map<String, dynamic>> _filtered(List accounts) {
    final list = accounts.cast<Map<String, dynamic>>();
    if (_query.isEmpty) return list;
    final q = _query.toLowerCase();
    return list.where((a) =>
        (a['businessName']  as String? ?? '').toLowerCase().contains(q) ||
        (a['contactNumber'] as String? ?? '').contains(q) ||
        (a['accountCode']   as String? ?? '').contains(q) ||
        (a['personName']    as String? ?? '').toLowerCase().contains(q),
    ).toList();
  }

  void _toggleSelect(String code) => setState(() =>
      _selected.contains(code) ? _selected.remove(code) : _selected.add(code));


  static const _dayOrder = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  Map<String, int> get _globalDayBreak {
    final counts = {for (final d in _dayOrder) d: 0};
    for (final plan in _beatPlans.values) {
      if ((plan['frequency'] as String?) == 'weekly') {
        final days = plan['days'];
        if (days is List) {
          for (final d in days) {
            final key = d.toString();
            if (counts.containsKey(key)) counts[key] = counts[key]! + 1;
          }
        }
      }
    }
    return counts;
  }

  void _selectAllIn(List<Map<String, dynamic>> accounts) =>
      setState(() => _selected.addAll(accounts.map(_key)));

  void _clearAllIn(List<Map<String, dynamic>> accounts) => setState(() {
        for (final a in accounts) {
          _selected.remove(_key(a));
        }
      });

  Future<void> _selectNIn(List<Map<String, dynamic>> accounts) async {
    final ctrl = TextEditingController();
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Select N Accounts',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'Enter number (max ${accounts.length})',
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: _gold, width: 2),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: _gold, foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            onPressed: () {
              final n = int.tryParse(ctrl.text.trim());
              if (n != null && n > 0) Navigator.pop(ctx, n);
            },
            child: const Text('Select'),
          ),
        ],
      ),
    );
    if (result != null) {
      final unselected = accounts.where((a) => !_selected.contains(_key(a))).toList();
      setState(() => _selected.addAll(unselected.take(result).map(_key)));
    }
  }

  String _key(Map<String, dynamic> a) =>
      (a['accountCode'] as String? ?? '').isNotEmpty
          ? a['accountCode'] as String
          : a['id'].toString();

  // ── Build ─────────────────────────────────────────────────────────────────────

  Future<void> _unassignSelected() async {
    final accountIds = _groups
        .expand((g) => (g['accounts'] as List<Map<String, dynamic>>))
        .where((a) => _selected.contains(_key(a)))
        .map((a) => a['id'] as String? ?? '')
        .where((id) => id.isNotEmpty)
        .toList();

    if (accountIds.isEmpty) return;
    setState(() => _actionLoading = true);
    final ok = await ApiService.unassignBeatPlanBulk(accountIds);
    if (!mounted) return;
    setState(() { _actionLoading = false; _selected.clear(); });
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Beat plan removed'),
        backgroundColor: Colors.orange,
      ));
      _load();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Failed to unassign. Try again.'),
        backgroundColor: Colors.red,
      ));
    }
  }

  Future<void> _showAssignDayDialog() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _AssignDayDialog(selectedCount: _selected.length),
    );
    if (result == null || !mounted) return;

    final frequency   = result['frequency'] as String;
    final days        = (result['days']       as List?)?.cast<String>();
    final monthDate   = result['month_date']  as int?;
    final intervalDays= result['interval_days']as int?;
    final startDate   = result['start_date']  as String?;

    final accountIds = _groups
        .expand((g) => (g['accounts'] as List<Map<String, dynamic>>))
        .where((a) => _selected.contains(_key(a)))
        .map((a) => a['id'] as String? ?? '')
        .where((id) => id.isNotEmpty)
        .toList();

    if (accountIds.isEmpty) return;

    if (mounted) setState(() => _actionLoading = true);
    final res = await ApiService.assignBeatPlan(
      accountIds:   accountIds,
      frequency:    frequency,
      days:         days,
      monthDate:    monthDate,
      intervalDays: intervalDays,
      startDate:    startDate,
    );
    if (!mounted) return;
    setState(() { _actionLoading = false; _selected.clear(); });

    if (res != null && res['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(res['message']?.toString() ?? 'Beat plan assigned'),
        backgroundColor: const Color(0xFF43A047),
      ));
      _load(); // refresh stats
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Failed to assign beat plan. Try again.'),
        backgroundColor: Colors.red,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text('Customer List Allotment'),
        backgroundColor: _gold,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_view_week_rounded),
            tooltip: 'Assignment View',
            onPressed: () => context.push('/assignment-view'),
          ),
          IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _gold))
          : _error.isNotEmpty
              ? _errorState()
              : Column(
                  children: [
                    Expanded(child: _buildList()),
                    _buildBottomBar(),
                  ],
                ),
    );
  }

  Widget _errorState() => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.wifi_off_rounded, size: 56, color: Colors.grey.shade300),
      const SizedBox(height: 12),
      Text(_error, textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: Colors.grey.shade500)),
      const SizedBox(height: 14),
      ElevatedButton.icon(
        onPressed: _load,
        icon: const Icon(Icons.refresh_rounded, size: 16),
        label: const Text('Retry'),
        style: ElevatedButton.styleFrom(
            backgroundColor: _gold, foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
      ),
    ]),
  );

  Widget _buildList() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      children: [
        // Subtitle
        const Text('Pincode-wise allotted customers',
            style: TextStyle(fontSize: 12, color: Colors.black54)),
        const SizedBox(height: 8),

        // Search bar
        TextField(
          controller: _searchCtrl,
          onChanged: (v) => setState(() => _query = v.trim()),
          decoration: InputDecoration(
            hintText: 'Search by name, phone, code...',
            hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
            prefixIcon: const Icon(Icons.search_rounded, color: _gold),
            suffixIcon: _query.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.close_rounded, size: 18),
                    onPressed: () { _searchCtrl.clear(); setState(() => _query = ''); })
                : null,
            filled: true, fillColor: Colors.white, isDense: true,
            contentPadding: const EdgeInsets.symmetric(vertical: 12),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _gold)),
          ),
        ),
        const SizedBox(height: 10),

        // Stats
        Text('${_groups.length} pincode(s)  |  $_totalAccounts account(s)',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),

        // Day count chips
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: _globalDayBreak.entries.map((e) => Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Text('${e.key}:${e.value}',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.black87)),
              ),
            )).toList(),
          ),
        ),
        const SizedBox(height: 12),

        // Pincode sections
        if (_groups.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 40),
            child: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.inbox_outlined, size: 64, color: Colors.grey.shade300),
                const SizedBox(height: 12),
                Text('No accounts in your assigned areas',
                    style: TextStyle(fontSize: 15, color: Colors.grey.shade500)),
              ]),
            ),
          )
        else
          ..._groups.map((g) {
            final pin      = g['pincode'] as String;
            final accounts = g['accounts'] as List<Map<String, dynamic>>;
            final filtered = _filtered(accounts);
            final isOpen   = _expanded.contains(pin);
            final selCount = accounts.where((a) => _selected.contains(_key(a))).length;
            final s = _stats[pin];
            return _PincodeSection(
              pincode:   pin,
              existing:  s?['existing']  ?? accounts.length,
              assign:    s?['assign']    ?? 0,
              remaining: s?['remaining'] ?? accounts.length,
              selected:  selCount,
              expanded:  isOpen,
              onToggle:  () => setState(() => isOpen ? _expanded.remove(pin) : _expanded.add(pin)),
              onSelectAll: () => _selectAllIn(accounts),
              onClearAll:  () => _clearAllIn(accounts),
              onSelectN:   () => _selectNIn(accounts),
              filteredAccounts: filtered,
              selectedKeys: _selected,
              keyOf:        _key,
              onToggleAccount: _toggleSelect,
              beatPlans:    _beatPlans,
            );
          }),

        const SizedBox(height: 80),
      ],
    );
  }

  Widget _buildBottomBar() => Container(
    padding: EdgeInsets.fromLTRB(
        16, 10, 16, 16 + MediaQuery.of(context).padding.bottom),
    decoration: const BoxDecoration(
      color: Colors.white,
      boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, -2))],
    ),
    child: Row(
      children: [
        Text('${_selected.length} selected  |  0 day',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        const Spacer(),
        OutlinedButton.icon(
          onPressed: (_selected.isEmpty || _actionLoading) ? null : _unassignSelected,
          icon: const Icon(Icons.remove_circle_outline_rounded, size: 15),
          label: const Text('Unassign', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.red,
            side: const BorderSide(color: Colors.red),
            disabledForegroundColor: Colors.red.withValues(alpha: 0.3),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          ),
        ),
        const SizedBox(width: 10),
        ElevatedButton.icon(
          onPressed: (_selected.isEmpty || _actionLoading) ? null : _showAssignDayDialog,
          icon: _actionLoading
              ? const SizedBox(width: 15, height: 15,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.save_rounded, size: 15),
          label: const Text('Assign Day', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          style: ElevatedButton.styleFrom(
            backgroundColor: _gold,
            foregroundColor: Colors.white,
            disabledBackgroundColor: _gold.withValues(alpha: 0.4),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          ),
        ),
      ],
    ),
  );
}

// ── Pincode section ───────────────────────────────────────────────────────────

class _PincodeSection extends StatefulWidget {
  final String                       pincode;
  final int                          existing;
  final int                          assign;
  final int                          remaining;
  final int                          selected;
  final bool                         expanded;
  final VoidCallback                 onToggle;
  final VoidCallback                 onSelectAll;
  final VoidCallback                 onClearAll;
  final VoidCallback                 onSelectN;
  final List<Map<String, dynamic>>   filteredAccounts;
  final Set<String>                  selectedKeys;
  final String Function(Map<String, dynamic>) keyOf;
  final void Function(String)        onToggleAccount;
  final Map<String, Map<String, dynamic>> beatPlans;

  const _PincodeSection({
    required this.pincode,
    required this.existing,
    required this.assign,
    required this.remaining,
    required this.selected,
    required this.expanded,
    required this.onToggle,
    required this.onSelectAll,
    required this.onClearAll,
    required this.onSelectN,
    required this.filteredAccounts,
    required this.selectedKeys,
    required this.keyOf,
    required this.onToggleAccount,
    required this.beatPlans,
  });

  @override
  State<_PincodeSection> createState() => _PincodeSectionState();
}

class _PincodeSectionState extends State<_PincodeSection> {
  // active filter: 'existing' (all) | 'assign' | 'remaining' | 'selected'
  String _filter = 'existing';

  static const _dayOrder = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  bool _hasPlan(Map<String, dynamic> a) =>
      widget.beatPlans.containsKey(a['id'] as String? ?? '');

  // Per-pincode breakdown: weekly day counts + monthly/n_days totals
  // for this pincode's assigned accounts.
  Map<String, int> get _dayBreak {
    final counts = {for (final d in _dayOrder) d: 0};
    var monthly = 0;
    var nDays   = 0;
    for (final a in widget.filteredAccounts) {
      final plan = widget.beatPlans[a['id'] as String? ?? ''];
      if (plan == null) continue;
      switch (plan['frequency'] as String?) {
        case 'weekly':
          final days = plan['days'];
          if (days is List) {
            for (final d in days) {
              final key = d.toString();
              if (counts.containsKey(key)) counts[key] = counts[key]! + 1;
            }
          }
        case 'monthly':
          monthly++;
        case 'n_days':
          nDays++;
      }
    }
    counts['Monthly'] = monthly;
    counts['N-Days']  = nDays;
    return counts;
  }

  List<Map<String, dynamic>> get _visibleAccounts {
    switch (_filter) {
      case 'assign':
        return widget.filteredAccounts.where(_hasPlan).toList();
      case 'remaining':
        return widget.filteredAccounts.where((a) => !_hasPlan(a)).toList();
      case 'selected':
        return widget.filteredAccounts
            .where((a) => widget.selectedKeys.contains(widget.keyOf(a)))
            .toList();
      default:
        return widget.filteredAccounts;
    }
  }

  @override
  Widget build(BuildContext context) {
    final pincode          = widget.pincode;
    final expanded         = widget.expanded;
    final beatPlans        = widget.beatPlans;
    final selectedKeys     = widget.selectedKeys;
    final keyOf            = widget.keyOf;
    final onToggleAccount  = widget.onToggleAccount;
    final visibleAccounts  = _visibleAccounts;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFEEEEEE)),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Pincode + expand toggle
                InkWell(
                  onTap: widget.onToggle,
                  child: Row(
                    children: [
                      Text(pincode,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                      const Spacer(),
                      Icon(expanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                          color: Colors.black45),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                // Clickable filter buttons — single row
                Row(
                  children: [
                    Expanded(child: _FilterBtn(
                      label: 'Existing', count: widget.existing,
                      active: _filter == 'existing',
                      onTap: () => setState(() { _filter = 'existing'; if (!expanded) widget.onToggle(); }),
                    )),
                    const SizedBox(width: 5),
                    Expanded(child: _FilterBtn(
                      label: 'Assign', count: widget.assign,
                      active: _filter == 'assign',
                      onTap: () => setState(() { _filter = 'assign'; if (!expanded) widget.onToggle(); }),
                    )),
                    const SizedBox(width: 5),
                    Expanded(child: _FilterBtn(
                      label: 'Remaining', count: widget.remaining,
                      active: _filter == 'remaining',
                      onTap: () => setState(() { _filter = 'remaining'; if (!expanded) widget.onToggle(); }),
                    )),
                    const SizedBox(width: 5),
                    Expanded(child: _FilterBtn(
                      label: 'Selected', count: widget.selected,
                      active: _filter == 'selected',
                      onTap: () => setState(() { _filter = 'selected'; if (!expanded) widget.onToggle(); }),
                    )),
                  ],
                ),
                const SizedBox(height: 8),
                // Per-pincode day breakdown
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: () {
                      final db = _dayBreak;
                      // weekdays always shown, then Monthly/N-Days only if > 0
                      final keys = [
                        ..._dayOrder,
                        if ((db['Monthly'] ?? 0) > 0) 'Monthly',
                        if ((db['N-Days'] ?? 0) > 0) 'N-Days',
                      ];
                      final items = <Widget>[];
                      for (var i = 0; i < keys.length; i++) {
                        final k = keys[i];
                        final n = db[k] ?? 0;
                        items.add(Text('$k:$n',
                            style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: n > 0 ? FontWeight.w700 : FontWeight.w500,
                                color: n > 0 ? const Color(0xFF2E7D32) : Colors.grey.shade500)));
                        if (i < keys.length - 1) {
                          items.add(Text('  |  ',
                              style: TextStyle(fontSize: 10.5, color: Colors.grey.shade300)));
                        }
                      }
                      return items;
                    }(),
                  ),
                ),
              ],
            ),
          ),

          // Expanded body
          if (expanded) ...[
            const Divider(height: 1),
            if (visibleAccounts.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                child: Row(
                  children: [
                    _SelectBtn(icon: Icons.check_box_rounded,              label: 'Select All',  onTap: widget.onSelectAll),
                    const SizedBox(width: 8),
                    _SelectBtn(icon: Icons.check_box_outline_blank_rounded, label: 'Unselect All', onTap: widget.onClearAll),
                    const SizedBox(width: 8),
                    _SelectBtn(icon: Icons.format_list_numbered_rounded,   label: 'Select N',    onTap: widget.onSelectN),
                  ],
                ),
              ),
            ...visibleAccounts.map((a) => _AccountCard(
              account:    a,
              isSelected: selectedKeys.contains(keyOf(a)),
              onCheckTap: () => onToggleAccount(keyOf(a)),
              plan:       beatPlans[a['id'] as String? ?? ''],
            )),
            if (visibleAccounts.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 18),
                child: Center(
                  child: Text(
                    _filter == 'existing'
                        ? 'No accounts found'
                        : 'No "$_filter" accounts in this pincode',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
                ),
              ),
            const SizedBox(height: 6),
          ],
        ],
      ),
    );
  }
}

// ── Account card ──────────────────────────────────────────────────────────────

class _AccountCard extends StatelessWidget {
  final Map<String, dynamic>  account;
  final bool                  isSelected;
  final VoidCallback          onCheckTap; // checkbox toggle
  final Map<String, dynamic>? plan;       // active beat plan, if any

  const _AccountCard({
    required this.account,
    required this.isSelected,
    required this.onCheckTap,
    this.plan,
  });

  // Build a short human label for the active plan
  String? get _planLabel {
    final p = plan;
    if (p == null) return null;
    switch (p['frequency'] as String?) {
      case 'weekly':
        final days = (p['days'] as List?)?.cast<dynamic>() ?? [];
        return days.isEmpty ? null : days.join(', ');
      case 'monthly':
        final d = p['month_date'];
        return d == null ? null : 'Day $d/month';
      case 'n_days':
        final n = p['interval_days'];
        return n == null ? null : 'Every $n days';
      default:
        return null;
    }
  }

  Future<void> _launch(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  void _call(String phone) => _launch('tel:$phone');

  void _whatsapp(String phone) {
    // Strip leading 0 / +91 and normalise to 10 digits, then prepend country code
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    final number = digits.length == 10 ? '91$digits' : digits;
    _launch('https://wa.me/$number');
  }

  @override
  Widget build(BuildContext context) {
    final id      = (account['id']           as String?) ?? '';
    final code    = account['accountCode']   as String? ?? '';
    final name    = account['businessName']  as String? ?? '—';
    final person  = account['personName']    as String? ?? '';
    final phone   = account['contactNumber'] as String? ?? '';
    final address = account['address']       as String? ?? '';
    final area    = account['area']          as String? ?? '';

    return GestureDetector(
      onTap: () {
        if (id.isNotEmpty) context.push('/lead-accounts/$id', extra: account);
      },
      child: Container(
        margin: const EdgeInsets.fromLTRB(10, 4, 10, 4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? const Color(0xFF1976D2) : const Color(0xFFEEEEEE),
          ),
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Code + person name
            Row(
              children: [
                Text(code,
                    style: const TextStyle(fontSize: 11, color: Colors.black45, letterSpacing: 0.4)),
                const Spacer(),
                if (person.isNotEmpty)
                  Text(person,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 4),
            Text(name,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            if (address.isNotEmpty)
              Text('Address : $address',
                  style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
            if (area.isNotEmpty)
              Text('Main area : $area',
                  style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
            // Assigned beat-plan chip
            if (_planLabel != null) ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF43A047).withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF43A047).withValues(alpha: 0.30)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.event_repeat_rounded, size: 12, color: Color(0xFF2E7D32)),
                    const SizedBox(width: 4),
                    Text(_planLabel!,
                        style: const TextStyle(
                            fontSize: 10.5, fontWeight: FontWeight.w700, color: Color(0xFF2E7D32))),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 8),
            // Checkbox + phone + call + whatsapp
            Row(
              children: [
                // Checkbox — stops tap propagating to card
                GestureDetector(
                  onTap: onCheckTap,
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    width: 22, height: 22,
                    decoration: BoxDecoration(
                      color: isSelected ? const Color(0xFF1976D2) : Colors.white,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: isSelected ? const Color(0xFF1976D2) : Colors.grey.shade400,
                      ),
                    ),
                    child: isSelected
                        ? const Icon(Icons.check_rounded, size: 14, color: Colors.white)
                        : null,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.phone_rounded, size: 13, color: Colors.grey.shade600),
                        const SizedBox(width: 5),
                        Text(phone,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Call button
                _ActionBtn(
                  icon: Icons.call_rounded,
                  color: Colors.grey.shade600,
                  onTap: phone.isNotEmpty ? () => _call(phone) : null,
                ),
                const SizedBox(width: 6),
                // WhatsApp button
                _ActionBtn(
                  icon: Icons.chat_rounded,
                  color: const Color(0xFF25D366),
                  onTap: phone.isNotEmpty ? () => _whatsapp(phone) : null,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Small helpers ─────────────────────────────────────────────────────────────

class _FilterBtn extends StatelessWidget {
  final String       label;
  final int          count;
  final bool         active;
  final VoidCallback onTap;
  const _FilterBtn({
    required this.label,
    required this.count,
    required this.active,
    required this.onTap,
  });

  static const _gold = Color(0xFFD7BE69);

  @override
  Widget build(BuildContext context) {
    final fg = active ? const Color(0xFF8A6D1B) : Colors.black87;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 5),
        decoration: BoxDecoration(
          color: active ? _gold.withValues(alpha: 0.18) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: active ? _gold : Colors.grey.shade300,
              width: active ? 1.5 : 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 8.5, fontWeight: FontWeight.w600, color: fg)),
            ),
            const SizedBox(width: 2),
            Text('$count',
                style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w800, color: fg)),
          ],
        ),
      ),
    );
  }
}

class _SelectBtn extends StatelessWidget {
  final IconData     icon;
  final String       label;
  final VoidCallback onTap;
  const _SelectBtn({required this.icon, required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(20),
            color: Colors.grey.shade50,
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 13, color: Colors.black54),
            const SizedBox(width: 4),
            Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
          ]),
        ),
      );
}

// ── Assign Day Dialog ─────────────────────────────────────────────────────────

class _AssignDayDialog extends StatefulWidget {
  final int selectedCount;
  const _AssignDayDialog({required this.selectedCount});

  @override
  State<_AssignDayDialog> createState() => _AssignDayDialogState();
}

class _AssignDayDialogState extends State<_AssignDayDialog> {
  static const _gold = Color(0xFFD7BE69);
  static const _allDays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  // frequency: 'weekly' | 'monthly' | 'n_days'
  String          _frequency    = 'weekly';
  final Set<String> _days       = {};         // weekly
  final _monthCtrl = TextEditingController(); // monthly: 1-31
  final _nCtrl     = TextEditingController(); // n_days: interval
  DateTime?       _startDate;                // n_days: anchor date

  @override
  void dispose() {
    _monthCtrl.dispose();
    _nCtrl.dispose();
    super.dispose();
  }

  bool get _canSubmit {
    switch (_frequency) {
      case 'weekly':  return _days.isNotEmpty;
      case 'monthly': final v = int.tryParse(_monthCtrl.text.trim()); return v != null && v >= 1 && v <= 31;
      case 'n_days':  final n = int.tryParse(_nCtrl.text.trim()); return n != null && n >= 1 && _startDate != null;
      default:        return false;
    }
  }

  void _submit() {
    if (!_canSubmit) return;
    switch (_frequency) {
      case 'weekly':
        Navigator.pop(context, {'frequency': 'weekly', 'days': _days.toList()});
      case 'monthly':
        Navigator.pop(context, {'frequency': 'monthly', 'month_date': int.parse(_monthCtrl.text.trim())});
      case 'n_days':
        Navigator.pop(context, {
          'frequency':    'n_days',
          'interval_days': int.parse(_nCtrl.text.trim()),
          'start_date':   _startDate!.toIso8601String().substring(0, 10),
        });
    }
  }

  Future<void> _pickStartDate() async {
    final picked = await showDatePicker(
      context:      context,
      initialDate:  _startDate ?? DateTime.now(),
      firstDate:    DateTime.now(),
      lastDate:     DateTime.now().add(const Duration(days: 365)),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(primary: _gold),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _startDate = picked);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title + count
              Row(children: [
                const Text('Assign Day',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _gold.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text('${widget.selectedCount} accounts',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _gold)),
                ),
              ]),
              const SizedBox(height: 14),

              // ── Frequency selector ─────────────────────────────────────────
              RadioGroup<String>(
                groupValue: _frequency,
                onChanged: (v) { if (v != null) setState(() => _frequency = v); },
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _FreqRadio(value: 'weekly',  label: 'Weekly',  freq: _frequency, onTap: () => setState(() => _frequency = 'weekly')),
                      const SizedBox(width: 4),
                      _FreqRadio(value: 'monthly', label: 'Monthly', freq: _frequency, onTap: () => setState(() => _frequency = 'monthly')),
                      const SizedBox(width: 4),
                      _FreqRadio(value: 'n_days',  label: 'N Days',  freq: _frequency, onTap: () => setState(() => _frequency = 'n_days')),
                    ],
                  ),
                ),
              ),

              const Divider(height: 20),

              // ── Weekly body ────────────────────────────────────────────────
              if (_frequency == 'weekly') ...[
                const Text('Select days of the week:',
                    style: TextStyle(fontSize: 12, color: Colors.black54)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8, runSpacing: 8,
                  children: _allDays.map((d) {
                    final on = _days.contains(d);
                    return GestureDetector(
                      onTap: () => setState(() => on ? _days.remove(d) : _days.add(d)),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: on ? _gold : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: on ? _gold : Colors.grey.shade300),
                        ),
                        child: Text(d,
                            style: TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600,
                              color: on ? Colors.white : Colors.black54,
                            )),
                      ),
                    );
                  }).toList(),
                ),
              ],

              // ── Monthly body ───────────────────────────────────────────────
              if (_frequency == 'monthly') ...[
                const Text('Day of month (1 – 31):',
                    style: TextStyle(fontSize: 12, color: Colors.black54)),
                const SizedBox(height: 8),
                TextField(
                  controller: _monthCtrl,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'e.g. 5  →  5th of every month',
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: _gold, width: 2),
                    ),
                  ),
                ),
              ],

              // ── N Days body ────────────────────────────────────────────────
              if (_frequency == 'n_days') ...[
                const Text('Repeat every N days:',
                    style: TextStyle(fontSize: 12, color: Colors.black54)),
                const SizedBox(height: 8),
                TextField(
                  controller: _nCtrl,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'e.g. 7  →  every 7 days',
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: _gold, width: 2),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Text('Start date:',
                    style: TextStyle(fontSize: 12, color: Colors.black54)),
                const SizedBox(height: 6),
                InkWell(
                  onTap: _pickStartDate,
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                    decoration: BoxDecoration(
                      border: Border.all(
                          color: _startDate != null ? _gold : Colors.grey.shade400),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(children: [
                      Icon(Icons.calendar_today_rounded, size: 16,
                          color: _startDate != null ? _gold : Colors.grey),
                      const SizedBox(width: 8),
                      Text(
                        _startDate != null
                            ? '${_startDate!.day.toString().padLeft(2,'0')}/'
                              '${_startDate!.month.toString().padLeft(2,'0')}/'
                              '${_startDate!.year}'
                            : 'Pick a start date',
                        style: TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w500,
                          color: _startDate != null ? Colors.black87 : Colors.grey,
                        ),
                      ),
                    ]),
                  ),
                ),
              ],

              const SizedBox(height: 20),

              // ── Actions ────────────────────────────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel',
                        style: TextStyle(color: Colors.grey, fontSize: 14)),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _canSubmit ? _gold : Colors.grey.shade300,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20)),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 10),
                    ),
                    onPressed: _canSubmit ? _submit : null,
                    child: const Text('Ok',
                        style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FreqRadio extends StatelessWidget {
  final String value, label, freq;
  final VoidCallback onTap;
  const _FreqRadio({required this.value, required this.label, required this.freq, required this.onTap});

  static const _gold = Color(0xFFD7BE69);

  @override
  Widget build(BuildContext context) {
    final on = freq == value;
    return GestureDetector(
      onTap: onTap,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Radio<String>(value: value, activeColor: _gold),
        Text(label,
            style: TextStyle(
              fontSize: 13, fontWeight: FontWeight.w600,
              color: on ? _gold : Colors.black54,
            )),
      ]),
    );
  }
}

// ── Action button ─────────────────────────────────────────────────────────────

class _ActionBtn extends StatelessWidget {
  final IconData      icon;
  final Color         color;
  final VoidCallback? onTap;
  const _ActionBtn({required this.icon, required this.color, this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: 36, height: 36,
          decoration: BoxDecoration(color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
          child: Icon(icon, size: 18, color: color),
        ),
      );
}

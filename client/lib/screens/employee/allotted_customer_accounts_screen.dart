import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/api_service.dart';
import '../../services/user_service.dart';
import '../../widgets/account_map_screen.dart';
import 'customer_detail_screen.dart';

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
  // 'all' | 'lead' | 'customer'
  String _typeFilter = 'all';

  bool   _loading       = true;
  bool   _actionLoading = false;
  String _error         = '';

  // {pincode, accounts: [...]}
  List<Map<String, dynamic>> _groups = [];

  // {pincode: {existing, assign, remaining}} — from beat-plan/stats API
  Map<String, Map<String, int>> _stats = {};

  // {accountId: beatPlan} — from beat-plan/my-plans API
  Map<String, Map<String, dynamic>> _beatPlans = {};

  // Count of assigned areas whose pincodes couldn't be fetched this load —
  // those pincodes are silently missing from _groups, so this drives a
  // warning banner instead of failing the whole screen.
  int _failedAreaCount = 0;

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
      var areaResults = await Future.wait(areaIds.map(ApiService.getArea));

      // A single failed request (timeout/network blip) here used to silently
      // drop that area's pincodes from the list with no indication to the
      // user — retry the failures once before giving up on them.
      final failedIds = <int>[
        for (var i = 0; i < areaIds.length; i++)
          if (areaResults[i] == null) areaIds[i],
      ];
      if (failedIds.isNotEmpty) {
        final retried = await Future.wait(failedIds.map(ApiService.getArea));
        var r = 0;
        areaResults = [
          for (var i = 0; i < areaIds.length; i++)
            areaResults[i] ?? retried[r++],
        ];
      }

      final pincodes = <String>[];
      var failedCount = 0;
      for (final area in areaResults) {
        if (area == null) { failedCount++; continue; }
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
      final leads = raw is List
          ? raw.map((e) {
              final m = Map<String, dynamic>.from(e as Map);
              m['_type'] = 'lead';
              return m;
            }).toList()
          : <Map<String, dynamic>>[];

      // Also fetch customers from user table (same pincodes)
      final customerRaw = await ApiService.getCustomers(pincodes: pincodes);
      final customers = customerRaw.map((u) => <String, dynamic>{
        'id':            u['userid'].toString(),
        'accountCode':   '',
        'businessName':  (u['shop_name'] as String?)?.isNotEmpty == true
            ? u['shop_name']
            : (u['name'] ?? '').toString(),
        'personName':    (u['name'] ?? '').toString(),
        'contactNumber': (u['contactno'] ?? '').toString(),
        'address':       (u['address'] ?? u['shop_address'] ?? '').toString(),
        'addresses':     ((u['addresses'] as List?) ?? [])
            .map((a) => (a as Map)['address']?.toString() ?? '')
            .where((a) => a.isNotEmpty)
            .toList(),
        'pincode':       (u['pincode'] ?? '').toString(),
        'latitude':      u['latitude'],
        'longitude':     u['longitude'],
        '_type':         'customer',
        // Raw user-table field names — kept alongside the normalised keys
        // above so CustomerDetailScreen (which reads userid/shop_name/name/
        // contactno/email/city/state/user_type) shows real values instead
        // of blanks.
        'userid':        u['userid'],
        'shop_name':     (u['shop_name'] ?? '').toString(),
        'name':          (u['name'] ?? '').toString(),
        'contactno':     (u['contactno'] ?? '').toString(),
        'email':         (u['email'] ?? '').toString(),
        'shop_address':  (u['shop_address'] ?? '').toString(),
        'city':          (u['city'] ?? '').toString(),
        'state':         (u['state'] ?? '').toString(),
        'user_type':     (u['user_type'] ?? '').toString(),
      }).toList();

      // Merge leads + customers
      final allAccounts = [...leads, ...customers];

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
        _groups           = groups;
        _stats            = stats;
        _beatPlans        = beatPlans;
        _failedAreaCount  = failedCount;
        _loading          = false;
      });
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = 'Failed to load data. Tap refresh to retry.'; });
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────────

  int get _totalAccounts =>
      _groups.fold(0, (s, g) => s + (g['accounts'] as List).length);

  List<Map<String, dynamic>> _filtered(List accounts) {
    var list = accounts.cast<Map<String, dynamic>>();
    if (_typeFilter != 'all') {
      list = list.where((a) => (a['_type'] as String?) == _typeFilter).toList();
    }
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

  String _planLabelFrom(Map<String, dynamic> p) {
    final freq = p['frequency'] as String? ?? '';
    switch (freq) {
      case 'weekly':
        final days = (p['days'] as List?)?.cast<dynamic>() ?? [];
        final alt = p['week_anchor_date'] != null ? ' (Alt)' : '';
        return days.isEmpty ? 'Weekly$alt' : 'Weekly: ${days.join(', ')}$alt';
      case 'monthly':
        final d = p['month_date'];
        return d == null ? 'Monthly' : 'Monthly: Day $d';
      case 'specific_dates':
        final dates = (p['specific_dates'] as List?)?.cast<String>() ?? [];
        return dates.isEmpty ? 'Specific Dates' : 'Specific: ${dates.length} dates';
      case 'appointment':
        final apt = p['appointment_date'] as String?;
        if (apt == null) return 'Appointment';
        try {
          final dt = DateTime.parse(apt);
          return 'Appt: ${dt.day}/${dt.month} ${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}';
        } catch (_) {
          return 'Appointment';
        }
      case 'n_days':
        final n = p['interval_days'];
        return n == null ? 'N Days' : 'Every $n days';
      default:
        return freq;
    }
  }

  Future<void> _showAssignDayDialog() async {
    // Check if any selected accounts already have a beat plan
    final alreadyAssigned = <Map<String, dynamic>>[];
    for (final g in _groups) {
      for (final a in (g['accounts'] as List<Map<String, dynamic>>)) {
        if (_selected.contains(_key(a))) {
          final id = a['id'] as String? ?? '';
          if (id.isNotEmpty && _beatPlans.containsKey(id)) {
            final plan = _beatPlans[id];
            // Only add if plan has a valid frequency (not null/empty)
            final freq = plan?['frequency'] as String?;
            if (freq != null && freq.isNotEmpty) {
              alreadyAssigned.add(a);
            }
          }
        }
      }
    }

    if (alreadyAssigned.isNotEmpty && mounted) {
      final proceed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('Already Assigned'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('The following account(s) already have a beat plan:'),
                const SizedBox(height: 10),
                Flexible(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 320),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: alreadyAssigned.length,
                      separatorBuilder: (_, _) => const Divider(height: 16),
                      itemBuilder: (_, i) {
                        final a = alreadyAssigned[i];
                        final plan = _beatPlans[a['id'] as String]!;
                        final name = a['businessName'] as String? ?? a['shop_name'] as String? ?? 'Account';
                        final isLead = (a['_type'] as String?) == 'lead';
                        final code = a['accountCode'] as String? ?? '';
                        final phone = a['contactNumber'] as String? ?? '';
                        final pincode = a['pincode'] as String? ?? '';
                        final detailParts = [
                          isLead ? 'Lead' : 'Customer',
                          if (code.isNotEmpty) code,
                          if (pincode.isNotEmpty) 'Pin $pincode',
                          if (phone.isNotEmpty) phone,
                        ];
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
                            const SizedBox(height: 2),
                            Text(
                              detailParts.join(' · '),
                              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                            ),
                            Text(
                              _planLabelFrom(plan),
                              style: const TextStyle(fontSize: 12, color: Colors.black87),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Text('Do you want to reassign them?'),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: _gold),
              child: const Text('Reassign', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
      if (proceed != true || !mounted) return;
    }

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _AssignDayDialog(selectedCount: _selected.length),
    );
    if (result == null || !mounted) return;

    final frequency   = result['frequency'] as String;
    final days        = (result['days']       as List?)?.cast<String>();
    final monthDate   = result['month_date']  as int?;
    final specificDates = (result['specific_dates'] as List?)?.cast<String>();
    final appointmentDate = result['appointment_date'] as String?;
    final weekAnchorDate = result['week_anchor_date'] as String?;
    final intervalDays= result['interval_days']as int?;
    final startDate   = result['start_date']  as String?;

    final selected = <Map<String, dynamic>>[];
    for (final g in _groups) {
      for (final a in (g['accounts'] as List<Map<String, dynamic>>)) {
        if (_selected.contains(_key(a))) {
          selected.add(a);
        }
      }
    }

    final accountIds = selected.map((a) => a['id'] as String? ?? '').where((id) => id.isNotEmpty).toList();
    final accountTypes = selected.map((a) => (a['_type'] as String?) == 'customer' ? 'customer' : 'lead').toList();

    if (accountIds.isEmpty) return;

    if (mounted) setState(() => _actionLoading = true);
    final res = await ApiService.assignBeatPlan(
      accountIds:   accountIds,
      accountTypes: accountTypes,
      frequency:    frequency,
      days:         days,
      monthDate:    monthDate,
      specificDates: specificDates,
      appointmentDate: appointmentDate,
      weekAnchorDate: weekAnchorDate,
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
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Customer List Allotment'),
            const Text(
              'Lead , User',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w400),
            ),
          ],
        ),
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

  Widget _typeChip(String label, String value) {
    final selected = _typeFilter == value;
    return GestureDetector(
      onTap: () => setState(() => _typeFilter = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? _gold : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? _gold : Colors.grey.shade300),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : Colors.black87,
          ),
        ),
      ),
    );
  }

  Widget _buildList() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      children: [
        // Subtitle
        const Text('Pincode-wise allotted customers',
            style: TextStyle(fontSize: 12, color: Colors.black54)),
        const SizedBox(height: 8),

        // Some assigned areas failed to load even after a retry — their
        // pincodes are missing from the list below, so surface that instead
        // of leaving the user to wonder why a pincode they expect isn't here.
        if (_failedAreaCount > 0) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.orange.shade200),
            ),
            child: Row(
              children: [
                Icon(Icons.warning_amber_rounded, size: 16, color: Colors.orange.shade800),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '$_failedAreaCount assigned area(s) failed to load — some pincodes may be missing. Tap refresh to retry.',
                    style: TextStyle(fontSize: 11.5, color: Colors.orange.shade900),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],

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

        // Lead / Customer filter
        Row(
          children: [
            _typeChip('All',       'all'),
            const SizedBox(width: 8),
            _typeChip('Leads',     'lead'),
            const SizedBox(width: 8),
            _typeChip('Customers', 'customer'),
          ],
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
          ..._groups.where((g) {
            // When a filter/search is active, drop pincodes with no matches
            if (_typeFilter == 'all' && _query.isEmpty) return true;
            return _filtered(g['accounts'] as List).isNotEmpty;
          }).map((g) {
            final pin      = (g['pincode'] ?? '').toString();
            final accounts = (g['accounts'] as List).cast<Map<String, dynamic>>();
            final filtered = _filtered(accounts);
            final isOpen   = _expanded.contains(pin);
            final selCount = accounts.where((a) => _selected.contains(_key(a))).length;
            final s = _stats[pin];

            // Separate leads and customers
            final leads = accounts.where((a) => (a['_type'] as String?) == 'lead').toList();
            final customers = accounts.where((a) => (a['_type'] as String?) == 'customer').toList();

            // Count with beat plans
            final leadsWithPlan = leads.where((a) => _beatPlans.containsKey(a['id'] as String? ?? '')).length;
            final customersWithPlan = customers.where((a) => _beatPlans.containsKey(a['id'] as String? ?? '')).length;

            // Selected by type
            final selectedLeads = leads.where((a) => _selected.contains(_key(a))).length;
            final selectedCustomers = customers.where((a) => _selected.contains(_key(a))).length;

            return _PincodeSection(
              pincode:   pin,
              existingL: leads.length,
              existingC: customers.length,
              assignL:   leadsWithPlan,
              assignC:   customersWithPlan,
              remainingL: leads.length - leadsWithPlan,
              remainingC: customers.length - customersWithPlan,
              selectedL:  selectedLeads,
              selectedC:  selectedCustomers,
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
        Expanded(
          child: Text('${_selected.length} selected',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        ),
        OutlinedButton(
          onPressed: (_selected.isEmpty || _actionLoading) ? null : _unassignSelected,
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.red,
            side: const BorderSide(color: Colors.red),
            disabledForegroundColor: Colors.red.withValues(alpha: 0.3),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          ),
          child: const Text('Unassign', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
        ),
        const SizedBox(width: 8),
        ElevatedButton(
          onPressed: (_selected.isEmpty || _actionLoading) ? null : _showAssignDayDialog,
          style: ElevatedButton.styleFrom(
            backgroundColor: _gold,
            foregroundColor: Colors.white,
            disabledBackgroundColor: _gold.withValues(alpha: 0.4),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          ),
          child: _actionLoading
              ? const SizedBox(width: 12, height: 12,
                  child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.white))
              : const Text('Assign', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
        ),
      ],
    ),
  );
}

// ── Pincode section ───────────────────────────────────────────────────────────

class _PincodeSection extends StatefulWidget {
  final String                       pincode;
  final int                          existingL;
  final int                          existingC;
  final int                          assignL;
  final int                          assignC;
  final int                          remainingL;
  final int                          remainingC;
  final int                          selectedL;
  final int                          selectedC;
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
    required this.existingL,
    required this.existingC,
    required this.assignL,
    required this.assignC,
    required this.remainingL,
    required this.remainingC,
    required this.selectedL,
    required this.selectedC,
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
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
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
                    ),
                    IconButton(
                      icon: const Icon(Icons.map_rounded, size: 20, color: Color(0xFF8A6D1B)),
                      tooltip: 'Show in Map',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => AccountMapScreen(
                            title: 'Pincode $pincode — Map',
                            accounts: widget.filteredAccounts,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Clickable filter buttons — single row
                Row(
                  children: [
                    Expanded(child: _FilterBtn(
                      label: 'Existing', countL: widget.existingL, countC: widget.existingC,
                      active: _filter == 'existing',
                      onTap: () => setState(() { _filter = 'existing'; if (!expanded) widget.onToggle(); }),
                    )),
                    const SizedBox(width: 5),
                    Expanded(child: _FilterBtn(
                      label: 'Assign', countL: widget.assignL, countC: widget.assignC,
                      active: _filter == 'assign',
                      onTap: () => setState(() { _filter = 'assign'; if (!expanded) widget.onToggle(); }),
                    )),
                    const SizedBox(width: 5),
                    Expanded(child: _FilterBtn(
                      label: 'Unassigned', countL: widget.remainingL, countC: widget.remainingC,
                      active: _filter == 'remaining',
                      onTap: () => setState(() { _filter = 'remaining'; if (!expanded) widget.onToggle(); }),
                    )),
                    const SizedBox(width: 5),
                    Expanded(child: _FilterBtn(
                      label: 'Selected', countL: widget.selectedL, countC: widget.selectedC,
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
    final freq = p['frequency'] as String?;
    if (freq == null) return null;

    switch (freq) {
      case 'weekly':
        final days = (p['days'] as List?)?.cast<dynamic>() ?? [];
        final alt = p['week_anchor_date'] != null ? ' (Alt)' : '';
        return days.isEmpty ? 'Weekly$alt' : 'Weekly: ${days.join(', ')}$alt';
      case 'monthly':
        final d = p['month_date'];
        return d == null ? 'Monthly' : 'Monthly: Day $d';
      case 'specific_dates':
        final dates = (p['specific_dates'] as List?)?.cast<String>() ?? [];
        if (dates.isEmpty) return 'Specific Dates';
        return dates.length == 1 ? 'Specific: ${dates[0]}' : 'Specific: ${dates.length} dates';
      case 'appointment':
        final apt = p['appointment_date'] as String?;
        if (apt == null) return 'Appointment';
        try {
          final dt = DateTime.parse(apt);
          return 'Appt: ${dt.day}/${dt.month} ${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}';
        } catch (e) {
          return 'Appointment';
        }
      case 'n_days':
        final n = p['interval_days'];
        return n == null ? 'N Days' : 'Every $n days';
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

  Future<void> _cloudCall(BuildContext context, String phone) async {
    final accountId   = (account['id'] as String?) ?? '';
    final accountType = (account['_type'] as String?) == 'customer' ? 'customer' : 'lead';
    if (accountId.isEmpty) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Calling… your phone will ring first, then the customer.')),
    );
    final result = await ApiService.triggerKnowlarityCall(
      accountId: accountId,
      accountType: accountType,
      customerNumber: phone,
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result == null ? 'Could not start the call. Try again.' : 'Call started'),
        backgroundColor: result == null ? Colors.red : const Color(0xFF43A047),
      ),
    );
  }

  String _formatAccountId(String code) {
    // Use code if available, otherwise parse ID and remove leading zeros
    if (code.isNotEmpty) return code;

    final accountId = (account['id'] as String?) ?? '';
    if (accountId.isEmpty) return '';

    // Try to parse as integer to remove leading zeros
    final num = int.tryParse(accountId);
    if (num != null) return num.toString();

    // If not numeric, just truncate UUID to first 8 chars
    return accountId.length > 8 ? accountId.substring(0, 8).toUpperCase() : accountId.toUpperCase();
  }

  Widget _buildTypeChip(String type) {
    final isLead = type == 'lead';
    final gold = const Color(0xFFD7BE69);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: isLead ? gold.withValues(alpha: 0.12) : Colors.green.shade50,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isLead ? gold : Colors.green.shade400,
        ),
      ),
      child: Text(
        isLead ? 'Lead' : 'Customer',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: isLead ? const Color(0xFFB89A3E) : Colors.green.shade700,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final id      = (account['id']           as String?) ?? '';
    final code    = account['accountCode']   as String? ?? '';
    final name    = account['businessName']  as String? ?? '—';
    final person  = account['personName']    as String? ?? '';
    final phone   = account['contactNumber'] as String? ?? '';
    final address = account['address']       as String? ?? '';
    final addresses = ((account['addresses'] as List?) ?? [])
        .map((a) => a.toString())
        .where((a) => a.isNotEmpty)
        .toList();
    final area    = account['area']          as String? ?? '';
    final type    = (account['_type']        as String?) ?? 'lead';
    final isLead  = type == 'lead';

    return GestureDetector(
      onTap: () {
        if (id.isNotEmpty) {
          if (isLead) {
            context.push('/lead-accounts/$id', extra: account);
          } else {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (ctx) => CustomerDetailScreen(customer: account),
              ),
            );
          }
        }
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
            // Account type + ID/code + person name
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text('${isLead ? 'Lead' : 'User'} Ac :${_formatAccountId(code)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, color: Colors.black45, letterSpacing: 0.4)),
                ),
                if (person.isNotEmpty) ...[
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(person,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 4),
            // Lead/Customer type chip
            _buildTypeChip((account['_type'] ?? 'lead').toString()),
            const SizedBox(height: 6),
            Text(name,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            if (addresses.length > 1)
              ...addresses.asMap().entries.map((e) => Padding(
                    padding: const EdgeInsets.only(bottom: 1),
                    child: Text('Address ${e.key + 1} : ${e.value}',
                        style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
                  ))
            else if (address.isNotEmpty)
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
            // Checkbox + phone pill + call + whatsapp buttons
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
                const SizedBox(width: 8),
                // Phone pill (compact)
                if (phone.isNotEmpty)
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.phone_rounded, size: 12, color: Colors.grey.shade600),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(phone,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(width: 6),
                // Call button
                _ActionBtn(
                  icon: const Icon(Icons.call_rounded, size: 18, color: Colors.grey),
                  color: Colors.grey.shade600,
                  onTap: phone.isNotEmpty ? () => _call(phone) : null,
                ),
                const SizedBox(width: 4),
                // Cloud call (Knowlarity click-to-call bridge)
                _ActionBtn(
                  icon: const Icon(Icons.ring_volume_rounded, size: 18, color: Color(0xFF8E24AA)),
                  color: const Color(0xFF8E24AA),
                  onTap: phone.isNotEmpty ? () => _cloudCall(context, phone) : null,
                ),
                const SizedBox(width: 4),
                // WhatsApp button
                _ActionBtn(
                  icon: const FaIcon(FontAwesomeIcons.whatsapp, size: 18, color: Color(0xFF25D366)),
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
  final int          countL;
  final int          countC;
  final bool         active;
  final VoidCallback onTap;
  const _FilterBtn({
    required this.label,
    required this.countL,
    required this.countC,
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
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        decoration: BoxDecoration(
          color: active ? _gold.withValues(alpha: 0.18) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: active ? _gold : Colors.grey.shade300,
              width: active ? 1.5 : 1),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 8, fontWeight: FontWeight.w600, color: fg)),
            const SizedBox(height: 1),
            Text('L:$countL C:$countC',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 9, fontWeight: FontWeight.w800, color: fg)),
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

  // frequency: 'weekly' | 'monthly' | 'n_days' | 'specific_dates' | 'appointment'
  String          _frequency    = 'weekly';
  final Set<String> _days       = {};         // weekly
  bool            _alternateWeek = false;     // weekly: alternate weeks toggle
  final _monthCtrl = TextEditingController(); // monthly: 1-31 (legacy)
  final _nCtrl     = TextEditingController(); // n_days: interval
  DateTime?       _startDate;                // n_days: anchor date
  final Set<DateTime> _specificDates = {};   // specific_dates: multi-date picker
  DateTime?       _appointmentDate;          // appointment: date + time
  TimeOfDay?      _appointmentTime;          // appointment: time

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
      case 'specific_dates': return _specificDates.isNotEmpty;
      case 'appointment': return _appointmentDate != null && _appointmentTime != null;
      case 'n_days':  final n = int.tryParse(_nCtrl.text.trim()); return n != null && n >= 1 && _startDate != null;
      default:        return false;
    }
  }

  void _submit() {
    if (!_canSubmit) return;
    switch (_frequency) {
      case 'weekly':
        Navigator.pop(context, {
          'frequency': 'weekly',
          'days': _days.toList(),
          if (_alternateWeek) 'week_anchor_date': DateTime.now().toIso8601String().substring(0, 10),
        });
      case 'monthly':
        Navigator.pop(context, {'frequency': 'monthly', 'month_date': int.parse(_monthCtrl.text.trim())});
      case 'specific_dates':
        Navigator.pop(context, {
          'frequency': 'specific_dates',
          'specific_dates': _specificDates
              .map((d) => d.toIso8601String().substring(0, 10))
              .toList()
              ..sort(),
        });
      case 'appointment':
        final dateTime = DateTime(
          _appointmentDate!.year,
          _appointmentDate!.month,
          _appointmentDate!.day,
          _appointmentTime!.hour,
          _appointmentTime!.minute,
        );
        Navigator.pop(context, {
          'frequency': 'appointment',
          'appointment_date': dateTime.toIso8601String(),
        });
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

  Future<void> _showDayPicker() async {
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Select Day of Month',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 16),
              GridView.count(
                crossAxisCount: 7,
                shrinkWrap: true,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                children: List.generate(31, (i) {
                  final day = i + 1;
                  final selected = _monthCtrl.text.isNotEmpty &&
                      int.tryParse(_monthCtrl.text.trim()) == day;
                  return GestureDetector(
                    onTap: () => Navigator.pop(ctx, day),
                    child: Container(
                      decoration: BoxDecoration(
                        color: selected ? _gold : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: selected ? _gold : Colors.grey.shade300,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          day.toString(),
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: selected ? Colors.white : Colors.black87,
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ],
          ),
        ),
      ),
    );
    if (result != null) {
      setState(() => _monthCtrl.text = result.toString());
    }
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
                child: Wrap(
               
                  children: [
                    _FreqRadio(value: 'weekly',  label: 'Weekly',  freq: _frequency, onTap: () => setState(() => _frequency = 'weekly')),
                    _FreqRadio(value: 'monthly', label: 'Monthly', freq: _frequency, onTap: () => setState(() => _frequency = 'monthly')),
                    _FreqRadio(value: 'specific_dates', label: 'Specific', freq: _frequency, onTap: () => setState(() => _frequency = 'specific_dates')),
                    _FreqRadio(value: 'appointment',  label: 'Appointment',  freq: _frequency, onTap: () => setState(() => _frequency = 'appointment')),
                    _FreqRadio(value: 'n_days',  label: 'N Days',  freq: _frequency, onTap: () => setState(() => _frequency = 'n_days')),
                  ],
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
                const SizedBox(height: 12),
                Row(
                  children: [
                    Checkbox(
                      value: _alternateWeek,
                      activeColor: _gold,
                      onChanged: (v) => setState(() => _alternateWeek = v ?? false),
                    ),
                    const Text('Alternate weeks only',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                  ],
                ),
              ],

              // ── Monthly body ───────────────────────────────────────────────
              if (_frequency == 'monthly') ...[
                const Text('Day of month (1 – 31):',
                    style: TextStyle(fontSize: 12, color: Colors.black54)),
                const SizedBox(height: 8),
                InkWell(
                  onTap: _showDayPicker,
                  borderRadius: BorderRadius.circular(10),
                  child: TextField(
                    controller: _monthCtrl,
                    enabled: false,
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
                      suffixIcon: const Icon(Icons.calendar_today_rounded, color: _gold),
                    ),
                  ),
                ),
              ],

              // ── Specific Dates body ────────────────────────────────────────
              if (_frequency == 'specific_dates') ...[
                const Text('Select specific dates:',
                    style: TextStyle(fontSize: 12, color: Colors.black54)),
                const SizedBox(height: 12),
                _MultiDateCalendar(
                  selectedDates: _specificDates,
                  onChanged: () => setState(() {}),
                ),
              ],

              // ── Appointment body ────────────────────────────────────────────
              if (_frequency == 'appointment') ...[
                const Text('Select date and time:',
                    style: TextStyle(fontSize: 12, color: Colors.black54)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _appointmentDate ?? DateTime.now(),
                            firstDate: DateTime.now(),
                            lastDate: DateTime.now().add(const Duration(days: 365)),
                            builder: (ctx, child) => Theme(
                              data: Theme.of(ctx).copyWith(
                                colorScheme: const ColorScheme.light(primary: _gold),
                              ),
                              child: child!,
                            ),
                          );
                          if (picked != null) setState(() => _appointmentDate = picked);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: _appointmentDate != null ? _gold : Colors.grey.shade400,
                            ),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.calendar_today_rounded, size: 16,
                                  color: _appointmentDate != null ? _gold : Colors.grey),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _appointmentDate != null
                                      ? '${_appointmentDate!.day.toString().padLeft(2,'0')}/'
                                        '${_appointmentDate!.month.toString().padLeft(2,'0')}/'
                                        '${_appointmentDate!.year}'
                                      : 'Pick date',
                                  style: TextStyle(
                                    fontSize: 13, fontWeight: FontWeight.w500,
                                    color: _appointmentDate != null ? Colors.black87 : Colors.grey,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: InkWell(
                        onTap: () async {
                          final picked = await showTimePicker(
                            context: context,
                            initialTime: _appointmentTime ?? TimeOfDay.now(),
                            builder: (ctx, child) => Theme(
                              data: Theme.of(ctx).copyWith(
                                colorScheme: const ColorScheme.light(primary: _gold),
                              ),
                              child: child!,
                            ),
                          );
                          if (!mounted) return;
                          if (picked != null) {
                            // Check if time is in the past (for today's date)
                            final now = DateTime.now();
                            final selectedDate = _appointmentDate ?? now;
                            final isToday = selectedDate.year == now.year &&
                                          selectedDate.month == now.month &&
                                          selectedDate.day == now.day;

                            if (isToday) {
                              final pickedTime = DateTime(now.year, now.month, now.day, picked.hour, picked.minute);
                              if (pickedTime.isBefore(now)) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Cannot select past time'),
                                    backgroundColor: Colors.red,
                                    duration: Duration(seconds: 2),
                                  ),
                                );
                                return;
                              }
                            }
                            setState(() => _appointmentTime = picked);
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: _appointmentTime != null ? _gold : Colors.grey.shade400,
                            ),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.access_time_rounded, size: 16,
                                  color: _appointmentTime != null ? _gold : Colors.grey),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _appointmentTime != null
                                      ? _appointmentTime!.format(context)
                                      : 'Pick time',
                                  style: TextStyle(
                                    fontSize: 13, fontWeight: FontWeight.w500,
                                    color: _appointmentTime != null ? Colors.black87 : Colors.grey,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],

              // ── N Days body ────────────────────────────────────────────────
              if (_frequency == 'n_days') ...[
                const Text('Start Date',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Colors.black87)),
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
                const SizedBox(height: 12),
                const Text('Repeat Every given number(N Days)',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Colors.black87)),
                const SizedBox(height: 6),
                TextField(
                  controller: _nCtrl,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'e.g. 7  →  every 7 days',
                    hintStyle: TextStyle(color: Colors.grey.shade400),
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

// ── Multi-Date Calendar ───────────────────────────────────────────────────────

class _MultiDateCalendar extends StatefulWidget {
  final Set<DateTime> selectedDates;
  final VoidCallback onChanged;

  const _MultiDateCalendar({required this.selectedDates, required this.onChanged});

  @override
  State<_MultiDateCalendar> createState() => _MultiDateCalendarState();
}

class _MultiDateCalendarState extends State<_MultiDateCalendar> {
  static const _gold = Color(0xFFD7BE69);
  late DateTime _displayMonth;

  @override
  void initState() {
    super.initState();
    _displayMonth = DateTime(DateTime.now().year, DateTime.now().month);
  }

  void _prevMonth() => setState(() => _displayMonth = DateTime(_displayMonth.year, _displayMonth.month - 1));
  void _nextMonth() => setState(() => _displayMonth = DateTime(_displayMonth.year, _displayMonth.month + 1));

  bool _isPastDate(DateTime date) => date.isBefore(DateTime.now()) && !_isSameDay(date, DateTime.now());

  bool _isSameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  bool _isToday(DateTime date) => _isSameDay(date, DateTime.now());

  @override
  Widget build(BuildContext context) {
    final firstDay = DateTime(_displayMonth.year, _displayMonth.month, 1);
    final lastDay = DateTime(_displayMonth.year, _displayMonth.month + 1, 0);
    final daysInMonth = lastDay.day;
    final startingWeekday = firstDay.weekday; // 1=Monday, 7=Sunday

    final dayLabels = ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su'];
    final days = <DateTime>[];

    // Empty cells for days before month starts
    for (var i = 1; i < startingWeekday; i++) {
      days.add(DateTime(2000)); // placeholder
    }

    // Days of the month
    for (var i = 1; i <= daysInMonth; i++) {
      days.add(DateTime(_displayMonth.year, _displayMonth.month, i));
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Month header with navigation
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left_rounded),
              onPressed: _prevMonth,
              color: _gold,
              iconSize: 24,
            ),
            Text(
              '${_monthName(_displayMonth.month)} ${_displayMonth.year}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right_rounded),
              onPressed: _nextMonth,
              color: _gold,
              iconSize: 24,
            ),
          ],
        ),
        const SizedBox(height: 8),

        // Day labels
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: dayLabels
              .map((d) => Expanded(
                    child: Center(
                      child: Text(d,
                          style: const TextStyle(
                              fontSize: 11, fontWeight: FontWeight.w600, color: Colors.black54)),
                    ),
                  ))
              .toList(),
        ),
        const SizedBox(height: 4),

        // Calendar grid
        GridView.count(
          crossAxisCount: 7,
          childAspectRatio: 1.2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 2,
          crossAxisSpacing: 2,
          children: days.map((date) {
            if (date.year == 2000) {
              return const SizedBox();
            }

            final isSelected = widget.selectedDates.any((d) => _isSameDay(d, date));
            final isPast = _isPastDate(date);
            final isToday = _isToday(date);

            return GestureDetector(
              onTap: isPast ? null : () {
                setState(() {
                  if (isSelected) {
                    widget.selectedDates.removeWhere((d) => _isSameDay(d, date));
                  } else {
                    widget.selectedDates.add(date);
                  }
                });
                widget.onChanged();
              },
              child: Container(
                decoration: BoxDecoration(
                  color: isSelected ? _gold : (isPast ? Colors.grey.shade100 : Colors.white),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: isToday ? _gold : (isSelected ? _gold : Colors.grey.shade300),
                    width: isToday && !isSelected ? 2 : 1,
                  ),
                ),
                child: Center(
                  child: Text(
                    date.day.toString(),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isSelected ? Colors.white : (isPast ? Colors.grey.shade400 : Colors.black87),
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 12),

        // Selected dates chips
        if (widget.selectedDates.isNotEmpty) ...[
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: () {
                final sorted = widget.selectedDates.toList()..sort((a, b) => a.compareTo(b));
                return sorted.map((date) => Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Chip(
                    label: Text(
                      '${date.day}/${date.month}/${date.year}',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                    backgroundColor: _gold.withValues(alpha: 0.12),
                    side: const BorderSide(color: _gold),
                    onDeleted: () {
                      setState(() => widget.selectedDates.removeWhere((d) => _isSameDay(d, date)));
                      widget.onChanged();
                    },
                  ),
                )).toList();
              }(),
            ),
          ),
        ],
      ],
    );
  }

  String _monthName(int month) => [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ][month - 1];
}

// ── Action button ─────────────────────────────────────────────────────────────

class _ActionBtn extends StatelessWidget {
  final Widget        icon;
  final Color         color;
  final VoidCallback? onTap;
  const _ActionBtn({required this.icon, required this.color, this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: 36, height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
          child: icon,
        ),
      );
}

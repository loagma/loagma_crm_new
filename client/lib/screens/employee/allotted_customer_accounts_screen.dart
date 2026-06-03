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

  bool   _loading = true;
  String _error   = '';

  // {pincode, accounts: [...]}
  List<Map<String, dynamic>> _groups = [];

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

      setState(() { _groups = groups; _loading = false; });
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
    for (final g in _groups) {
      for (final a in (g['accounts'] as List<Map<String, dynamic>>)) {
        final days = a['assignedDays'];
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

  Future<void> _showAssignDayDialog() async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _AssignDayDialog(selectedCount: _selected.length),
    );
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
          IconButton(icon: const Icon(Icons.info_outline_rounded), onPressed: () {}),
          IconButton(icon: const Icon(Icons.refresh_rounded),      onPressed: _load),
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
            return _PincodeSection(
              pincode:   pin,
              total:     accounts.length,
              selected:  selCount,
              expanded:  isOpen,
              onToggle:  () => setState(() => isOpen ? _expanded.remove(pin) : _expanded.add(pin)),
              onSelectAll: () => _selectAllIn(accounts),
              onClearAll:  () => _clearAllIn(accounts),
              onSelectN:   () => _selectNIn(accounts),
              filteredAccounts: filtered,
              selectedKeys: _selected,
              keyOf:     _key,
              onToggleAccount: _toggleSelect,
            );
          }),

        const SizedBox(height: 80),
      ],
    );
  }

  Widget _buildBottomBar() => Container(
    padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
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
          onPressed: _selected.isEmpty ? null : () => setState(() => _selected.clear()),
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
          onPressed: _selected.isEmpty ? null : _showAssignDayDialog,
          icon: const Icon(Icons.save_rounded, size: 15),
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

class _PincodeSection extends StatelessWidget {
  final String                       pincode;
  final int                          total;
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

  const _PincodeSection({
    required this.pincode,
    required this.total,
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
  });

  @override
  Widget build(BuildContext context) {
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
          InkWell(
            onTap: onToggle,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(pincode,
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6, runSpacing: 4,
                          children: [
                            _StatChip(label: 'Existing: $total'),
                            _StatChip(label: 'Assign: $total'),
                            _StatChip(label: 'Remaining: 0'),
                            _StatChip(label: 'Selected: $selected'),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Icon(expanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                      color: Colors.black45),
                ],
              ),
            ),
          ),

          // Expanded body
          if (expanded) ...[
            const Divider(height: 1),
            if (filteredAccounts.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                child: Row(
                  children: [
                    _SelectBtn(icon: Icons.check_box_rounded,              label: 'Select All',  onTap: onSelectAll),
                    const SizedBox(width: 8),
                    _SelectBtn(icon: Icons.check_box_outline_blank_rounded, label: 'Unselect All', onTap: onClearAll),
                    const SizedBox(width: 8),
                    _SelectBtn(icon: Icons.format_list_numbered_rounded,   label: 'Select N',    onTap: onSelectN),
                  ],
                ),
              ),
            ...filteredAccounts.map((a) => _AccountCard(
              account:    a,
              isSelected: selectedKeys.contains(keyOf(a)),
              onCheckTap: () => onToggleAccount(keyOf(a)),
            )),
            if (filteredAccounts.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 18),
                child: Center(
                  child: Text('No accounts found',
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
  final Map<String, dynamic> account;
  final bool                 isSelected;
  final VoidCallback         onCheckTap; // checkbox toggle

  const _AccountCard({
    required this.account,
    required this.isSelected,
    required this.onCheckTap,
  });

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

class _StatChip extends StatelessWidget {
  final String label;
  const _StatChip({required this.label});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Text(label,
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.black87)),
      );
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
  static const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  final Set<String> _selectedDays = {};
  String _frequency = 'Weekly'; // Weekly | Monthly | Recurring Day (After N Days)
  final _nCtrl = TextEditingController();

  @override
  void dispose() {
    _nCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title
            const Text('Assign Day',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 14),

            // Day checkboxes
            ..._days.map((d) => InkWell(
              onTap: () => setState(() =>
                  _selectedDays.contains(d) ? _selectedDays.remove(d) : _selectedDays.add(d)),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    SizedBox(
                      width: 24, height: 24,
                      child: Checkbox(
                        value: _selectedDays.contains(d),
                        activeColor: _gold,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                        onChanged: (v) => setState(() =>
                            v == true ? _selectedDays.add(d) : _selectedDays.remove(d)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(d, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
            )),

            const Divider(height: 20),

            // Frequency radio buttons
            RadioGroup<String>(
              groupValue: _frequency,
              onChanged: (v) { if (v != null) setState(() => _frequency = v); },
              child: Column(
                children: ['Weekly', 'Monthly', 'Recurring Day (After N Days)'].map((f) =>
                  InkWell(
                    onTap: () => setState(() => _frequency = f),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 24, height: 24,
                            child: Radio<String>(value: f, activeColor: _gold),
                          ),
                          const SizedBox(width: 12),
                          Text(f, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                        ],
                      ),
                    ),
                  ),
                ).toList(),
              ),
            ),

            // N days input (only for Recurring)
            if (_frequency == 'Recurring Day (After N Days)') ...[
              const SizedBox(height: 8),
              TextField(
                controller: _nCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  hintText: 'Enter number of days',
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

            const SizedBox(height: 16),

            // Actions
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel', style: TextStyle(color: Colors.grey, fontSize: 14)),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _gold,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                  ),
                  onPressed: () {
                    if (_selectedDays.isEmpty) return;
                    Navigator.pop(context, {
                      'days':      _selectedDays.toList(),
                      'frequency': _frequency,
                      if (_frequency == 'Recurring Day (After N Days)')
                        'n': int.tryParse(_nCtrl.text.trim()),
                    });
                  },
                  child: const Text('Ok', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ],
        ),
      ),
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

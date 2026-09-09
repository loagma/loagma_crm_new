import 'dart:async';

import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';

import '../../services/api_service.dart';

/// Admin: pin a single `user` customer to a single employee.
///
/// Search a customer → tap → popup to choose an employee (or reassign / remove).
/// The assignment is stored in `customer_assign_crm` and the employee then sees
/// that customer merged into their Allotted Customers list.
class CustomerAssignScreen extends StatefulWidget {
  const CustomerAssignScreen({super.key});

  @override
  State<CustomerAssignScreen> createState() => _CustomerAssignScreenState();
}

class _CustomerAssignScreenState extends State<CustomerAssignScreen> {
  static const _gold = Color(0xFFD7BE69);

  final _searchCtrl = TextEditingController();
  String _query = '';
  Timer? _debounce;

  bool _loading = false;
  List<Map<String, dynamic>> _customers = [];

  // Multi-select ("assign many customers to one employee").
  bool _selectMode = false;
  final Set<int> _selected = {};

  // Assignable staff (salesman + telecaller).
  List<Map<String, dynamic>> _staff = [];

  // mobile → employee record (all roles).
  Map<String, Map<String, dynamic>> _staffByMobile = {};

  // customer_userid → assignment row (from /customer-assign).
  Map<int, Map<String, dynamic>> _assignByCustomer = {};

  // pincode → { employee_mobile → set of area names covering it }.
  // A customer whose pincode is here is ALREADY reachable by that employee
  // through their area allotment — a direct assignment would be redundant.
  Map<String, Map<String, Set<String>>> _areaCoverByPincode = {};

  @override
  void initState() {
    super.initState();
    _loadMeta();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  // Live search-as-you-type: rebuild for the clear button, then run the
  // (case-insensitive, server-side LIKE) search 300ms after the last keystroke.
  void _onSearchChanged(String value) {
    setState(() {});
    _debounce?.cancel();
    if (value.trim().isEmpty) {
      setState(() {
        _customers = [];
        _query = '';
        _loading = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), _search);
  }

  Future<void> _loadMeta() async {
    final staffFuture = ApiService.getEmployees(perPage: 500);
    final assignsFuture = ApiService.getCustomerAssigns();
    final areasFuture = ApiService.getAreas(perPage: 500);
    final areaAssignsFuture = ApiService.getAllAreaAssigns();

    final staffList = await staffFuture;
    final assigns = await assignsFuture;
    final areasRes = await areasFuture;
    final areaAssigns = await areaAssignsFuture;
    if (!mounted) return;

    // area id → {name, pincodes}
    final areasRaw = (areasRes['data'] as List?) ?? [];
    final areaById = <int, Map<String, dynamic>>{
      for (final a in areasRaw)
        if (int.tryParse('${(a as Map)['id'] ?? ''}') != null)
          int.parse('${a['id']}'): {
            'name': (a['area_name'] ?? '').toString(),
            'pincodes': ((a['pincodes'] as List?) ?? []).map((p) => p.toString().trim()).toList(),
          },
    };

    // pincode → { employee_mobile → {area names} }
    final cover = <String, Map<String, Set<String>>>{};
    for (final aa in areaAssigns) {
      final empId = (aa['employee_id'] ?? '').toString();
      if (empId.isEmpty) continue;
      final ids = aa['area_ids'];
      if (ids is! List) continue;
      for (final rawId in ids) {
        final id = int.tryParse(rawId.toString());
        final area = id == null ? null : areaById[id];
        if (area == null) continue;
        final areaName = (area['name'] as String?)?.isNotEmpty == true ? area['name'] as String : 'Area $id';
        for (final pin in (area['pincodes'] as List)) {
          final key = pin.toString().trim();
          if (key.isEmpty) continue;
          cover.putIfAbsent(key, () => {}).putIfAbsent(empId, () => <String>{}).add(areaName);
        }
      }
    }

    setState(() {
      _staffByMobile = {
        for (final e in staffList) (e['mobile'] ?? '').toString(): Map<String, dynamic>.from(e),
      };
      _staff = staffList.where((e) {
        final r = (e['role'] ?? '').toString().trim().toLowerCase();
        return r == 'salesman' || r == 'telecaller';
      }).toList();
      _assignByCustomer = {
        for (final a in assigns)
          if (a['customer_userid'] != null)
            (a['customer_userid'] as num).toInt(): Map<String, dynamic>.from(a),
      };
      _areaCoverByPincode = cover;
    });
  }

  // Employees who already reach a customer at [pincode] via their area allotment.
  // Returns [{mobile, name, areas}].
  List<Map<String, String>> _areaCoverersFor(String pincode) {
    final m = _areaCoverByPincode[pincode.trim()];
    if (m == null) return [];
    return m.entries.map((e) => {
          'mobile': e.key,
          'name': (_staffByMobile[e.key]?['name'] ?? e.key).toString(),
          'role': (_staffByMobile[e.key]?['role'] ?? '').toString(),
          'areas': e.value.join(', '),
        }).toList();
  }

  Future<void> _refreshAssigns() async {
    final assigns = await ApiService.getCustomerAssigns();
    if (!mounted) return;
    setState(() {
      _assignByCustomer = {
        for (final a in assigns)
          if (a['customer_userid'] != null)
            (a['customer_userid'] as num).toInt(): Map<String, dynamic>.from(a),
      };
    });
  }

  Future<void> _search() async {
    final q = _searchCtrl.text.trim();
    if (q.isEmpty) {
      setState(() {
        _customers = [];
        _query = '';
      });
      return;
    }
    setState(() {
      _loading = true;
      _query = q;
    });
    final res = await ApiService.getCustomers(q: q);
    if (!mounted) return;
    // Ignore a stale response if the user has since typed something else.
    if (_searchCtrl.text.trim() != q) return;
    setState(() {
      _customers = res;
      _loading = false;
    });
  }

  int _useridOf(Map<String, dynamic> c) =>
      int.tryParse('${c['userid'] ?? ''}') ?? 0;

  String _nameOf(Map<String, dynamic> c) {
    final shop = (c['shop_name'] ?? '').toString().trim();
    if (shop.isNotEmpty) return shop;
    final name = (c['name'] ?? '').toString().trim();
    return name.isNotEmpty ? name : 'Customer';
  }

  Future<void> _openAssignSheet(
      Map<String, dynamic> customer, List<Map<String, String>> coverers) async {
    final userid = _useridOf(customer);
    if (userid == 0) return;

    // mobile → area label, for the staff picker to flag redundant picks.
    final coverByMobile = <String, String>{
      for (final c in coverers) c['mobile']!: c['areas'] ?? '',
    };

    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _AssignSheet(
        customerName: _nameOf(customer),
        customerUserid: userid,
        staff: _staff,
        current: _assignByCustomer[userid],
        areaCoverByMobile: coverByMobile,
      ),
    );

    if (changed == true) await _refreshAssigns();
  }

  void _toggleSelectMode() {
    setState(() {
      _selectMode = !_selectMode;
      if (!_selectMode) _selected.clear();
    });
  }

  void _toggleSelected(int userid) {
    if (userid == 0) return;
    setState(() {
      _selected.contains(userid) ? _selected.remove(userid) : _selected.add(userid);
    });
  }

  Future<void> _openBulkAssignSheet() async {
    if (_selected.isEmpty) return;

    // For each employee mobile, how many of the selected customers they
    // already reach through their area allotment.
    final selectedCustomers =
        _customers.where((c) => _selected.contains(_useridOf(c))).toList();
    final coverCount = <String, int>{};
    for (final c in selectedCustomers) {
      for (final cov in _areaCoverersFor((c['pincode'] ?? '').toString())) {
        coverCount[cov['mobile']!] = (coverCount[cov['mobile']] ?? 0) + 1;
      }
    }

    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _BulkAssignSheet(
        staff: _staff,
        userids: _selected.toList(),
        areaCoverCountByMobile: coverCount,
      ),
    );

    if (changed == true) {
      setState(() {
        _selectMode = false;
        _selected.clear();
      });
      await _refreshAssigns();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: Text(_selectMode ? '${_selected.length} selected' : 'Customer Assign'),
        backgroundColor: _gold,
        foregroundColor: Colors.white,
        actions: [
          if (_customers.isNotEmpty)
            TextButton.icon(
              onPressed: _toggleSelectMode,
              icon: Icon(_selectMode ? Icons.close_rounded : Icons.checklist_rounded,
                  color: Colors.white, size: 18),
              label: Text(_selectMode ? 'Cancel' : 'Select',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(20),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
                _selectMode
                    ? 'Pick customers, then assign them all to one employee'
                    : 'Assign customers to an employee',
                style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.85))),
          ),
        ),
      ),
      bottomNavigationBar: (_selectMode && _selected.isNotEmpty)
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                child: ElevatedButton.icon(
                  onPressed: _openBulkAssignSheet,
                  icon: const Icon(Icons.assignment_ind_rounded, size: 18),
                  label: Text('Assign ${_selected.length} customer${_selected.length == 1 ? '' : 's'}'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _gold,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(46),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            )
          : null,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: TextField(
              controller: _searchCtrl,
              textInputAction: TextInputAction.search,
              onChanged: _onSearchChanged,
              onSubmitted: (_) {
                _debounce?.cancel();
                _search();
              },
              decoration: InputDecoration(
                hintText: 'Search customer by name, shop or phone…',
                prefixIcon: const Icon(Icons.search_rounded, color: _gold),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close_rounded, size: 18),
                        onPressed: () {
                          _searchCtrl.clear();
                          _onSearchChanged('');
                        },
                      )
                    : null,
                isDense: true,
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade200)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _gold)),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 4),
            child: Row(
              children: [
                Text(
                  _query.isEmpty
                      ? 'Type to search — results update as you type'
                      : '${_customers.length} result${_customers.length == 1 ? '' : 's'} for "$_query"',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                Text('${_assignByCustomer.length} assigned',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          if (_loading) const LinearProgressIndicator(color: _gold, minHeight: 2),
          Expanded(
            child: (_loading && _customers.isEmpty)
                ? const Center(child: CircularProgressIndicator(color: _gold))
                : _customers.isEmpty
                    ? _emptyState()
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(12, 6, 12, 80),
                        itemCount: _customers.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (_, i) {
                          final c = _customers[i];
                          final userid = _useridOf(c);
                          final assign = _assignByCustomer[userid];
                          final coverers = _areaCoverersFor((c['pincode'] ?? '').toString());
                          return _CustomerCard(
                            name: _nameOf(c),
                            person: (c['name'] ?? '').toString(),
                            phone: (c['contactno'] ?? '').toString(),
                            pincode: (c['pincode'] ?? '').toString(),
                            city: (c['city'] ?? '').toString(),
                            assigneeName: assign?['employee_name']?.toString(),
                            assigneeRole: assign?['employee_role']?.toString(),
                            areaCoverers: coverers,
                            selectMode: _selectMode,
                            selected: _selected.contains(userid),
                            onTap: _selectMode
                                ? () => _toggleSelected(userid)
                                : () => _openAssignSheet(c, coverers),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_query.isEmpty ? Icons.person_search_rounded : Icons.search_off_rounded,
                size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text(
              _query.isEmpty
                  ? 'Search a customer to assign'
                  : 'No customers match "$_query"',
              style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
            ),
          ],
        ),
      );
}

class _CustomerCard extends StatelessWidget {
  final String name;
  final String person;
  final String phone;
  final String pincode;
  final String city;
  final String? assigneeName;
  final String? assigneeRole;
  final List<Map<String, String>> areaCoverers;
  final bool selectMode;
  final bool selected;
  final VoidCallback onTap;

  const _CustomerCard({
    required this.name,
    required this.person,
    required this.phone,
    required this.pincode,
    required this.city,
    required this.assigneeName,
    required this.assigneeRole,
    required this.areaCoverers,
    this.selectMode = false,
    this.selected = false,
    required this.onTap,
  });

  static const _gold = Color(0xFFD7BE69);

  @override
  Widget build(BuildContext context) {
    final assigned = (assigneeName ?? '').isNotEmpty;
    return GestureDetector(
      onTap: onTap,
      child: Card(
        // Opaque colours only — a translucent fill composites with the card
        // shadow into a muddy grey that washes the text out.
        color: selected ? const Color(0xFFFBF4DC) : Colors.white,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        elevation: 1.5,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: selected ? const BorderSide(color: _gold, width: 1.5) : BorderSide.none,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              if (selectMode) ...[
                Icon(selected ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                    color: selected ? _gold : Colors.grey.shade400),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF212121))),
                    const SizedBox(height: 2),
                    Text(
                      [
                        if (person.isNotEmpty) person,
                        if (phone.isNotEmpty) phone,
                        if (pincode.isNotEmpty) 'Pin $pincode',
                        if (city.isNotEmpty) city,
                      ].join('  •  '),
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: assigned ? _gold.withValues(alpha: 0.12) : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: assigned ? _gold.withValues(alpha: 0.35) : Colors.grey.shade300),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(assigned ? Icons.assignment_ind_rounded : Icons.person_off_rounded,
                              size: 12, color: assigned ? const Color(0xFFB89A3E) : Colors.grey.shade400),
                          const SizedBox(width: 4),
                          Text(
                            assigned
                                ? 'Assigned to $assigneeName'
                                    '${(assigneeRole ?? '').isNotEmpty ? ' (${assigneeRole!.replaceAll('_', ' ')})' : ''}'
                                : 'Not assigned',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                              color: assigned ? const Color(0xFFB89A3E) : Colors.grey.shade500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (areaCoverers.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE8F5E9),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFA5D6A7)),
                        ),
                        child: Text(
                          'Already in area of: '
                          '${areaCoverers.map((c) => '${c['name']} (${c['areas']})').join(', ')}',
                          style: const TextStyle(
                              fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFF2E7D32)),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (!selectMode)
                const Icon(Icons.chevron_right_rounded, color: Colors.grey, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Assign / reassign / remove sheet ────────────────────────────────────────

class _AssignSheet extends StatefulWidget {
  final String customerName;
  final int customerUserid;
  final List<Map<String, dynamic>> staff;
  final Map<String, dynamic>? current;
  // employee_mobile → area label(s) that already cover this customer's pincode.
  final Map<String, String> areaCoverByMobile;

  const _AssignSheet({
    required this.customerName,
    required this.customerUserid,
    required this.staff,
    required this.current,
    required this.areaCoverByMobile,
  });

  @override
  State<_AssignSheet> createState() => _AssignSheetState();
}

class _AssignSheetState extends State<_AssignSheet> {
  static const _gold = Color(0xFFD7BE69);

  final _searchCtrl = TextEditingController();
  String _q = '';
  bool _saving = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _filtered {
    if (_q.isEmpty) return widget.staff;
    final q = _q.toLowerCase();
    return widget.staff.where((e) {
      return (e['name'] ?? '').toString().toLowerCase().contains(q) ||
          (e['mobile'] ?? '').toString().contains(q);
    }).toList();
  }

  Future<void> _assign(String mobile) async {
    // Picking someone who already reaches this customer through their area
    // allotment is redundant — confirm before creating the direct pin.
    final areas = widget.areaCoverByMobile[mobile];
    if (areas != null && areas.isNotEmpty) {
      final name = widget.staff.firstWhere(
        (e) => (e['mobile'] ?? '').toString() == mobile,
        orElse: () => const {},
      )['name']?.toString() ?? mobile;
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: const Text('Already covered by area',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          content: Text(
            'This customer already falls under $name\'s assigned area ($areas), '
            'so they can already see this customer. A direct assignment is not needed.\n\n'
            'Assign directly anyway?',
            style: const TextStyle(fontSize: 13),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel', style: TextStyle(color: Colors.grey))),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: _gold, foregroundColor: Colors.white),
              child: const Text('Assign anyway'),
            ),
          ],
        ),
      );
      if (proceed != true) return;
    }

    setState(() => _saving = true);
    final ok = await ApiService.assignCustomer(widget.customerUserid, mobile);
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) {
      Fluttertoast.showToast(
          msg: 'Customer assigned', backgroundColor: const Color(0xFF2E7D32), textColor: Colors.white);
      Navigator.pop(context, true);
    } else {
      Fluttertoast.showToast(
          msg: 'Failed to assign. Try again.', backgroundColor: Colors.red, textColor: Colors.white);
    }
  }

  Future<void> _remove() async {
    setState(() => _saving = true);
    final ok = await ApiService.unassignCustomer(widget.customerUserid);
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) {
      Fluttertoast.showToast(
          msg: 'Assignment removed', backgroundColor: Colors.orange, textColor: Colors.white);
      Navigator.pop(context, true);
    } else {
      Fluttertoast.showToast(
          msg: 'Failed to remove. Try again.', backgroundColor: Colors.red, textColor: Colors.white);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentMobile = widget.current?['employee_mobile']?.toString();
    final currentName = widget.current?['employee_name']?.toString();

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.92,
        minChildSize: 0.5,
        builder: (context, scrollCtrl) => Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Assign customer',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(widget.customerName,
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                  if (currentName != null && currentName.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: _gold.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: _gold.withValues(alpha: 0.35)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.assignment_ind_rounded, size: 16, color: Color(0xFFB89A3E)),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text('Currently assigned to $currentName',
                                style: const TextStyle(
                                    fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFFB89A3E))),
                          ),
                          TextButton(
                            onPressed: _saving ? null : _remove,
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.red,
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              minimumSize: const Size(0, 32),
                            ),
                            child: const Text('Remove', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (widget.areaCoverByMobile.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8F5E9),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFA5D6A7)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.location_on_rounded, size: 15, color: Color(0xFF2E7D32)),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Already reachable via area allotment: '
                              '${widget.areaCoverByMobile.entries.map((e) {
                                final n = widget.staff.firstWhere(
                                  (s) => (s['mobile'] ?? '').toString() == e.key,
                                  orElse: () => const {},
                                )['name']?.toString() ?? e.key;
                                return '$n (${e.value})';
                              }).join(', ')}',
                              style: const TextStyle(
                                  fontSize: 11.5, fontWeight: FontWeight.w600, color: Color(0xFF2E7D32)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: TextField(
                controller: _searchCtrl,
                onChanged: (v) => setState(() => _q = v.trim()),
                decoration: InputDecoration(
                  hintText: 'Search salesman / telecaller…',
                  prefixIcon: const Icon(Icons.search_rounded, color: _gold, size: 20),
                  isDense: true,
                  filled: true,
                  fillColor: const Color(0xFFF5F5F5),
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                ),
              ),
            ),
            if (_saving) const LinearProgressIndicator(color: _gold, minHeight: 2),
            Expanded(
              child: _filtered.isEmpty
                  ? Center(
                      child: Text('No staff found', style: TextStyle(color: Colors.grey.shade500)),
                    )
                  : ListView.separated(
                      controller: scrollCtrl,
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                      itemCount: _filtered.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 6),
                      itemBuilder: (_, i) {
                        final e = _filtered[i];
                        final mobile = (e['mobile'] ?? '').toString();
                        final role = (e['role'] ?? '').toString();
                        final isCurrent = mobile == currentMobile;
                        final coversViaArea = (widget.areaCoverByMobile[mobile] ?? '').isNotEmpty;
                        return ListTile(
                          tileColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                            side: BorderSide(
                                color: isCurrent ? _gold : Colors.grey.shade200,
                                width: isCurrent ? 1.5 : 1),
                          ),
                          leading: CircleAvatar(
                            backgroundColor: _gold.withValues(alpha: 0.15),
                            child: Text(
                              (e['name'] ?? '?').toString().trim().isNotEmpty
                                  ? (e['name'] as String).trim()[0].toUpperCase()
                                  : '?',
                              style: const TextStyle(color: Color(0xFFB89A3E), fontWeight: FontWeight.bold),
                            ),
                          ),
                          title: Text((e['name'] ?? mobile).toString(),
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${role.replaceAll('_', ' ')}${mobile.isNotEmpty ? '  •  $mobile' : ''}',
                                style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                              ),
                              if (coversViaArea)
                                Text(
                                  'Already covers via area (${widget.areaCoverByMobile[mobile]})',
                                  style: const TextStyle(
                                      fontSize: 10.5, fontWeight: FontWeight.w600, color: Color(0xFF2E7D32)),
                                ),
                            ],
                          ),
                          trailing: isCurrent
                              ? const Icon(Icons.check_circle_rounded, color: _gold)
                              : coversViaArea
                                  ? const Icon(Icons.location_on_rounded, color: Color(0xFF2E7D32), size: 20)
                                  : const Icon(Icons.chevron_right_rounded, color: Colors.grey),
                          onTap: (_saving || isCurrent || mobile.isEmpty) ? null : () => _assign(mobile),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Bulk assign sheet (many customers → one employee) ───────────────────────

class _BulkAssignSheet extends StatefulWidget {
  final List<Map<String, dynamic>> staff;
  final List<int> userids;
  // employee_mobile → how many of the selected customers they already cover by area.
  final Map<String, int> areaCoverCountByMobile;

  const _BulkAssignSheet({
    required this.staff,
    required this.userids,
    required this.areaCoverCountByMobile,
  });

  @override
  State<_BulkAssignSheet> createState() => _BulkAssignSheetState();
}

class _BulkAssignSheetState extends State<_BulkAssignSheet> {
  static const _gold = Color(0xFFD7BE69);

  final _searchCtrl = TextEditingController();
  String _q = '';
  bool _saving = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _filtered {
    if (_q.isEmpty) return widget.staff;
    final q = _q.toLowerCase();
    return widget.staff.where((e) =>
        (e['name'] ?? '').toString().toLowerCase().contains(q) ||
        (e['mobile'] ?? '').toString().contains(q)).toList();
  }

  Future<void> _assign(String mobile, String name) async {
    final total = widget.userids.length;
    final covered = widget.areaCoverCountByMobile[mobile] ?? 0;

    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Confirm assignment',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        content: Text(
          'Assign $total customer${total == 1 ? '' : 's'} to $name?'
          '${covered > 0 ? '\n\n$covered of them are already in this employee\'s area and don\'t strictly need a direct pin.' : ''}',
          style: const TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: _gold, foregroundColor: Colors.white),
            child: const Text('Assign'),
          ),
        ],
      ),
    );
    if (proceed != true) return;

    setState(() => _saving = true);
    final n = await ApiService.assignCustomersBulk(widget.userids, mobile);
    if (!mounted) return;
    setState(() => _saving = false);
    if (n != null) {
      Fluttertoast.showToast(
          msg: '$n customer${n == 1 ? '' : 's'} assigned to $name',
          backgroundColor: const Color(0xFF2E7D32), textColor: Colors.white);
      Navigator.pop(context, true);
    } else {
      Fluttertoast.showToast(
          msg: 'Failed to assign. Try again.', backgroundColor: Colors.red, textColor: Colors.white);
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.userids.length;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.92,
        minChildSize: 0.5,
        builder: (context, scrollCtrl) => Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Assign $total customer${total == 1 ? '' : 's'} to…',
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: TextField(
                controller: _searchCtrl,
                onChanged: (v) => setState(() => _q = v.trim()),
                decoration: InputDecoration(
                  hintText: 'Search salesman / telecaller…',
                  prefixIcon: const Icon(Icons.search_rounded, color: _gold, size: 20),
                  isDense: true,
                  filled: true,
                  fillColor: const Color(0xFFF5F5F5),
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                ),
              ),
            ),
            if (_saving) const LinearProgressIndicator(color: _gold, minHeight: 2),
            Expanded(
              child: _filtered.isEmpty
                  ? Center(child: Text('No staff found', style: TextStyle(color: Colors.grey.shade500)))
                  : ListView.separated(
                      controller: scrollCtrl,
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                      itemCount: _filtered.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 6),
                      itemBuilder: (_, i) {
                        final e = _filtered[i];
                        final mobile = (e['mobile'] ?? '').toString();
                        final role = (e['role'] ?? '').toString();
                        final name = (e['name'] ?? mobile).toString();
                        final covered = widget.areaCoverCountByMobile[mobile] ?? 0;
                        return ListTile(
                          tileColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                            side: BorderSide(color: Colors.grey.shade200),
                          ),
                          leading: CircleAvatar(
                            backgroundColor: _gold.withValues(alpha: 0.15),
                            child: Text(
                              name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : '?',
                              style: const TextStyle(color: Color(0xFFB89A3E), fontWeight: FontWeight.bold),
                            ),
                          ),
                          title: Text(name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${role.replaceAll('_', ' ')}${mobile.isNotEmpty ? '  •  $mobile' : ''}',
                                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                              if (covered > 0)
                                Text('Already covers $covered of these via area',
                                    style: const TextStyle(
                                        fontSize: 10.5, fontWeight: FontWeight.w600, color: Color(0xFF2E7D32))),
                            ],
                          ),
                          trailing: const Icon(Icons.chevron_right_rounded, color: Colors.grey),
                          onTap: (_saving || mobile.isEmpty) ? null : () => _assign(mobile, name),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

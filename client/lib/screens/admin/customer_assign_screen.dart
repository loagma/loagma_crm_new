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

  bool _loading = false;
  List<Map<String, dynamic>> _customers = [];

  // Assignable staff (salesman + telecaller).
  List<Map<String, dynamic>> _staff = [];

  // customer_userid → assignment row (from /customer-assign).
  Map<int, Map<String, dynamic>> _assignByCustomer = {};

  @override
  void initState() {
    super.initState();
    _loadMeta();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadMeta() async {
    final staffFuture = ApiService.getEmployees(perPage: 500);
    final assignsFuture = ApiService.getCustomerAssigns();

    final staffList = await staffFuture;
    final assigns = await assignsFuture;
    if (!mounted) return;

    setState(() {
      _staff = staffList.where((e) {
        final r = (e['role'] ?? '').toString().trim().toLowerCase();
        return r == 'salesman' || r == 'telecaller';
      }).toList();
      _assignByCustomer = {
        for (final a in assigns)
          if (a['customer_userid'] != null)
            (a['customer_userid'] as num).toInt(): Map<String, dynamic>.from(a),
      };
    });
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

  Future<void> _openAssignSheet(Map<String, dynamic> customer) async {
    final userid = _useridOf(customer);
    if (userid == 0) return;

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
      ),
    );

    if (changed == true) await _refreshAssigns();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text('Customer Assign'),
        backgroundColor: _gold,
        foregroundColor: Colors.white,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(20),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text('Assign one customer to one employee',
                style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.85))),
          ),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: TextField(
              controller: _searchCtrl,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _search(),
              decoration: InputDecoration(
                hintText: 'Search customer by name, shop or phone…',
                prefixIcon: const Icon(Icons.search_rounded, color: _gold),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close_rounded, size: 18),
                        onPressed: () {
                          _searchCtrl.clear();
                          _search();
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
                ElevatedButton.icon(
                  onPressed: _search,
                  icon: const Icon(Icons.search_rounded, size: 16),
                  label: const Text('Search'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _gold,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
                const Spacer(),
                Text('${_assignByCustomer.length} assigned',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          Expanded(
            child: _loading
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
                          return _CustomerCard(
                            name: _nameOf(c),
                            person: (c['name'] ?? '').toString(),
                            phone: (c['contactno'] ?? '').toString(),
                            pincode: (c['pincode'] ?? '').toString(),
                            city: (c['city'] ?? '').toString(),
                            assigneeName: assign?['employee_name']?.toString(),
                            assigneeRole: assign?['employee_role']?.toString(),
                            onTap: () => _openAssignSheet(c),
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
  final VoidCallback onTap;

  const _CustomerCard({
    required this.name,
    required this.person,
    required this.phone,
    required this.pincode,
    required this.city,
    required this.assigneeName,
    required this.assigneeRole,
    required this.onTap,
  });

  static const _gold = Color(0xFFD7BE69);

  @override
  Widget build(BuildContext context) {
    final assigned = (assigneeName ?? '').isNotEmpty;
    return GestureDetector(
      onTap: onTap,
      child: Card(
        color: Colors.white,
        margin: EdgeInsets.zero,
        elevation: 1.5,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(
                      [
                        if (person.isNotEmpty) person,
                        if (phone.isNotEmpty) phone,
                        if (pincode.isNotEmpty) 'Pin $pincode',
                        if (city.isNotEmpty) city,
                      ].join('  •  '),
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
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
                  ],
                ),
              ),
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

  const _AssignSheet({
    required this.customerName,
    required this.customerUserid,
    required this.staff,
    required this.current,
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
                          subtitle: Text(
                            '${role.replaceAll('_', ' ')}${mobile.isNotEmpty ? '  •  $mobile' : ''}',
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                          ),
                          trailing: isCurrent
                              ? const Icon(Icons.check_circle_rounded, color: _gold)
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

import 'package:flutter/material.dart';

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
  String _query = '';

  // Expanded pincode sections
  final Set<String> _expanded = {'500001'};

  // Selected customer codes
  final Set<String> _selected = {};

  // ── Dummy data ──────────────────────────────────────────────────────────────

  static const _allDays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  final List<Map<String, dynamic>> _pincodes = [
    {
      'pincode': '482002',
      'existing': 0,
      'assign': 0,
      'remaining': 0,
      'dayBreak': {'Mon': 0, 'Tue': 0, 'Wed': 0, 'Thu': 0, 'Fri': 0, 'Sat': 0, 'Sun': 0},
      'customers': <Map<String, dynamic>>[],
    },
    {
      'pincode': '500001',
      'existing': 17,
      'assign': 17,
      'remaining': 0,
      'dayBreak': {'Mon': 5, 'Tue': 6, 'Wed': 6, 'Thu': 10, 'Fri': 6, 'Sat': 5, 'Sun': 10},
      'customers': [
        {'code': '00026040060', 'name': 'Abids Daily Needs',      'salesman': 'Sanjay Gupta',  'address': 'Shop 45, Station Road',    'area': 'Abids', 'phone': '9848101002', 'days': ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'], 'active': ['Thu'], 'next': 'Thu 04/06/2026'},
        {'code': '00026040052', 'name': 'Abids Provision Mart 13','salesman': 'Sameer Uddin',  'address': 'Shop 13, Station Road',    'area': 'Abids', 'phone': '9848101005', 'days': ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'], 'active': ['Mon'], 'next': 'Mon 01/06/2026'},
        {'code': '00026040048', 'name': 'Star Kirana Centre',     'salesman': 'Rajiv Menon',   'address': 'Kothi, MG Road',           'area': 'Abids', 'phone': '9848101010', 'days': ['Mon','Wed','Fri'],                         'active': ['Mon'], 'next': 'Mon 01/06/2026'},
        {'code': '00026040044', 'name': 'Lal Darwaza Store',      'salesman': 'Priya Shah',    'address': 'Lal Darwaza Junction',     'area': 'Abids', 'phone': '9848101018', 'days': ['Tue','Thu','Sat'],                         'active': ['Thu'], 'next': 'Thu 04/06/2026'},
        {'code': '00026040040', 'name': 'Regal Provisions',       'salesman': 'Aditya Kumar',  'address': 'Near Clock Tower',         'area': 'Abids', 'phone': '9848101025', 'days': ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'], 'active': ['Tue'], 'next': 'Tue 02/06/2026'},
      ],
    },
    {
      'pincode': '500095',
      'existing': 15,
      'assign': 15,
      'remaining': 0,
      'dayBreak': {'Mon': 3, 'Tue': 5, 'Wed': 4, 'Thu': 4, 'Fri': 4, 'Sat': 3, 'Sun': 5},
      'customers': [
        {'code': '00026040036', 'name': 'Sultan Bazar Mart',      'salesman': 'Deepak Rao',    'address': 'Sultan Bazar Main St',     'area': 'Sultan Bazar', 'phone': '9848101030', 'days': ['Mon','Wed','Fri','Sun'], 'active': ['Mon'], 'next': 'Mon 01/06/2026'},
        {'code': '00026040032', 'name': 'City Light General',     'salesman': 'Sunita Iyer',   'address': 'Beside Post Office',       'area': 'Sultan Bazar', 'phone': '9848101038', 'days': ['Tue','Thu','Sat'],       'active': ['Tue'], 'next': 'Tue 02/06/2026'},
        {'code': '00026040028', 'name': 'Everest Kirana',         'salesman': 'Mohan Das',     'address': 'Old Bridge Road, No.4',    'area': 'Sultan Bazar', 'phone': '9848101044', 'days': ['Mon','Tue','Wed'],       'active': ['Mon'], 'next': 'Mon 01/06/2026'},
      ],
    },
    {
      'pincode': '500028',
      'existing': 17,
      'assign': 15,
      'remaining': 2,
      'dayBreak': {'Mon': 5, 'Tue': 4, 'Wed': 4, 'Thu': 3, 'Fri': 3, 'Sat': 4, 'Sun': 7},
      'customers': [
        {'code': '00026040020', 'name': 'Himayat Nagar Stores',   'salesman': 'Kiran Patel',   'address': 'Himayat Nagar X Roads',    'area': 'Himayat Nagar', 'phone': '9848101055', 'days': ['Mon','Thu','Sun'], 'active': ['Mon'], 'next': 'Mon 01/06/2026'},
        {'code': '00026040016', 'name': 'Classic Provisions',     'salesman': 'Nilesh Joshi',  'address': 'Road No. 5, Banjara',      'area': 'Banjara Hills', 'phone': '9848101062', 'days': ['Tue','Fri'],      'active': ['Tue'], 'next': 'Tue 02/06/2026'},
        {'code': '00026040012', 'name': 'Dhan Shree Traders',     'salesman': 'Ankit Mehta',   'address': 'Near Water Tank, Lane 2',  'area': 'Himayat Nagar', 'phone': '9848101070', 'days': ['Sun'],            'active': ['Sun'], 'next': 'Sun 07/06/2026'},
        {'code': '00026040008', 'name': 'Sree Balaji Stores',     'salesman': 'Pooja Reddy',   'address': 'Adj. Petrol Bunk',         'area': 'Banjara Hills', 'phone': '9848101078', 'days': ['Mon','Wed','Fri'], 'active': ['Mon'], 'next': 'Mon 01/06/2026'},
      ],
    },
  ];

  // ── Computed ─────────────────────────────────────────────────────────────────

  int get _totalAccounts =>
      _pincodes.fold(0, (s, p) => s + (p['customers'] as List).length);

  Map<String, int> get _globalDayBreak {
    final m = {for (final d in _allDays) d: 0};
    for (final p in _pincodes) {
      final db = p['dayBreak'] as Map<String, dynamic>;
      for (final d in _allDays) {
        m[d] = (m[d] ?? 0) + ((db[d] as int?) ?? 0);
      }
    }
    return m;
  }

  List<Map<String, dynamic>> _filteredCustomers(List customers) {
    if (_query.isEmpty) return List<Map<String, dynamic>>.from(customers);
    final q = _query.toLowerCase();
    return customers.where((c) {
      final cMap = c as Map<String, dynamic>;
      return (cMap['name'] as String).toLowerCase().contains(q) ||
          (cMap['phone'] as String).contains(q) ||
          (cMap['code'] as String).contains(q);
    }).map((c) => c as Map<String, dynamic>).toList();
  }

  int get _selectedDayCount {
    if (_selected.isEmpty) return 0;
    final days = <String>{};
    for (final p in _pincodes) {
      for (final c in (p['customers'] as List)) {
        final cMap = c as Map<String, dynamic>;
        if (_selected.contains(cMap['code'])) {
          days.addAll((cMap['active'] as List).cast<String>());
        }
      }
    }
    return days.length;
  }

  void _toggleCustomer(String code) =>
      setState(() => _selected.contains(code) ? _selected.remove(code) : _selected.add(code));

  void _selectAll(List customers) => setState(() {
        for (final c in customers) {
          _selected.add((c as Map<String, dynamic>)['code'] as String);
        }
      });

  void _selectNone(List customers) => setState(() {
        for (final c in customers) {
          _selected.remove((c as Map<String, dynamic>)['code'] as String);
        }
      });

  void _showAssignDayDialog() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Assign Day',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: _allDays.map((d) => GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  decoration: BoxDecoration(
                    color: _gold.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _gold.withValues(alpha: 0.4)),
                  ),
                  child: Text(d,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, color: _gold)),
                ),
              )).toList(),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // ── Build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final dayBreak = _globalDayBreak;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text('Customer List Allotment'),
        backgroundColor: _gold,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(icon: const Icon(Icons.info_outline_rounded), onPressed: () {}),
          IconButton(icon: const Icon(Icons.refresh_rounded),      onPressed: () {}),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
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
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() => _query = '');
                            })
                        : null,
                    filled: true,
                    fillColor: Colors.white,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade200)),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: _gold)),
                  ),
                ),
                const SizedBox(height: 10),

                // Stats row
                Text(
                  '${_pincodes.length} pincode(s)  |  $_totalAccounts account(s)',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),

                // Day count chips
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: _allDays.map((d) => Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: Text('$d:${dayBreak[d]}',
                            style: const TextStyle(
                                fontSize: 11, fontWeight: FontWeight.w600)),
                      ),
                    )).toList(),
                  ),
                ),
                const SizedBox(height: 12),

                // Pincode sections
                ..._pincodes.map((p) => _PincodeSection(
                  pincodeData: p,
                  expanded: _expanded.contains(p['pincode'] as String),
                  selected: _selected,
                  query: _query,
                  onToggle: () => setState(() {
                    final pin = p['pincode'] as String;
                    _expanded.contains(pin) ? _expanded.remove(pin) : _expanded.add(pin);
                  }),
                  onCustomerTap: _toggleCustomer,
                  onSelectAll: () => _selectAll(p['customers'] as List),
                  onSelectNone: () => _selectNone(p['customers'] as List),
                  filteredCustomers: _filteredCustomers(p['customers'] as List),
                )),

                const SizedBox(height: 80),
              ],
            ),
          ),

          // ── Bottom bar ────────────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, -2))],
            ),
            child: Row(
              children: [
                Text(
                  '${_selected.length} selected  |  $_selectedDayCount day',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                OutlinedButton(
                  onPressed: _selected.isEmpty ? null : () => setState(() => _selected.clear()),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.red),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.remove_circle_outline_rounded, size: 15),
                      SizedBox(width: 4),
                      Text('Unassign', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: _selected.isEmpty ? null : _showAssignDayDialog,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _gold,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.save_rounded, size: 15),
                      SizedBox(width: 4),
                      Text('Assign Day', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Pincode Section ───────────────────────────────────────────────────────────

class _PincodeSection extends StatelessWidget {
  final Map<String, dynamic>       pincodeData;
  final bool                       expanded;
  final Set<String>                selected;
  final String                     query;
  final VoidCallback               onToggle;
  final void Function(String code) onCustomerTap;
  final VoidCallback               onSelectAll;
  final VoidCallback               onSelectNone;
  final List<Map<String, dynamic>> filteredCustomers;

  static const _gold = Color(0xFFD7BE69);
  static const _allDays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  const _PincodeSection({
    required this.pincodeData,
    required this.expanded,
    required this.selected,
    required this.query,
    required this.onToggle,
    required this.onCustomerTap,
    required this.onSelectAll,
    required this.onSelectNone,
    required this.filteredCustomers,
  });

  @override
  Widget build(BuildContext context) {
    final pincode  = pincodeData['pincode'] as String;
    final existing = pincodeData['existing'] as int;
    final assign   = pincodeData['assign']   as int;
    final remaining= pincodeData['remaining']as int;
    final dayBreak = pincodeData['dayBreak'] as Map<String, dynamic>;

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
          // ── Header ────────────────────────────────────────────────────────
          InkWell(
            onTap: onToggle,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(pincode,
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w800)),
                      const Spacer(),
                      Icon(expanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                          color: Colors.black45),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _StatChip(label: 'Existing: $existing', color: _gold),
                        const SizedBox(width: 6),
                        _StatChip(label: 'Assign: $assign',     color: _gold),
                        const SizedBox(width: 6),
                        _StatChip(label: 'Remaining: $remaining',color: _gold),
                        const SizedBox(width: 6),
                        _StatChip(label: 'Selected: ${filteredCustomers.where((c) => selected.contains(c['code'])).length}', color: _gold),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Day breakdown
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: _allDays.map((d) => Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: Text('$d:${dayBreak[d] ?? 0}',
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                      )).toList(),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Expanded: select buttons + customer cards ─────────────────────
          if (expanded) ...[
            const Divider(height: 1),
            if (filteredCustomers.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                child: Row(
                  children: [
                    _SelectBtn(
                      icon: Icons.check_rounded,
                      label: 'Select All',
                      onTap: onSelectAll,
                    ),
                    const SizedBox(width: 8),
                    _SelectBtn(
                      icon: Icons.grid_view_rounded,
                      label: 'Select None',
                      onTap: onSelectNone,
                    ),
                  ],
                ),
              ),
            ],
            ...filteredCustomers.map((c) => _CustomerCard(
              customer: c,
              isSelected: selected.contains(c['code'] as String),
              onTap: () => onCustomerTap(c['code'] as String),
            )),
            if (filteredCustomers.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: Text(
                    query.isNotEmpty ? 'No results for "$query"' : 'No customers in this pincode',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                  ),
                ),
              ),
            const SizedBox(height: 4),
          ],
        ],
      ),
    );
  }
}

// ── Customer Card (inside pincode) ────────────────────────────────────────────

class _CustomerCard extends StatelessWidget {
  final Map<String, dynamic> customer;
  final bool                 isSelected;
  final VoidCallback         onTap;

  static const _allDays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  const _CustomerCard({
    required this.customer,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final days   = (customer['days']   as List).cast<String>();
    final active = (customer['active'] as List).cast<String>();
    final next   = customer['next'] as String;

    return Container(
      margin: const EdgeInsets.fromLTRB(10, 4, 10, 4),
      decoration: BoxDecoration(
        color: isSelected
            ? const Color(0xFFEBF5FB)
            : const Color(0xFFF0FFF4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected
              ? const Color(0xFFAED6F1)
              : const Color(0xFFC8E6C9),
        ),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Code + salesman
          Row(
            children: [
              Text(customer['code'] as String,
                  style: const TextStyle(fontSize: 11, color: Colors.black54, letterSpacing: 0.4)),
              const Spacer(),
              Text(customer['salesman'] as String,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 4),
          // Store name
          Text(customer['name'] as String,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text('Address : ${customer['address']}',
              style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
          Text('Main area : ${customer['area']}',
              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          // Days row
          Row(
            children: [
              const Text('Days : ',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
              ..._allDays.map((d) {
                final has    = days.contains(d);
                final isAct  = active.contains(d);
                return Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: isAct
                          ? Colors.black87
                          : has
                              ? Colors.grey.shade200
                              : Colors.transparent,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(d,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: isAct
                              ? Colors.white
                              : has
                                  ? Colors.black54
                                  : Colors.grey.shade300,
                        )),
                  ),
                );
              }),
            ],
          ),
          const SizedBox(height: 6),
          // Next visit chip
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(next,
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(height: 8),
          // Checkbox + phone + actions
          Row(
            children: [
              GestureDetector(
                onTap: onTap,
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
                      Text(customer['phone'] as String,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _ActionBtn(icon: Icons.call_rounded,  color: Colors.grey.shade600),
              const SizedBox(width: 6),
              _ActionBtn(icon: Icons.chat_rounded,  color: const Color(0xFF25D366)),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

class _StatChip extends StatelessWidget {
  final String label;
  final Color  color;
  const _StatChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.w700, color: color)),
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
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13, color: Colors.black54),
              const SizedBox(width: 4),
              Text(label,
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      );
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final Color    color;
  const _ActionBtn({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        width: 36, height: 36,
        decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
        child: Icon(icon, size: 18, color: color),
      );
}

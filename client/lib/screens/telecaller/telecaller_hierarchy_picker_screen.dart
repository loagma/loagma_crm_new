import 'package:flutter/material.dart';

import '../../services/api_service.dart';
import '../admin/incharge_levels.dart' show normalizeRole;
import 'telecaller_mock_data.dart';

/// Drill-down picker for "Team Report New": Head Incharge → Zonal Incharge →
/// Teleadmin → Telecaller, one level at a time (report-card style, not a
/// flat dropdown) — so an admin picks their way down the org chart instead
/// of scanning every telecaller in one long list.
///
/// Only the telecaller-hierarchy branch is shown (head_incharge,
/// zonal_incharge, teleadmin, telecaller) — the salesman branch
/// (area_incharge → salesman) is irrelevant to this report and filtered out.
///
/// Pops with `{'mobile': ..., 'name': ...}` when a telecaller is picked, or
/// null if the user backs out without choosing one.
class TelecallerHierarchyPickerScreen extends StatefulWidget {
  // admin sees the whole company (root = every Head Incharge); anyone else
  // starts at their own subtree (root = their own direct children) — never
  // someone else's, same scoping the server enforces in
  // TelecallerReportController::resolveTelecallerId.
  final String viewerRole;
  final String viewerMobile;

  // 'telecaller' → Head → Zonal → Teleadmin → Telecaller
  // 'salesman'   → Head → Zonal → Area Incharge → Salesman
  final String branch;

  const TelecallerHierarchyPickerScreen({
    super.key,
    required this.viewerRole,
    required this.viewerMobile,
    this.branch = 'telecaller',
  });

  @override
  State<TelecallerHierarchyPickerScreen> createState() => _TelecallerHierarchyPickerScreenState();
}

class _Node {
  final String mobile;
  final String name;
  final String role;
  const _Node({required this.mobile, required this.name, required this.role});
}

class _TelecallerHierarchyPickerScreenState extends State<TelecallerHierarchyPickerScreen> {
  bool get _isSalesmanBranch => widget.branch == 'salesman';
  String get _leafRole => _isSalesmanBranch ? 'salesman' : 'telecaller';
  Set<String> get _allowedRoles => _isSalesmanBranch
      ? {'head_incharge', 'zonal_incharge', 'area_incharge', 'salesman'}
      : {'head_incharge', 'zonal_incharge', 'teleadmin', 'telecaller'};

  bool _loading = true;
  String? _error;

  // parent mobile -> child mobiles (raw, from incharge_assign_crm)
  Map<String, List<String>> _childIdsOf = {};
  Map<String, Map<String, dynamic>> _empByMobile = {};

  // Breadcrumb of picked nodes, root first. Empty = at the root level.
  final List<_Node> _path = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final results = await Future.wait([
        ApiService.getAllInchargeAssigns(),
        ApiService.getEmployees(perPage: 500),
      ]);
      final allAssigns = results[0];
      final allStaff = results[1];

      final childIdsOf = <String, List<String>>{};
      for (final a in allAssigns) {
        final parentId = '${a['head_incharge_id'] ?? ''}';
        final ids = a['incharge_ids'];
        if (parentId.isEmpty || parentId == '0' || ids is! List) continue;
        childIdsOf[parentId] = ids
            .map((e) => '$e')
            .where((s) => s.isNotEmpty && s != '0')
            .toList();
      }

      final empByMobile = <String, Map<String, dynamic>>{};
      for (final e in allStaff) {
        final mob = '${e['mobile'] ?? ''}'.trim();
        final deli = '${e['deli_id'] ?? ''}'.trim();
        if (mob.isNotEmpty) empByMobile[mob] = e;
        if (deli.isNotEmpty) empByMobile[deli] = e;
      }

      if (!mounted) return;
      setState(() {
        _childIdsOf = childIdsOf;
        _empByMobile = empByMobile;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = 'Failed to load: $e'; });
    }
  }

  bool get _isAdmin => normalizeRole(widget.viewerRole) == 'admin';

  List<_Node> _childrenOf(String? parentMobile) {
    Iterable<Map<String, dynamic>> pool;
    bool rootIsCompanyWideHeadIncharges = false;

    if (parentMobile != null) {
      // Drilled at least one level in — always this node's own children.
      final ids = _childIdsOf[parentMobile] ?? const <String>[];
      pool = ids.map((id) => _empByMobile[id]).whereType<Map<String, dynamic>>();
    } else if (_isAdmin) {
      // Admin's root: every Head Incharge company-wide.
      pool = _empByMobile.values;
      rootIsCompanyWideHeadIncharges = true;
    } else {
      // Any other senior's root: their OWN direct children only — never
      // another branch of the company (mirrors the server's
      // Hierarchy::subtreeForViewer scoping).
      final ids = _childIdsOf[widget.viewerMobile] ?? const <String>[];
      pool = ids.map((id) => _empByMobile[id]).whereType<Map<String, dynamic>>();
    }

    final seen = <String>{};
    final nodes = <_Node>[];
    for (final e in pool) {
      final role = normalizeRole(e['role'] as String?);
      if (!_allowedRoles.contains(role)) continue;
      final mobile = '${e['mobile'] ?? ''}'.trim();
      if (mobile.isEmpty || !seen.add(mobile)) continue;
      if (rootIsCompanyWideHeadIncharges && role != 'head_incharge') continue;
      nodes.add(_Node(mobile: mobile, name: '${e['name'] ?? mobile}', role: role));
    }
    nodes.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return nodes;
  }

  void _drillInto(_Node n) {
    if (n.role == _leafRole) {
      Navigator.pop(context, {'mobile': n.mobile, 'name': n.name});
      return;
    }
    setState(() => _path.add(n));
  }

  void _backTo(int index) {
    // index == -1 means the root breadcrumb.
    setState(() => _path.removeRange(index + 1, _path.length));
  }

  // What role the cards on screen right now belong to — drives the AppBar
  // title ("Pick Head Incharge" → "Pick Zonal Incharge" → …) so each step is
  // explicit instead of every level looking like the same generic list.
  Map<String, String> get _roleAfter => _isSalesmanBranch
      ? const {
          'head_incharge': 'zonal_incharge',
          'zonal_incharge': 'area_incharge',
          'area_incharge': 'salesman',
        }
      : const {
          'head_incharge': 'zonal_incharge',
          'zonal_incharge': 'teleadmin',
          'teleadmin': 'telecaller',
        };

  String _currentLevelRole() {
    if (_path.isNotEmpty) return _roleAfter[_path.last.role] ?? _leafRole;
    if (_isAdmin) return 'head_incharge';
    return _roleAfter[normalizeRole(widget.viewerRole)] ?? _leafRole;
  }

  // Hardware/gesture back and the AppBar's own back arrow both go up one
  // level while drilled in, and only leave the screen once at the root —
  // otherwise a stray back tap silently cancels the whole picker.
  void _handleBack() {
    if (_path.isNotEmpty) {
      _backTo(_path.length - 2);
    } else {
      Navigator.pop(context);
    }
  }

  ({String label, Color color, Color bg}) _roleStyle(String role) {
    switch (role) {
      case 'head_incharge':
        return (label: 'Head Incharge', color: const Color(0xFFAB47BC), bg: const Color(0xFFF3E5F5));
      case 'zonal_incharge':
        return (label: 'Zonal Incharge', color: const Color(0xFF42A5F5), bg: const Color(0xFFE3F2FD));
      case 'teleadmin':
        return (label: 'Teleadmin', color: const Color(0xFF5E35B1), bg: const Color(0xFFEDE7F6));
      case 'telecaller':
        return (label: 'Telecaller', color: const Color(0xFF00838F), bg: const Color(0xFFE0F7FA));
      case 'area_incharge':
        return (label: 'Area Incharge', color: const Color(0xFFFF7043), bg: const Color(0xFFFBE9E7));
      case 'salesman':
        return (label: 'Salesman', color: const Color(0xFF43A047), bg: const Color(0xFFE8F5E9));
      default:
        return (label: role, color: Colors.grey, bg: const Color(0xFFEEEEEE));
    }
  }

  @override
  Widget build(BuildContext context) {
    final parentMobile = _path.isEmpty ? null : _path.last.mobile;
    final children = _loading ? const <_Node>[] : _childrenOf(parentMobile);
    final levelLabel = _roleStyle(_currentLevelRole()).label;

    return PopScope(
      canPop: _path.isEmpty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleBack();
      },
      child: Scaffold(
        backgroundColor: kBg,
        appBar: AppBar(
          backgroundColor: kGold,
          elevation: 0,
          iconTheme: const IconThemeData(color: Colors.white),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: _handleBack,
          ),
          title: Text('Pick $levelLabel',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17)),
          bottom: _path.isEmpty ? null : _breadcrumbBar(),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator(color: kGold))
            : _error != null
                ? Center(child: Text(_error!, style: const TextStyle(color: Colors.black54)))
                : children.isEmpty
                    ? Center(
                        child: Text(
                          _path.isEmpty
                              ? (_isAdmin ? 'No Head Incharges found.' : 'No team assigned to you yet.')
                              : 'No one under ${_path.last.name} yet.',
                          style: const TextStyle(color: Colors.black54),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(12),
                        itemCount: children.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (_, i) => _nodeCard(children[i]),
                      ),
      ),
    );
  }

  // Docked to the AppBar (not a separate floating bar) so the "where am I"
  // trail always sits in the same place, right under the title.
  PreferredSizeWidget _breadcrumbBar() {
    return PreferredSize(
      preferredSize: const Size.fromHeight(34),
      child: Container(
        width: double.infinity,
        color: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _crumb(_isAdmin ? 'All' : 'My Team', () => _backTo(-1), active: false),
              for (var i = 0; i < _path.length; i++) ...[
                const Icon(Icons.chevron_right_rounded, size: 14, color: Colors.black38),
                _crumb(_path[i].name, () => _backTo(i), active: i == _path.length - 1),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _crumb(String label, VoidCallback onTap, {required bool active}) {
    return InkWell(
      onTap: active ? null : onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            color: active ? Colors.black87 : kGoldDark,
            decoration: active ? TextDecoration.none : TextDecoration.underline,
          ),
        ),
      ),
    );
  }

  Widget _nodeCard(_Node n) {
    final style = _roleStyle(n.role);
    final isLeaf = n.role == _leafRole;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      elevation: 1,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _drillInto(n),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: style.bg,
                child: Icon(isLeaf ? (_isSalesmanBranch ? Icons.storefront_rounded : Icons.support_agent_rounded) : Icons.account_tree_rounded, size: 18, color: style.color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(n.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: style.bg, borderRadius: BorderRadius.circular(20)),
                      child: Text(style.label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: style.color)),
                    ),
                  ],
                ),
              ),
              Icon(isLeaf ? Icons.check_circle_outline_rounded : Icons.chevron_right_rounded,
                  color: isLeaf ? const Color(0xFF43A047) : Colors.black38),
            ],
          ),
        ),
      ),
    );
  }
}

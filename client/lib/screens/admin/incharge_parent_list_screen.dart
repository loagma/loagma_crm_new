import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../services/api_service.dart';
import 'incharge_levels.dart';

/// Lists every employee whose role == [level.parentRole] and shows how many
/// children ([level.childRole]) are currently assigned to each. Tapping a row
/// opens the child-assignment screen for that parent.
class InchargeParentListScreen extends StatefulWidget {
  final InchargeLevel level;

  const InchargeParentListScreen({super.key, required this.level});

  @override
  State<InchargeParentListScreen> createState() => _InchargeParentListScreenState();
}

class _InchargeParentListScreenState extends State<InchargeParentListScreen> {
  static const gold = Color(0xFFD7BE69);

  final _searchCtrl = TextEditingController();
  String _query = '';
  String _filter = 'all';
  bool _loading = false;

  List<Map<String, dynamic>> _parents = [];
  Map<String, List<String>> _assignMap = {}; // parentId → child names
  Map<String, ZonalSpecialty> _specialtyMap = {}; // parentId → derived specialty (zonal only)

  InchargeLevel get _level => widget.level;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);

    final staffFuture = ApiService.getEmployees(perPage: 500);
    final assignsFuture = ApiService.getAllInchargeAssigns();

    final staffList = await staffFuture;
    final assignsList = await assignsFuture;
    if (!mounted) return;

    // parentId → child names (the API stores parent under `head_incharge_id`
    // and children under `incharge_names`, used generically for every level)
    final assignMap = <String, List<String>>{};
    for (final a in assignsList) {
      final parentId = (a['head_incharge_id'] ?? '').toString();
      final names = a['incharge_names'];
      if (parentId.isNotEmpty && parentId != '0' && names is List) {
        assignMap[parentId] = List<String>.from(names.map((n) => n.toString()));
      }
    }

    // child id (mobile or deli_id) → normalized role, to derive a zonal's
    // specialty (sales / tele / both) from the roles of its assigned children.
    final roleById = <String, String>{};
    for (final e in staffList) {
      final role = normalizeRole(e['role']);
      final mob = (e['mobile'] ?? '').toString();
      final deli = (e['deli_id'] ?? '').toString();
      if (mob.isNotEmpty) roleById[mob] = role;
      if (deli.isNotEmpty) roleById[deli] = role;
    }

    final specialtyMap = <String, ZonalSpecialty>{};
    if (_level.hasMultipleChildRoles) {
      for (final a in assignsList) {
        final parentId = (a['head_incharge_id'] ?? '').toString();
        final ids = a['incharge_ids'];
        if (parentId.isEmpty || parentId == '0' || ids is! List) continue;
        final roles = ids.map((id) => roleById[id.toString()] ?? '').toList();
        specialtyMap[parentId] = zonalSpecialtyFromRoles(roles);
      }
    }

    final parents = staffList.map((e) {
      final role = (e['role'] ?? '').toString().trim().toLowerCase();
      final id = (e['mobile'] ?? e['deli_id'] ?? '').toString();
      return <String, dynamic>{
        'id': id,
        'name': (e['name'] ?? '').toString(),
        'mobile': (e['mobile'] ?? '').toString(),
        'role': role,
      };
    }).where((e) {
      if (e['role'] != _level.parentRole) return false;
      if (_query.isNotEmpty) {
        final q = _query.toLowerCase();
        return e['name'].toString().toLowerCase().contains(q) ||
            e['mobile'].toString().contains(q);
      }
      return true;
    }).toList();

    setState(() {
      _parents = parents;
      _assignMap = assignMap;
      _specialtyMap = specialtyMap;
      _loading = false;
    });
  }

  List<Map<String, dynamic>> get _filtered {
    if (_filter == 'assigned') {
      return _parents.where((s) => (_assignMap[s['id']] ?? []).isNotEmpty).toList();
    }
    if (_filter == 'not_assigned') {
      return _parents.where((s) => (_assignMap[s['id']] ?? []).isEmpty).toList();
    }
    return _parents;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: Text(_level.parentLabel),
        backgroundColor: gold,
        foregroundColor: Colors.white,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(20),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(_level.hasMultipleChildRoles
                ? 'Tap to assign area incharges & teleadmins'
                : 'Tap to assign ${_level.childLabel.toLowerCase()}s',
                style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.8))),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _loadAll,
        backgroundColor: gold,
        foregroundColor: Colors.white,
        tooltip: 'Refresh',
        child: const Icon(Icons.refresh_rounded),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) {
                _query = v.trim();
                _loadAll();
              },
              decoration: InputDecoration(
                hintText: 'Search ${_level.parentLabel.toLowerCase()} by name or mobile…',
                prefixIcon: const Icon(Icons.search_rounded, color: gold),
                suffixIcon: _query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close_rounded, size: 18),
                        onPressed: () {
                          _searchCtrl.clear();
                          _query = '';
                          _loadAll();
                        })
                    : null,
                isDense: true,
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade200)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: gold)),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
            child: Row(
              children: [
                for (final f in [('all', 'All'), ('assigned', 'Assigned'), ('not_assigned', 'Not Assigned')])
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(f.$2),
                      selected: _filter == f.$1,
                      onSelected: (_) => setState(() => _filter = f.$1),
                      selectedColor: gold,
                      labelStyle: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: _filter == f.$1 ? Colors.white : Colors.grey.shade700),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: gold))
                : _filtered.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.supervisor_account_outlined, size: 64, color: Colors.grey.shade300),
                            const SizedBox(height: 12),
                            Text('No ${_level.parentLabel.toLowerCase()}s found',
                                style: TextStyle(fontSize: 15, color: Colors.grey.shade500)),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadAll,
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(12, 6, 12, 80),
                          itemCount: _filtered.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (context, i) {
                            final s = _filtered[i];
                            final names = _assignMap[s['id']] ?? [];
                            return _ParentCard(
                              level: _level,
                              parent: s,
                              assignedChildren: names,
                              specialty: _specialtyMap[s['id']] ?? ZonalSpecialty.none,
                              onTap: () async {
                                await context.push('/incharge-assign/assign/${_level.key}/${s['id']}', extra: s);
                                _loadAll();
                              },
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

class _ParentCard extends StatelessWidget {
  final InchargeLevel level;
  final Map<String, dynamic> parent;
  final List<String> assignedChildren;
  final ZonalSpecialty specialty;
  final VoidCallback onTap;

  const _ParentCard({
    required this.level,
    required this.parent,
    required this.assignedChildren,
    required this.specialty,
    required this.onTap,
  });

  String get _initials {
    final name = (parent['name'] as String? ?? '').trim();
    final parts = name.split(' ').where((p) => p.isNotEmpty).toList();
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  @override
  Widget build(BuildContext context) {
    final has = assignedChildren.isNotEmpty;

    return GestureDetector(
      onTap: onTap,
      child: Card(
        color: Colors.white,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 1.5,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: const Color(0xFFC09E3E).withValues(alpha: 0.12),
                    child: Text(_initials,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFFC09E3E))),
                  ),
                  if (has)
                    Positioned(
                      right: -4,
                      top: -4,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(color: Color(0xFFC09E3E), shape: BoxShape.circle),
                        child: Text('${assignedChildren.length}',
                            style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white)),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                            child: Text((parent['name'] ?? '').toString(),
                                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600))),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(color: const Color(0xFFFFF8E1), borderRadius: BorderRadius.circular(20)),
                          child: Text(level.parentLabel,
                              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFFC09E3E))),
                        ),
                        if (specialty.label != null) ...[
                          const SizedBox(width: 5),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: specialty.color.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: specialty.color.withValues(alpha: 0.5)),
                            ),
                            child: Text(specialty.label!,
                                style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: specialty.color)),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text((parent['mobile'] ?? '').toString(),
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                    const SizedBox(height: 6),
                    if (!has)
                      Row(children: [
                        Icon(Icons.person_off_rounded, size: 12, color: Colors.grey.shade400),
                        const SizedBox(width: 4),
                        Text(level.hasMultipleChildRoles
                            ? 'No team assigned'
                            : 'No ${level.childLabel.toLowerCase()}s assigned',
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
                      ])
                    else ...[
                      Row(children: [
                        const Icon(Icons.supervisor_account_rounded, size: 12, color: Color(0xFFC09E3E)),
                        const SizedBox(width: 4),
                        Text(level.hasMultipleChildRoles
                            ? '${assignedChildren.length} member${assignedChildren.length == 1 ? '' : 's'} assigned'
                            : '${assignedChildren.length} ${level.childLabelCount(assignedChildren.length).toLowerCase()} assigned',
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFFC09E3E))),
                      ]),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: assignedChildren
                            .map((n) => Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFFF8E1),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: const Color(0xFFD7BE69)),
                                  ),
                                  child: Text(n,
                                      style: const TextStyle(fontSize: 10, color: Color(0xFFC09E3E), fontWeight: FontWeight.w500)),
                                ))
                            .toList(),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right_rounded, color: Colors.grey, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

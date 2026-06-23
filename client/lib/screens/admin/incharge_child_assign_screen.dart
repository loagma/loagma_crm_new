import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';

import '../../services/api_service.dart';
import 'incharge_levels.dart';

/// Multi-select screen: pick the children ([level.childRole]) to assign to a
/// single [parent] ([level.parentRole]). Saves via the generic incharge-assign
/// API keyed by the parent's mobile id.
class InchargeChildAssignScreen extends StatefulWidget {
  final InchargeLevel level;
  final Map<String, dynamic> parent;

  const InchargeChildAssignScreen({super.key, required this.level, required this.parent});

  @override
  State<InchargeChildAssignScreen> createState() => _InchargeChildAssignScreenState();
}

class _InchargeChildAssignScreenState extends State<InchargeChildAssignScreen> {
  static const goldDark = Color(0xFFD7BE69);
  static const goldLight = Color(0xFFFFF8E1);

  final Set<int> _selectedIds = {};
  final Set<int> _originalIds = {}; // snapshot of pre-assigned children
  bool _loading = false;
  bool _saving = false;
  List<Map<String, dynamic>> _children = [];
  Map<String, List<String>> _areaMap = {}; // childId → area names
  Map<int, List<String>> _childOwners = {}; // childId → other same-level parents owning it
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';

  InchargeLevel get _level => widget.level;

  String get _parentId =>
      (widget.parent['id'] ?? widget.parent['deli_id'] ?? '').toString();

  List<Map<String, dynamic>> get _filtered {
    if (_searchQuery.isEmpty) return _children;
    final q = _searchQuery.toLowerCase();
    return _children
        .where((i) =>
            (i['name'] ?? '').toString().toLowerCase().contains(q) ||
            (i['mobile'] ?? '').toString().contains(q))
        .toList();
  }

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
    final assignFuture = ApiService.getInchargeAssign(_parentId);
    final areaAssignFuture = ApiService.getAllAreaAssigns();
    final allInchargeFuture = ApiService.getAllInchargeAssigns();

    final staffList = await staffFuture;
    final assignResult = await assignFuture;
    final allAreaAssigns = await areaAssignFuture;
    final allInchargeAssigns = await allInchargeFuture;

    if (!mounted) return;

    final areaMap = <String, List<String>>{};
    for (final a in allAreaAssigns) {
      final empId = (a['employee_id'] ?? '').toString();
      final names = a['area_names'];
      if (empId.isNotEmpty && names is List) {
        areaMap[empId] = List<String>.from(names.map((n) => n.toString()));
      }
    }

    // Lookup: mobile → {name, role}, used to resolve owning-parent name & scope by level.
    final staffByMobile = <String, Map<String, dynamic>>{
      for (final e in staffList) (e['mobile'] ?? '').toString(): e,
    };

    // Roles assignable on this level (one, or two for the zonal level).
    final childRoles = _level.childRoleList.map((c) => normalizeRole(c.role)).toSet();
    final children = staffList.map((e) {
      final role = normalizeRole(e['role']);
      final id = (e['mobile'] ?? e['deli_id'] ?? '').toString();
      return <String, dynamic>{
        'id': id,
        'name': (e['name'] ?? '').toString(),
        'mobile': (e['mobile'] ?? '').toString(),
        'role': role,
      };
    }).where((e) => childRoles.contains(e['role'])).toList();

    // childId → names of OTHER same-level parents that already own this child.
    final childOwners = <int, List<String>>{};
    for (final a in allInchargeAssigns) {
      final ownerId = (a['head_incharge_id'] ?? '').toString();
      if (ownerId.isEmpty || ownerId == _parentId) continue;
      final ownerEmp = staffByMobile[ownerId];
      if (ownerEmp == null) continue;
      final ownerRole = (ownerEmp['role'] ?? '').toString().trim().toLowerCase();
      if (ownerRole != _level.parentRole) continue; // same level only
      final ownerName = (ownerEmp['name'] ?? '').toString();
      final ids = a['incharge_ids'];
      if (ids is! List) continue;
      for (final r in ids) {
        final cid = int.tryParse(r.toString());
        if (cid == null) continue;
        childOwners.putIfAbsent(cid, () => []).add(ownerName);
      }
    }

    // Pre-select currently assigned children
    final Set<int> preSelected = {};
    if (assignResult != null && assignResult['data'] is Map) {
      final ids = (assignResult['data'] as Map)['incharge_ids'];
      if (ids is List) {
        for (final id in ids) {
          final n = int.tryParse(id.toString());
          if (n != null) preSelected.add(n);
        }
      }
    }

    setState(() {
      _children = children;
      _areaMap = areaMap;
      _childOwners = childOwners;
      _selectedIds
        ..clear()
        ..addAll(preSelected);
      _originalIds
        ..clear()
        ..addAll(preSelected);
      _loading = false;
    });
  }

  int _idOf(Map<String, dynamic> inc) => int.tryParse((inc['id'] ?? '').toString()) ?? 0;

  String _childNameOf(int id) {
    for (final c in _children) {
      if (_idOf(c) == id) return (c['name'] ?? '').toString();
    }
    return '#$id';
  }

  Future<String?> _showConflictDialog(Map<int, List<String>> conflicts) {
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Already Assigned',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                  'These ${_level.hasMultipleChildRoles ? 'members' : '${_level.childLabel}s'} are already assigned to other ${_level.parentLabel}s:',
                  style: const TextStyle(fontSize: 13)),
              const SizedBox(height: 10),
              ...conflicts.entries.map((e) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          const Icon(Icons.person_rounded, size: 14, color: goldDark),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(_childNameOf(e.key),
                                style: const TextStyle(
                                    fontSize: 13, fontWeight: FontWeight.w700)),
                          ),
                        ]),
                        Padding(
                          padding: const EdgeInsets.only(left: 18, top: 1),
                          child: Text(e.value.join(', '),
                              style: TextStyle(
                                  fontSize: 11.5, color: Colors.grey.shade600)),
                        ),
                      ],
                    ),
                  )),
              const SizedBox(height: 4),
              const Text('Do you still want to assign them?',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'cancel'),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'skip'),
            child: const Text('Skip These',
                style: TextStyle(color: Color(0xFFE65100), fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, 'assign'),
            style: ElevatedButton.styleFrom(
              backgroundColor: goldDark, foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Assign Anyway'),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    if (_saving) return;

    // ── Conflict check for newly-added children already under another parent ──
    final newlyAdded = _selectedIds.difference(_originalIds);
    final conflicts = <int, List<String>>{};
    for (final cid in newlyAdded) {
      final owners = (_childOwners[cid] ?? []).where((n) => n.isNotEmpty).toList();
      if (owners.isNotEmpty) conflicts[cid] = owners;
    }

    // Mutable copy so "Skip These" can drop the conflicting children.
    final toSave = Set<int>.from(_selectedIds);

    if (conflicts.isNotEmpty) {
      final choice = await _showConflictDialog(conflicts);
      if (!mounted) return;
      if (choice == 'cancel' || choice == null) return; // abort, keep selection
      if (choice == 'skip') toSave.removeAll(conflicts.keys);
      // 'assign' → keep all (duplicates allowed)
    }

    setState(() => _saving = true);

    final selected = _children.where((i) => toSave.contains(_idOf(i))).toList();
    final ids = selected.map(_idOf).toList();
    final names = selected.map((i) => (i['name'] ?? '').toString()).toList();

    final res = await ApiService.saveInchargeAssign(_parentId, ids, names);

    if (!mounted) return;
    setState(() => _saving = false);

    if (res == null || res.containsKey('errors')) {
      Fluttertoast.showToast(
          msg: 'Failed to save', backgroundColor: Colors.red, textColor: Colors.white);
      return;
    }

    Fluttertoast.showToast(
      msg: ids.isEmpty
          ? 'Assignment cleared successfully'
          : _level.hasMultipleChildRoles
              ? '${ids.length} member${ids.length == 1 ? '' : 's'} assigned successfully'
              : '${ids.length} ${_level.childLabelCount(ids.length).toLowerCase()} assigned successfully',
      backgroundColor: goldDark,
      textColor: Colors.white,
      toastLength: Toast.LENGTH_LONG,
    );

    // Return to the previous page (parent list) after a successful save.
    if (mounted) Navigator.of(context).pop();
  }

  String get _initials {
    final name = (widget.parent['name'] as String? ?? '').trim();
    final parts = name.split(' ').where((p) => p.isNotEmpty).toList();
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.parent['name'] as String? ?? _level.parentLabel;
    final mobile = widget.parent['mobile'] as String? ?? '';

    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      appBar: AppBar(
        title: Text(_level.hasMultipleChildRoles ? 'Assign Team' : 'Assign ${_level.childLabel}s'),
        backgroundColor: goldDark,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _saving ? null : _save,
        backgroundColor: goldDark,
        foregroundColor: Colors.white,
        icon: _saving
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
            : const Icon(Icons.save_rounded),
        label: Text(_saving ? 'Saving…' : 'Save Assignment',
            style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: Column(
        children: [
          _buildHeader(name, mobile),
          if (_selectedIds.isNotEmpty && _children.isNotEmpty) _buildSelectedChips(),
          _buildSearchBar(),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: goldDark))
                : _buildList(),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(String name, String mobile) {
    final total = _children.length;
    final assigned = _selectedIds.length;
    final progress = total == 0 ? 0.0 : assigned / total;

    return Container(
      decoration: const BoxDecoration(
        color: goldDark,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.25),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white.withValues(alpha: 0.6), width: 2),
                ),
                child: Center(
                    child: Text(_initials,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white))),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white)),
                    if (mobile.isNotEmpty)
                      Text(mobile, style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.85))),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(20)),
                      child: Text(_level.parentLabel,
                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white)),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.4)),
                ),
                child: Column(children: [
                  Text('$assigned',
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white, height: 1)),
                  Text('assigned', style: TextStyle(fontSize: 10, color: Colors.white.withValues(alpha: 0.85))),
                ]),
              ),
            ],
          ),
          if (!_loading && total > 0) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progress,
                      backgroundColor: Colors.white.withValues(alpha: 0.25),
                      valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                      minHeight: 6,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text('$assigned / $total ${_level.hasMultipleChildRoles ? 'members' : '${_level.childLabel.toLowerCase()}s'}',
                    style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.9), fontWeight: FontWeight.w600)),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSelectedChips() {
    final sel = _children.where((i) => _selectedIds.contains(_idOf(i))).toList();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: goldLight,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFD7BE69)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.supervisor_account_rounded, size: 14, color: goldDark),
              const SizedBox(width: 6),
              Text(_level.hasMultipleChildRoles ? 'Selected members' : 'Selected ${_level.childLabel}s',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: goldDark)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: goldDark, borderRadius: BorderRadius.circular(10)),
                child: Text('${sel.length}',
                    style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: sel.map((i) {
              final id = _idOf(i);
              return GestureDetector(
                onTap: () => setState(() => _selectedIds.remove(id)),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFD7BE69)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.person_rounded, size: 12, color: goldDark),
                      const SizedBox(width: 4),
                      Text((i['name'] ?? '').toString(),
                          style: const TextStyle(fontSize: 11, color: goldDark, fontWeight: FontWeight.w600)),
                      const SizedBox(width: 5),
                      const Icon(Icons.close_rounded, size: 12, color: Color(0xFFD7BE69)),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 4),
          Text('Tap a chip to remove', style: TextStyle(fontSize: 10, color: Colors.amber.shade400)),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      child: TextField(
        controller: _searchCtrl,
        onChanged: (v) => setState(() => _searchQuery = v.trim()),
        decoration: InputDecoration(
          hintText: _level.hasMultipleChildRoles
              ? 'Search by name or mobile…'
              : 'Search ${_level.childLabel.toLowerCase()} by name or mobile…',
          hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
          prefixIcon: const Icon(Icons.search_rounded, color: goldDark),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: Icon(Icons.clear_rounded, size: 18, color: Colors.grey.shade400),
                  onPressed: () {
                    _searchCtrl.clear();
                    setState(() => _searchQuery = '');
                  })
              : null,
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Colors.grey.shade200)),
          focusedBorder: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(14)), borderSide: BorderSide(color: goldDark, width: 1.5)),
        ),
      ),
    );
  }

  /// Build the flat item list. Single-role levels keep the original
  /// Selected / Not Selected split; multi-role levels (zonal) group by child
  /// role ("Area Incharges", "Teleadmins"), selected-first within each group.
  List<Object> _buildItems() {
    if (!_level.hasMultipleChildRoles) {
      final selList = _filtered.where((i) => _selectedIds.contains(_idOf(i))).toList();
      final unselList = _filtered.where((i) => !_selectedIds.contains(_idOf(i))).toList();
      return [
        if (selList.isNotEmpty) ...[_Section('Selected', selList.length, true), ...selList],
        if (unselList.isNotEmpty) ...[_Section('Not Selected', unselList.length, false), ...unselList],
      ];
    }

    final items = <Object>[];
    for (final cr in _level.childRoleList) {
      final roleNorm = normalizeRole(cr.role);
      final group = _filtered.where((i) => normalizeRole(i['role']) == roleNorm).toList();
      if (group.isEmpty) continue;
      final sel = group.where((i) => _selectedIds.contains(_idOf(i))).toList();
      final unsel = group.where((i) => !_selectedIds.contains(_idOf(i))).toList();
      items
        ..add(_RoleHeader('${cr.label}s', sel.length, group.length))
        ..addAll(sel)
        ..addAll(unsel);
    }
    return items;
  }

  Widget _buildList() {
    if (_filtered.isEmpty) {
      final what = _level.hasMultipleChildRoles ? 'members' : '${_level.childLabel.toLowerCase()}s';
      return Center(
        child: Text(
          _searchQuery.isNotEmpty ? 'No $what match "$_searchQuery"' : 'No $what available',
          style: TextStyle(fontSize: 14, color: Colors.grey.shade400),
        ),
      );
    }

    final items = _buildItems();

    return RefreshIndicator(
      onRefresh: _loadAll,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 100),
        itemCount: items.length,
        itemBuilder: (context, i) {
          final item = items[i];

          if (item is _RoleHeader) {
            return Padding(
              padding: EdgeInsets.only(top: i == 0 ? 6 : 18, bottom: 8, left: 2, right: 2),
              child: Row(
                children: [
                  Icon(Icons.badge_outlined, size: 16, color: goldDark),
                  const SizedBox(width: 8),
                  Text(item.label,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: goldDark)),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
                    decoration: BoxDecoration(color: goldDark, borderRadius: BorderRadius.circular(10)),
                    child: Text('${item.selected}/${item.total}',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)),
                  ),
                  const Expanded(child: Divider(indent: 10)),
                ],
              ),
            );
          }

          if (item is _Section) {
            return Padding(
              padding: EdgeInsets.only(top: i == 0 ? 6 : 18, bottom: 8, left: 2, right: 2),
              child: Row(
                children: [
                  Icon(
                    item.isSelected ? Icons.check_circle_outline_rounded : Icons.radio_button_unchecked_rounded,
                    size: 16,
                    color: item.isSelected ? goldDark : Colors.grey.shade500,
                  ),
                  const SizedBox(width: 8),
                  Text(item.label,
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
                          color: item.isSelected ? goldDark : Colors.grey.shade700)),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
                    decoration: BoxDecoration(
                      color: item.isSelected ? goldDark : Colors.grey.shade400,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text('${item.count}',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)),
                  ),
                  const Expanded(child: Divider(indent: 10)),
                ],
              ),
            );
          }

          final inc = item as Map<String, dynamic>;
          final id = _idOf(inc);
          final isSel = _selectedIds.contains(id);
          final areas = _areaMap[inc['id']?.toString() ?? ''] ?? [];

          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: GestureDetector(
              onTap: () => setState(() {
                if (isSel) {
                  _selectedIds.remove(id);
                } else {
                  _selectedIds.add(id);
                }
              }),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isSel ? const Color(0xFFD7BE69) : Colors.transparent,
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: isSel ? goldDark.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.04),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    )
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                  child: Row(
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: isSel ? goldLight : Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: isSel ? const Color(0xFFD7BE69) : Colors.grey.shade200),
                        ),
                        child: Icon(Icons.person_rounded, color: isSel ? goldDark : Colors.grey.shade400, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text((inc['name'] ?? '').toString(),
                                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700,
                                    color: isSel ? const Color(0xFFB89A3E) : Colors.grey.shade900)),
                            Text((inc['mobile'] ?? '').toString(),
                                style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                            if (areas.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Wrap(
                                spacing: 4,
                                runSpacing: 3,
                                children: areas
                                    .take(3)
                                    .map((a) => Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFFFF8E1),
                                            borderRadius: BorderRadius.circular(4),
                                            border: Border.all(color: const Color(0xFFD7BE69).withValues(alpha: 0.4)),
                                          ),
                                          child: Text(a,
                                              style: const TextStyle(fontSize: 9, color: Color(0xFFB89A3E), fontWeight: FontWeight.w500)),
                                        ))
                                    .toList(),
                              ),
                            ] else if (normalizeRole(inc['role']) != 'teleadmin')
                              Text('No areas assigned',
                                  style: TextStyle(fontSize: 10, color: Colors.grey.shade400)),
                          ],
                        ),
                      ),
                      Checkbox(
                        value: isSel,
                        activeColor: goldDark,
                        checkColor: Colors.white,
                        side: BorderSide(color: isSel ? goldDark : Colors.grey.shade400, width: 1.5),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
                        onChanged: (v) => setState(() {
                          if (v == true) {
                            _selectedIds.add(id);
                          } else {
                            _selectedIds.remove(id);
                          }
                        }),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Section {
  final String label;
  final int count;
  final bool isSelected;
  const _Section(this.label, this.count, this.isSelected);
}

/// Header for a child-role group on multi-role levels (e.g. "Area Incharges",
/// "Teleadmins"), showing how many of that role are selected.
class _RoleHeader {
  final String label;
  final int selected;
  final int total;
  const _RoleHeader(this.label, this.selected, this.total);
}

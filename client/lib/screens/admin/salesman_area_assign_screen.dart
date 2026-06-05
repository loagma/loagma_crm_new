import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:go_router/go_router.dart';

import '../../services/api_service.dart';

class SalesmanAreaAssignScreen extends StatefulWidget {
  final Map<String, dynamic> salesman;

  const SalesmanAreaAssignScreen({super.key, required this.salesman});

  @override
  State<SalesmanAreaAssignScreen> createState() => _SalesmanAreaAssignScreenState();
}

class _SalesmanAreaAssignScreenState extends State<SalesmanAreaAssignScreen> {
  static const gold       = Color(0xFFD7BE69);
  static const greenCheck = Color(0xFF2E7D32);
  static const greenLight  = Color(0xFFE8F5E9);

  final Set<int> _assignedIds = {};
  // Snapshot of areas this person already had on load — used to detect newly-added.
  final Set<int> _originalAssignedIds = {};
  // areaId → other staff who already own it: [{id, name, role}]
  Map<int, List<Map<String, String>>> _areaOwners = {};
  bool _loading = false;
  bool _saving  = false;
  List<Map<String, dynamic>> _areas = [];
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  List<Map<String, dynamic>> get _filteredAreas {
    if (_searchQuery.isEmpty) return _areas;
    final q = _searchQuery.toLowerCase();
    return _areas.where((a) {
      if ((a['area_name'] ?? '').toString().toLowerCase().contains(q)) return true;
      if ((a['city']      ?? '').toString().toLowerCase().contains(q)) return true;
      if ((a['district']  ?? '').toString().toLowerCase().contains(q)) return true;
      if ((a['state']     ?? '').toString().toLowerCase().contains(q)) return true;
      final pins = a['pincodes'];
      if (pins is List) return pins.any((p) => p.toString().toLowerCase().contains(q));
      return false;
    }).toList();
  }

  String get _employeeId => (widget.salesman['mobile'] ?? widget.salesman['id'] ?? '').toString();

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);

    final areaResult   = await ApiService.getAreas(perPage: 200);
    final assignResult = await ApiService.getAreaAssign(_employeeId);

    if (!mounted) return;

    final raw  = areaResult['data'];
    final list = raw is List
        ? raw.map((e) => Map<String, dynamic>.from(e as Map)).toList()
        : <Map<String, dynamic>>[];

    final Set<int> preSelected = {};
    if (assignResult != null && assignResult['data'] is Map) {
      final ids = (assignResult['data'] as Map)['area_ids'];
      if (ids is List) {
        for (final id in ids) {
          final n = int.tryParse(id.toString());
          if (n != null) preSelected.add(n);
        }
      }
    }

    setState(() {
      _areas = list;
      _assignedIds..clear()..addAll(preSelected);
      _originalAssignedIds..clear()..addAll(preSelected);
      _loading = false;
    });

    // Load same-role conflict data in the background (non-blocking, fail-open).
    _loadAreaOwners();
  }

  // Builds areaId → other staff (excluding this person) who already own each area.
  Future<void> _loadAreaOwners() async {
    try {
      final assigns = await ApiService.getAllAreaAssigns();
      final staff   = await ApiService.getEmployees(perPage: 500);
      if (!mounted) return;

      final staffByMobile = <String, Map<String, dynamic>>{
        for (final e in staff) (e['mobile'] ?? '').toString(): e,
      };

      final owners = <int, List<Map<String, String>>>{};
      for (final a in assigns) {
        final empId = (a['employee_id'] ?? '').toString();
        if (empId == _employeeId) continue; // skip this person
        final emp = staffByMobile[empId];
        if (emp == null) continue;
        final ids = a['area_ids'];
        if (ids is! List) continue;
        for (final r in ids) {
          final aid = int.tryParse(r.toString());
          if (aid == null) continue;
          owners.putIfAbsent(aid, () => []).add({
            'id':   empId,
            'name': (emp['name'] ?? '').toString(),
            'role': (emp['role'] ?? '').toString().toLowerCase().trim(),
          });
        }
      }

      if (mounted) setState(() => _areaOwners = owners);
    } catch (_) {
      // fail-open: no conflict data → save proceeds without warnings
    }
  }

  int _idOf(Map<String, dynamic> area) =>
      int.tryParse((area['id'] ?? '').toString()) ?? 0;

  String _areaNameOf(int aid) {
    final a = _areas.firstWhere((e) => _idOf(e) == aid, orElse: () => const {});
    return (a['area_name'] ?? 'Area $aid').toString();
  }

  String _roleLabel(String role) =>
      role.isEmpty ? 'staff' : role.replaceAll('_', ' ');

  // Returns 'assign' | 'skip' | 'cancel' | null
  Future<String?> _showConflictDialog(Map<int, List<String>> conflicts, String role) {
    final roleLabel = _roleLabel(role);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Area Already Assigned',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('These areas are already assigned to other ${roleLabel}s:',
                  style: const TextStyle(fontSize: 13)),
              const SizedBox(height: 10),
              ...conflicts.entries.map((e) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          const Icon(Icons.location_on_rounded, size: 14, color: gold),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(_areaNameOf(e.key),
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
              const Text('Do you still want to assign these areas?',
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
              backgroundColor: gold, foregroundColor: Colors.white,
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

    // ── Same-role conflict check (only for newly-added areas) ────────────────
    final currentRole = (widget.salesman['role'] ?? '').toString().toLowerCase().trim();
    final newlyAdded  = _assignedIds.difference(_originalAssignedIds);

    // areaId → names of same-role staff already owning it
    final conflicts = <int, List<String>>{};
    for (final aid in newlyAdded) {
      final owners = (_areaOwners[aid] ?? [])
          .where((o) => o['role'] == currentRole)
          .map((o) => o['name'] ?? '')
          .where((n) => n.isNotEmpty)
          .toList();
      if (owners.isNotEmpty) conflicts[aid] = owners;
    }

    // Work on a mutable copy so "Skip" can drop conflicting areas
    final toSave = Set<int>.from(_assignedIds);

    if (conflicts.isNotEmpty) {
      final choice = await _showConflictDialog(conflicts, currentRole);
      if (!mounted) return;
      if (choice == 'cancel' || choice == null) return; // abort, keep selection
      if (choice == 'skip') toSave.removeAll(conflicts.keys);
      // 'assign' → keep all
    }

    setState(() => _saving = true);

    final selectedAreas = _areas.where((a) => toSave.contains(_idOf(a))).toList();
    final areaIds   = selectedAreas.map(_idOf).toList();
    final areaNames = selectedAreas.map((a) => (a['area_name'] ?? '').toString()).toList();

    final res = await ApiService.saveAreaAssign(_employeeId, areaIds, areaNames);

    if (!mounted) return;
    setState(() => _saving = false);

    if (res == null || res.containsKey('errors')) {
      Fluttertoast.showToast(msg: 'Failed to save assignment', backgroundColor: Colors.red, textColor: Colors.white);
    } else {
      Fluttertoast.showToast(
        msg: areaIds.isEmpty
            ? 'Assignment cleared successfully'
            : '${areaIds.length} area(s) assigned successfully',
        backgroundColor: greenCheck,
        textColor: Colors.white,
      );
      // Redirect back to the Area Assign page
      if (context.canPop()) {
        context.pop(true);
      } else {
        context.go('/area-assign');
      }
    }
  }


  // ── build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final name   = widget.salesman['name']   as String? ?? 'Staff';
    final mobile = widget.salesman['mobile'] as String? ?? '';
    final role   = (widget.salesman['role']  as String? ?? '').trim();

    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      appBar: AppBar(
        title: const Text('Area Assignment'),
        backgroundColor: gold,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _saving ? null : _save,
        backgroundColor: gold,
        foregroundColor: Colors.white,
        icon: _saving
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
            : const Icon(Icons.save_rounded),
        label: Text(_saving ? 'Saving…' : 'Save Assignment', style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: Column(
        children: [
          _buildHeader(name, mobile, role),
          _buildSearchBar(),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: gold))
                : _buildList(),
          ),
        ],
      ),
    );
  }

  // ── header ─────────────────────────────────────────────────────────────────

  Widget _buildHeader(String name, String mobile, String role) {
    final total    = _areas.length;
    final assigned = _assignedIds.length;

    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: gold,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 8, 12, 12),
      child: Row(
        children: [
          // name + role only
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white)),
                ),
                if (role.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  _RoleBadge(role: role),
                ],
              ],
            ),
          ),
          // compact assigned count
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text('$assigned / $total',
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // ── search bar ─────────────────────────────────────────────────────────────

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      child: TextField(
        controller: _searchController,
        onChanged: (v) => setState(() => _searchQuery = v.trim()),
        decoration: InputDecoration(
          hintText: 'Search area, city, district, pincode…',
          hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
          prefixIcon: const Icon(Icons.search_rounded, color: gold),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: Icon(Icons.clear_rounded, size: 18, color: Colors.grey.shade400),
                  onPressed: () { _searchController.clear(); setState(() => _searchQuery = ''); },
                )
              : null,
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
          border:        OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Colors.grey.shade200)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: gold, width: 1.5)),
        ),
      ),
    );
  }

  // ── sectioned list ─────────────────────────────────────────────────────────

  Widget _buildList() {
    final assignedList    = _filteredAreas.where((a) =>  _assignedIds.contains(_idOf(a))).toList();
    final notAssignedList = _filteredAreas.where((a) => !_assignedIds.contains(_idOf(a))).toList();

    if (_filteredAreas.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_searchQuery.isNotEmpty ? Icons.search_off_rounded : Icons.location_off_rounded,
                size: 60, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text(
              _searchQuery.isNotEmpty ? 'No areas match "$_searchQuery"' : 'No areas available',
              style: TextStyle(fontSize: 14, color: Colors.grey.shade400),
            ),
          ],
        ),
      );
    }

    final items = <Object>[
      if (assignedList.isNotEmpty)    ...[_SectionHeader('Assigned',     assignedList.length,    true),  ...assignedList],
      if (notAssignedList.isNotEmpty) ...[_SectionHeader('Not Assigned', notAssignedList.length, false), ...notAssignedList],
    ];

    return RefreshIndicator(
      onRefresh: _loadAll,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 100),
        itemCount: items.length,
        itemBuilder: (context, i) {
          final item = items[i];

          if (item is _SectionHeader) {
            return Padding(
              padding: EdgeInsets.only(top: i == 0 ? 6 : 18, bottom: 8, left: 2, right: 2),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: item.isAssigned ? greenLight : Colors.grey.shade100,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      item.isAssigned ? Icons.check_circle_outline_rounded : Icons.radio_button_unchecked_rounded,
                      size: 14,
                      color: item.isAssigned ? greenCheck : Colors.grey.shade500,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    item.label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: item.isAssigned ? greenCheck : Colors.grey.shade700,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
                    decoration: BoxDecoration(
                      color: item.isAssigned ? greenCheck : Colors.grey.shade400,
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

          final area      = item as Map<String, dynamic>;
          final id        = _idOf(area);
          final isAssign  = _assignedIds.contains(id);
          final areaName  = (area['area_name'] ?? '').toString();
          final city      = (area['city']      ?? '').toString();
          final district  = (area['district']  ?? '').toString();
          final subtitle  = [city, district].where((s) => s.isNotEmpty).join(', ');
          final pins      = area['pincodes'];
          final pinList   = pins is List ? pins.map((p) => p.toString()).take(3).join(', ') : '';

          final prev   = i > 0 ? items[i - 1] : null;
          final topGap = prev is _SectionHeader ? 0.0 : 4.0;

          return Padding(
            padding: EdgeInsets.only(top: topGap),
            child: GestureDetector(
              onTap: () => setState(() {
                if (isAssign) { _assignedIds.remove(id); } else { _assignedIds.add(id); }
              }),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isAssign ? const Color(0xFFA5D6A7) : Colors.transparent,
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: isAssign
                          ? greenCheck.withValues(alpha: 0.08)
                          : Colors.black.withValues(alpha: 0.04),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
                  child: Row(
                    children: [
                      Icon(
                        Icons.location_on_rounded,
                        color: isAssign ? greenCheck : Colors.grey.shade400,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      // text info
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(areaName, style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: isAssign ? const Color(0xFF1B5E20) : Colors.grey.shade900,
                            )),
                            if (subtitle.isNotEmpty || pinList.isNotEmpty)
                              Text(
                                [subtitle, if (pinList.isNotEmpty) 'Pin: $pinList']
                                    .where((s) => s.isNotEmpty).join('  •  '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 10.5, color: Colors.grey.shade500),
                              ),
                          ],
                        ),
                      ),
                      // checkbox
                      Checkbox(
                        value: isAssign,
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        activeColor: greenCheck,
                        checkColor: Colors.white,
                        side: BorderSide(color: isAssign ? greenCheck : Colors.grey.shade400, width: 1.5),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
                        onChanged: (v) => setState(() {
                          if (v == true) { _assignedIds.add(id); } else { _assignedIds.remove(id); }
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

// ── helpers ──────────────────────────────────────────────────────────────────

class _SectionHeader {
  final String label;
  final int    count;
  final bool   isAssigned;
  const _SectionHeader(this.label, this.count, this.isAssigned);
}

class _RoleBadge extends StatelessWidget {
  final String role;
  const _RoleBadge({required this.role});

  ({Color bg, Color text, String label}) get _style {
    switch (role) {
      case 'deli_staff': return (bg: const Color(0x33FFFFFF), text: Colors.white, label: 'Deli Staff');
      case 'salesman':   return (bg: const Color(0x33FFFFFF), text: Colors.white, label: 'Salesman');
      case 'admin':      return (bg: const Color(0x33FFFFFF), text: Colors.white, label: 'Admin');
      case 'manager':    return (bg: const Color(0x33FFFFFF), text: Colors.white, label: 'Manager');
      default:
        final label = role.isEmpty ? 'Staff' : role[0].toUpperCase() + role.substring(1);
        return (bg: const Color(0x33FFFFFF), text: Colors.white, label: label);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _style;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: s.bg, borderRadius: BorderRadius.circular(20)),
      child: Text(s.label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: s.text)),
    );
  }
}

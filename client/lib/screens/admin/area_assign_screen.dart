import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../services/api_service.dart';

class AreaAssignScreen extends StatefulWidget {
  const AreaAssignScreen({super.key});

  @override
  State<AreaAssignScreen> createState() => _AreaAssignScreenState();
}

class _AreaAssignScreenState extends State<AreaAssignScreen> {
  static const gold = Color(0xFFD7BE69);

  final _searchCtrl = TextEditingController();
  String _query = '';
  String _filter = 'all'; // 'all' | 'assigned' | 'not_assigned'
  bool _loading = false;
  List<Map<String, dynamic>> _staff = [];

  // employeeId → list of assigned area names
  Map<String, List<String>> _assignMap = {};

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

    final staffFuture   = ApiService.getEmployees(q: _query.isEmpty ? null : _query, perPage: 500);
    final assignsFuture = ApiService.getAllAreaAssigns();

    final staffList   = await staffFuture;
    final assignsList = await assignsFuture;

    if (!mounted) return;

    // Build employee_id → [area_name, ...] lookup
    final assignMap = <String, List<String>>{};
    for (final a in assignsList) {
      final empId = (a['employee_id'] ?? '').toString();
      final names = a['area_names'];
      if (empId.isNotEmpty && names is List) {
        assignMap[empId] = List<String>.from(names.map((n) => n.toString()));
      }
    }

    final normalized = staffList.map((e) {
      final role = (e['role'] ?? '').toString().trim().toLowerCase();
      final id   = (e['deli_id'] ?? e['mobile'] ?? '').toString();
      return <String, dynamic>{
        'id':     id,
        'name':   (e['name'] ?? '').toString(),
        'mobile': (e['mobile'] ?? '').toString(),
        'role':   role,
      };
    }).where((e) {
      return e['name'].toString().isNotEmpty || e['mobile'].toString().isNotEmpty;
    }).toList();

    setState(() {
      _staff     = normalized;
      _assignMap = assignMap;
      _loading   = false;
    });
  }

  List<Map<String, dynamic>> get _filteredStaff {
    if (_filter == 'assigned') return _staff.where((s) => (_assignMap[s['id']] ?? []).isNotEmpty).toList();
    if (_filter == 'not_assigned') return _staff.where((s) => (_assignMap[s['id']] ?? []).isEmpty).toList();
    return _staff;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text('Area Assign'),
        backgroundColor: gold,
        foregroundColor: Colors.white,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _loadAll,
        backgroundColor: gold,
        foregroundColor: Colors.white,
        tooltip: 'Refresh',
        child: const Icon(Icons.assignment_ind_rounded),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) {
                _query = v.trim().toLowerCase();
                _loadAll();
              },
              decoration: InputDecoration(
                hintText: 'Search staff by name or mobile...',
                prefixIcon: const Icon(Icons.search_rounded, color: gold),
                suffixIcon: _query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close_rounded, size: 18),
                        onPressed: () {
                          _searchCtrl.clear();
                          _query = '';
                          _loadAll();
                        },
                      )
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
                        color: _filter == f.$1 ? Colors.white : Colors.grey.shade700,
                      ),
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
                : _filteredStaff.isEmpty
                    ? _emptyState()
                    : RefreshIndicator(
                        onRefresh: _loadAll,
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(12, 6, 12, 80),
                          itemCount: _filteredStaff.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (context, i) {
                            final s = _filteredStaff[i];
                            final areas = _assignMap[s['id']] ?? [];
                            return _StaffCard(
                              staff: s,
                              assignedAreas: areas,
                              onTap: () async {
                                await context.push('/area-assign/${s['id']}', extra: s);
                                _loadAll(); // refresh counts after returning
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

  Widget _emptyState() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_query.isNotEmpty ? Icons.search_off_rounded : Icons.person_off_rounded, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text(
              _query.isNotEmpty ? 'No staff results for "$_query"' : 'No staff found',
              style: TextStyle(fontSize: 15, color: Colors.grey.shade500),
            ),
          ],
        ),
      );
}

class _StaffCard extends StatelessWidget {
  final Map<String, dynamic> staff;
  final List<String> assignedAreas;
  final VoidCallback onTap;

  const _StaffCard({required this.staff, required this.assignedAreas, required this.onTap});

  static const gold = Color(0xFFD7BE69);

  String get _initials {
    final name = (staff['name'] as String? ?? '').trim();
    final parts = name.split(' ').where((p) => p.isNotEmpty).toList();
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  @override
  Widget build(BuildContext context) {
    final hasAreas = assignedAreas.isNotEmpty;

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
              // Avatar with assigned-area count badge
              Stack(
                clipBehavior: Clip.none,
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: gold.withValues(alpha: 0.15),
                    child: Text(_initials, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: gold)),
                  ),
                  if (hasAreas)
                    Positioned(
                      right: -4,
                      top: -4,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(color: gold, shape: BoxShape.circle),
                        child: Text(
                          '${assignedAreas.length}',
                          style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Name + role badge
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            (staff['name'] ?? '').toString(),
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                          ),
                        ),
                        const SizedBox(width: 6),
                        _RoleBadge(role: (staff['role'] ?? '').toString()),
                      ],
                    ),
                    const SizedBox(height: 2),
                    // Mobile
                    Text(
                      (staff['mobile'] ?? '').toString(),
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                    ),
                    const SizedBox(height: 6),
                    // Area assignment info
                    if (!hasAreas)
                      Row(
                        children: [
                          Icon(Icons.location_off_rounded, size: 12, color: Colors.grey.shade400),
                          const SizedBox(width: 4),
                          Text('No areas assigned', style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
                        ],
                      )
                    else ...[
                      Row(
                        children: [
                          Icon(Icons.location_on_rounded, size: 12, color: gold),
                          const SizedBox(width: 4),
                          Text(
                            '${assignedAreas.length} area${assignedAreas.length == 1 ? '' : 's'} assigned',
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: gold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: assignedAreas.map((areaName) => Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: gold.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: gold.withValues(alpha: 0.30)),
                          ),
                          child: Text(areaName, style: const TextStyle(fontSize: 10, color: Color(0xFFB89A3E), fontWeight: FontWeight.w500)),
                        )).toList(),
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

class _RoleBadge extends StatelessWidget {
  final String role;
  const _RoleBadge({required this.role});

  ({Color bg, Color text, String label}) get _style {
    switch (role) {
      case 'deli_staff':
        return (bg: const Color(0xFFE3F0FF), text: const Color(0xFF1565C0), label: 'Deli Staff');
      case 'salesman':
        return (bg: const Color(0xFFFFF8E1), text: const Color(0xFFB89A3E), label: 'Salesman');
      case 'admin':
        return (bg: const Color(0xFFFFEBEE), text: const Color(0xFFC62828), label: 'Admin');
      case 'manager':
        return (bg: const Color(0xFFE8F5E9), text: const Color(0xFF2E7D32), label: 'Manager');
      default:
        return (
          bg: const Color(0xFFF3E5F5),
          text: const Color(0xFF6A1B9A),
          label: role.isEmpty ? 'Staff' : role[0].toUpperCase() + role.substring(1),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _style;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: s.bg, borderRadius: BorderRadius.circular(20)),
      child: Text(s.label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: s.text)),
    );
  }
}

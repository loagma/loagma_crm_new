import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../services/api_service.dart';

class MarketingAreaScreen extends StatefulWidget {
  const MarketingAreaScreen({super.key});

  @override
  State<MarketingAreaScreen> createState() => _MarketingAreaScreenState();
}

class _MarketingAreaScreenState extends State<MarketingAreaScreen> {
  static const gold = Color(0xFFD7BE69);

  final _searchCtrl = TextEditingController();
  Timer? _debounce;
  bool _loading = false;
  String _query = '';
  List<Map<String, dynamic>> _areas = [];

  // areaId → list of {name, role} employees this area is assigned to
  Map<int, List<Map<String, String>>> _assignees = {};

  @override
  void initState() {
    super.initState();
    _loadAreas();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  int _idOf(Map<String, dynamic> area) => int.tryParse((area['id'] ?? '').toString()) ?? 0;

  String _nameOf(Map<String, dynamic> area) => (area['area_name'] ?? '').toString();

  Future<void> _loadAreas() async {
    setState(() => _loading = true);
    final result = await ApiService.getAreas(q: _query.isEmpty ? null : _query);
    if (!mounted) return;
    final raw = result['data'];
    final list = raw is List
        ? raw.map((e) => Map<String, dynamic>.from(e as Map)).toList()
        : <Map<String, dynamic>>[];
    setState(() {
      _areas   = list;
      _loading = false;
    });
    // Load "assigned to" data separately so a slow employees/assigns fetch
    // never blocks (or crashes) the area list. The dev server is single-threaded.
    _loadAssignees();
  }

  // Builds areaId → [{name, role}] from area assignments + employees.
  // Defensive: any failure leaves cards showing "Not assigned" instead of crashing.
  Future<void> _loadAssignees() async {
    try {
      final assigns = await ApiService.getAllAreaAssigns();
      final staff   = await ApiService.getEmployees(perPage: 500);
      if (!mounted) return;

      final staffByMobile = <String, Map<String, dynamic>>{
        for (final e in staff) (e['mobile'] ?? '').toString(): e,
      };

      final assignees = <int, List<Map<String, String>>>{};
      for (final a in assigns) {
        final empId = (a['employee_id'] ?? '').toString();
        final emp   = staffByMobile[empId];
        if (emp == null) continue;
        final ids = a['area_ids'];
        if (ids is! List) continue;
        for (final r in ids) {
          final aid = int.tryParse(r.toString());
          if (aid == null) continue;
          assignees.putIfAbsent(aid, () => []).add({
            'name': (emp['name'] ?? '').toString(),
            'role': (emp['role'] ?? '').toString(),
          });
        }
      }

      if (mounted) setState(() => _assignees = assignees);
    } catch (_) {
      // leave _assignees as-is; cards show "Not assigned"
    }
  }

  void _onSearchChanged(String v) {
    _query = v.trim();
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _loadAreas);
  }

  void _toast(String msg, {bool success = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: success ? const Color(0xFF43A047) : Colors.red,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
    ));
  }

  // Returns areas whose name matches (case-insensitive, trimmed) — for the
  // duplicate-name guard.
  Future<List<Map<String, dynamic>>> _findAreasByName(String name) async {
    final target = name.trim().toLowerCase();
    final res = await ApiService.getAreas(q: name, perPage: 200);
    final data = res['data'];
    if (data is! List) return [];
    return data
        .map((e) => Map<String, dynamic>.from(e as Map))
        .where((a) => (a['area_name'] ?? '').toString().trim().toLowerCase() == target)
        .toList();
  }

  // Generic yes/no confirmation for "already exists, create anyway?".
  Future<bool?> _confirmDuplicate({required String title, required String message}) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        content: Text(message, style: const TextStyle(fontSize: 13.5)),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('No', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: gold, foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Yes, create'),
          ),
        ],
      ),
    );
  }

  Future<void> _showCreateOrEditDialog({Map<String, dynamic>? area}) async {
    final ctrl = TextEditingController(text: area == null ? '' : _nameOf(area));
    final formKey = GlobalKey<FormState>();
    final isEdit = area != null;

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text(isEdit ? 'Edit Area' : 'New Area', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: ctrl,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: 'Area Name *',
              prefixIcon: const Icon(Icons.location_on_outlined, color: gold),
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: gold, width: 2),
              ),
            ),
            validator: (v) => (v == null || v.trim().isEmpty) ? 'Area name is required' : null,
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              final name = ctrl.text.trim();
              Map<String, dynamic>? res;
              if (isEdit) {
                res = await ApiService.updateArea(_idOf(area), areaName: name);
              } else {
                // Duplicate-name guard: ask before creating a second area
                // with the same name.
                final existing = await _findAreasByName(name);
                if (!mounted) return;
                if (existing.isNotEmpty) {
                  final proceed = await _confirmDuplicate(
                    title: 'Area Already Exists',
                    message: '"$name" already exists '
                        '(${existing.length} area${existing.length == 1 ? '' : 's'}). '
                        'Do you want to create one more with the same name?',
                  );
                  if (proceed != true) return; // keep dialog open
                }
                res = await ApiService.createArea(name);
              }
              if (!mounted) return;
              if (res == null || res.containsKey('errors')) {
                _toast(isEdit ? 'Failed to update area' : 'Failed to create area', success: false);
                return;
              }
              if (ctx.mounted) Navigator.pop(ctx);
              _toast(isEdit ? 'Area "$name" updated' : 'Area "$name" created');
              _loadAreas();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: gold,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: Text(isEdit ? 'Update' : 'Create'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteArea(Map<String, dynamic> area) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Area'),
        content: Text('Delete "${_nameOf(area)}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final done = await ApiService.deleteArea(_idOf(area));
    if (!mounted) return;
    _toast(done ? 'Area "${_nameOf(area)}" deleted' : 'Failed to delete area', success: done);
    if (done) _loadAreas();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text('Marketing Area'),
        backgroundColor: gold,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
            child: TextField(
              controller: _searchCtrl,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: 'Search areas...',
                prefixIcon: const Icon(Icons.search_rounded, color: gold),
                suffixIcon: _query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close_rounded, size: 18),
                        onPressed: () {
                          _searchCtrl.clear();
                          _query = '';
                          _loadAreas();
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
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: gold))
                : _areas.isEmpty
                    ? _emptyState()
                    : RefreshIndicator(
                        onRefresh: _loadAreas,
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
                          itemCount: _areas.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (context, i) {
                            final area = _areas[i];
                            final pins = area['pincodes'] is List ? (area['pincodes'] as List).length : 0;
                            return _AreaCard(
                              area: area,
                              pincodeCount: pins,
                              assignees: _assignees[_idOf(area)] ?? const [],
                              onTap: () async {
                                final changed = await context.push('/marketing-area/${_idOf(area)}', extra: area);
                                if (changed == true) _loadAreas();
                              },
                              onEdit: () => _showCreateOrEditDialog(area: area),
                              onDelete: () => _deleteArea(area),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showCreateOrEditDialog(),
        backgroundColor: gold,
        foregroundColor: Colors.white,
        child: const Icon(Icons.add_rounded),
      ),
    );
  }

  Widget _emptyState() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_query.isNotEmpty ? Icons.search_off_rounded : Icons.location_off_rounded, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text(_query.isNotEmpty ? 'No results for "$_query"' : 'No areas yet', style: TextStyle(fontSize: 15, color: Colors.grey.shade500)),
            const SizedBox(height: 4),
            if (_query.isEmpty) Text('Tap + to add the first area', style: TextStyle(fontSize: 13, color: Colors.grey.shade400)),
          ],
        ),
      );
}

class _AreaCard extends StatelessWidget {
  final Map<String, dynamic> area;
  final int pincodeCount;
  final List<Map<String, String>> assignees;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _AreaCard({
    required this.area,
    required this.pincodeCount,
    required this.assignees,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final name = (area['area_name'] ?? '').toString();
    final id = (area['id'] ?? '').toString();

    return GestureDetector(
      onTap: onTap,
      child: Card(
        color: Colors.white,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 1.5,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0xFFD7BE69).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.location_on_rounded, color: Color(0xFFD7BE69), size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Marketing Area',
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.3,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        Text(name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 2),
                        Text('ID: $id --- $pincodeCount pincodes ', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    onSelected: (v) {
                      if (v == 'edit') onEdit();
                      if (v == 'delete') onDelete();
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'edit', child: Text('Edit')),
                      PopupMenuItem(value: 'delete', child: Text('Delete')),
                    ],
                  ),
                ],
              ),
              // ── Assigned-to row ──────────────────────────────────────────
              if (assignees.isNotEmpty) ...[
                const SizedBox(height: 10),
                const Divider(height: 1, color: Color(0xFFEEEEEE)),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.people_alt_rounded, size: 13, color: Colors.grey.shade500),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Wrap(
                        spacing: 5, runSpacing: 5,
                        children: assignees.map((e) {
                          final role = (e['role'] ?? '').replaceAll('_', ' ');
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFFD7BE69).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: const Color(0xFFD7BE69).withValues(alpha: 0.35)),
                            ),
                            child: Text(
                              role.isEmpty ? (e['name'] ?? '') : '${e['name']} · $role',
                              style: const TextStyle(
                                  fontSize: 10, fontWeight: FontWeight.w600,
                                  color: Color(0xFF8A6D1B)),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ),
              ] else ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.person_off_outlined, size: 12, color: Colors.grey.shade400),
                    const SizedBox(width: 6),
                    Text('Not assigned to anyone',
                        style: TextStyle(fontSize: 10.5, color: Colors.grey.shade400,
                            fontStyle: FontStyle.italic)),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

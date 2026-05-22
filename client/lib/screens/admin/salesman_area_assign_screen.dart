import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';

import '../../services/api_service.dart';

class SalesmanAreaAssignScreen extends StatefulWidget {
  final Map<String, dynamic> salesman;

  const SalesmanAreaAssignScreen({super.key, required this.salesman});

  @override
  State<SalesmanAreaAssignScreen> createState() => _SalesmanAreaAssignScreenState();
}

class _SalesmanAreaAssignScreenState extends State<SalesmanAreaAssignScreen> {
  static const gold = Color(0xFFD7BE69);

  final Set<int> _assignedIds = {};
  bool _loading = false;
  bool _saving = false;
  List<Map<String, dynamic>> _areas = [];
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  List<Map<String, dynamic>> get _filteredAreas {
    if (_searchQuery.isEmpty) return _areas;
    final q = _searchQuery.toLowerCase();
    return _areas.where((a) {
      if ((a['area_name'] ?? '').toString().toLowerCase().contains(q)) return true;
      if ((a['city'] ?? '').toString().toLowerCase().contains(q)) return true;
      if ((a['district'] ?? '').toString().toLowerCase().contains(q)) return true;
      if ((a['state'] ?? '').toString().toLowerCase().contains(q)) return true;
      final pins = a['pincodes'];
      if (pins is List) {
        return pins.any((p) => p.toString().toLowerCase().contains(q));
      }
      return false;
    }).toList();
  }

  String get _employeeId => (widget.salesman['id'] ?? widget.salesman['deli_id'] ?? '').toString();

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

    final areaFuture = ApiService.getAreas(perPage: 200);
    final assignFuture = ApiService.getAreaAssign(_employeeId);
    final areaResult = await areaFuture;
    final assignResult = await assignFuture;

    if (!mounted) return;

    final raw = areaResult['data'];
    final list = raw is List
        ? raw.map((e) => Map<String, dynamic>.from(e as Map)).toList()
        : <Map<String, dynamic>>[];

    final Set<int> preSelected = {};
    if (assignResult != null && assignResult['data'] is Map) {
      final data = assignResult['data'] as Map;
      final ids = data['area_ids'];
      if (ids is List) {
        for (final id in ids) {
          final n = int.tryParse(id.toString());
          if (n != null) preSelected.add(n);
        }
      }
    }

    setState(() {
      _areas = list;
      _assignedIds
        ..clear()
        ..addAll(preSelected);
      _loading = false;
    });
  }

  int _idOf(Map<String, dynamic> area) => int.tryParse((area['id'] ?? '').toString()) ?? 0;

  Future<void> _assign() async {
    if (_saving) return;
    setState(() => _saving = true);

    final selectedAreas = _areas.where((a) => _assignedIds.contains(_idOf(a))).toList();
    final areaIds = selectedAreas.map((a) => _idOf(a)).toList();
    final areaNames = selectedAreas.map((a) => (a['area_name'] ?? '').toString()).toList();

    final res = await ApiService.saveAreaAssign(_employeeId, areaIds, areaNames);

    if (!mounted) return;
    setState(() => _saving = false);

    if (res == null || res.containsKey('errors')) {
      Fluttertoast.showToast(msg: 'Failed to save assignment');
    } else {
      Fluttertoast.showToast(
        msg: areaIds.isEmpty
            ? 'Assignment cleared'
            : '${areaIds.length} area(s) assigned successfully',
        backgroundColor: Colors.green,
        textColor: Colors.white,
      );
    }
  }

  String get _initials {
    final name = (widget.salesman['name'] as String? ?? '').trim();
    final parts = name.split(' ').where((p) => p.isNotEmpty).toList();
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.salesman['name'] as String? ?? 'Staff';
    final mobile = widget.salesman['mobile'] as String? ?? '';

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: Text(name),
        backgroundColor: gold,
        foregroundColor: Colors.white,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _saving ? null : _assign,
        backgroundColor: gold,
        foregroundColor: Colors.white,
        tooltip: 'Assign',
        child: _saving
            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
            : const Icon(Icons.assignment_turned_in_rounded, size: 26),
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: gold.withValues(alpha: 0.1),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: gold.withValues(alpha: 0.2),
                  child: Text(
                    _initials,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: gold),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: gold)),
                      if (mobile.isNotEmpty)
                        Text(mobile, style: const TextStyle(fontSize: 11, color: Color(0xFFC09E3E))),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: gold.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${_assignedIds.length} assigned',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: gold),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _searchQuery = v.trim()),
              decoration: InputDecoration(
                hintText: 'Search by area, pincode, city, district, state...',
                hintStyle: const TextStyle(fontSize: 13),
                prefixIcon: const Icon(Icons.search_rounded, color: gold),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: gold),
                ),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: gold))
                : RefreshIndicator(
                    onRefresh: _loadAll,
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 80),
                      itemCount: _filteredAreas.isEmpty && _searchQuery.isNotEmpty
                          ? 1
                          : _filteredAreas.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, i) {
                        if (_filteredAreas.isEmpty && _searchQuery.isNotEmpty) {
                          return const Center(
                            child: Padding(
                              padding: EdgeInsets.only(top: 40),
                              child: Text('No areas found', style: TextStyle(color: Colors.grey)),
                            ),
                          );
                        }
                        final area = _filteredAreas[i];
                        final id = _idOf(area);
                        final assigned = _assignedIds.contains(id);

                        return Card(
                          color: Colors.white,
                          margin: EdgeInsets.zero,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 1.5,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            child: Row(
                              children: [
                                Container(
                                  width: 42,
                                  height: 42,
                                  decoration: BoxDecoration(
                                    color: assigned ? gold.withValues(alpha: 0.2) : Colors.grey.shade100,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(
                                    Icons.location_on_rounded,
                                    color: assigned ? gold : Colors.grey.shade400,
                                    size: 22,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text((area['area_name'] ?? '').toString(), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                                      const SizedBox(height: 2),
                                      Text(
                                        assigned ? 'Assigned' : 'Not assigned',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: assigned ? Colors.green : Colors.grey.shade500,
                                          fontWeight: assigned ? FontWeight.w600 : FontWeight.normal,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Checkbox(
                                  value: assigned,
                                  activeColor: gold,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                  onChanged: (v) => setState(() {
                                    if (v == true) {
                                      _assignedIds.add(id);
                                    } else {
                                      _assignedIds.remove(id);
                                    }
                                  }),
                                ),
                              ],
                            ),
                          ),
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

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
  List<Map<String, dynamic>> _areas = [];

  @override
  void initState() {
    super.initState();
    _loadAreas();
  }

  Future<void> _loadAreas() async {
    setState(() => _loading = true);
    final result = await ApiService.getAreas(perPage: 200);
    if (!mounted) return;
    final raw = result['data'];
    final list = raw is List
        ? raw.map((e) => Map<String, dynamic>.from(e as Map)).toList()
        : <Map<String, dynamic>>[];
    setState(() {
      _areas = list;
      _loading = false;
    });
  }

  int _idOf(Map<String, dynamic> area) => int.tryParse((area['id'] ?? '').toString()) ?? 0;

  void _assign() {
    final assigned = _areas
        .where((a) => _assignedIds.contains(_idOf(a)))
        .map((a) => (a['area_name'] ?? '').toString())
        .toList();
    Fluttertoast.showToast(
      msg: assigned.isEmpty ? 'No areas selected' : 'Assigned: ${assigned.join(', ')}',
    );
  }

  String get _initials {
    final name = (widget.salesman['name'] as String? ?? '').trim();
    final parts = name.split(' ');
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.salesman['name'] as String? ?? 'Salesman';
    final mobile = widget.salesman['mobile'] as String? ?? '';

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: Text(name),
        backgroundColor: gold,
        foregroundColor: Colors.white,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _assign,
        backgroundColor: gold,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.assignment_turned_in_rounded),
        label: const Text('Assign', style: TextStyle(fontWeight: FontWeight.w600)),
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
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: gold))
                : RefreshIndicator(
                    onRefresh: _loadAreas,
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
                      itemCount: _areas.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, i) {
                        final area = _areas[i];
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

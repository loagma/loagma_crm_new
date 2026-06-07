import 'package:flutter/material.dart';

import '../../services/api_service.dart';
import '../../services/user_service.dart';

class MyTeamScreen extends StatefulWidget {
  const MyTeamScreen({super.key});

  @override
  State<MyTeamScreen> createState() => _MyTeamScreenState();
}

class _MyTeamScreenState extends State<MyTeamScreen> {
  static const gold = Color(0xFFD7BE69);

  bool   _loading = true;
  String _error   = '';

  // salesman id → {name, mobile, areas: [areaName,...]}
  List<Map<String, dynamic>> _team = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = ''; });

    final mobile = UserService.currentMobile ?? '';
    if (mobile.isEmpty) {
      setState(() { _loading = false; _error = 'Not logged in'; });
      return;
    }

    try {
      final assignRes  = await ApiService.getAreaAssign(mobile);
      final allAssigns = await ApiService.getAllAreaAssigns();
      final allStaff   = await ApiService.getEmployees(perPage: 500);
      if (!mounted) return;

      // My area IDs
      final myAreaIds = <int>{};
      final myAreaNames = <int, String>{};
      final assignData = assignRes?['data'];
      if (assignData is Map) {
        final ids   = assignData['area_ids'];
        final names = assignData['area_names'];
        if (ids is List && names is List) {
          for (var i = 0; i < ids.length; i++) {
            final n = int.tryParse(ids[i].toString());
            if (n != null) {
              myAreaIds.add(n);
              myAreaNames[n] = i < names.length ? names[i].toString() : 'Area $n';
            }
          }
        }
      }

      // Build staff lookup (salesmen only)
      final staffById = <String, Map<String, dynamic>>{};
      for (final e in allStaff) {
        final role = (e['role'] ?? '').toString().toLowerCase();
        if (role != 'salesman') continue;
        final id = (e['mobile'] ?? e['deli_id'] ?? '').toString();
        staffById[id] = e;
      }

      // salesman id → set of area names they share with me
      final teamMap = <String, Set<String>>{};
      for (final assign in allAssigns) {
        final empId  = (assign['employee_id'] ?? '').toString();
        if (!staffById.containsKey(empId)) continue;

        final empAreaIds = assign['area_ids'];
        if (empAreaIds is! List) continue;

        for (final aId in empAreaIds) {
          final n = int.tryParse(aId.toString());
          if (n == null || !myAreaIds.contains(n)) continue;
          teamMap.putIfAbsent(empId, () => {});
          teamMap[empId]!.add(myAreaNames[n] ?? 'Area $n');
        }
      }

      final team = teamMap.entries.map((entry) {
        final emp = staffById[entry.key]!;
        return {
          'id':     entry.key,
          'name':   (emp['name']   ?? '').toString(),
          'mobile': (emp['mobile'] ?? '').toString(),
          'areas':  entry.value.toList()..sort(),
        };
      }).toList()
        ..sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));

      setState(() { _team = team; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = 'Failed to load team'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text('My Team'),
        backgroundColor: gold,
        foregroundColor: Colors.white,
        actions: [
          IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: gold))
          : _error.isNotEmpty
              ? Center(child: Text(_error, style: const TextStyle(color: Colors.red)))
              : _team.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.group_off_rounded, size: 64, color: Colors.grey.shade300),
                          const SizedBox(height: 12),
                          Text('No salesmen in your areas yet',
                              style: TextStyle(fontSize: 16, color: Colors.grey.shade500)),
                          const SizedBox(height: 6),
                          Text('Ask admin to assign salesmen to your areas',
                              style: TextStyle(fontSize: 13, color: Colors.grey.shade400),
                              textAlign: TextAlign.center),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.all(14),
                        itemCount: _team.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (ctx, i) => _SalesmanCard(member: _team[i]),
                      ),
                    ),
    );
  }
}

class _SalesmanCard extends StatelessWidget {
  final Map<String, dynamic> member;
  const _SalesmanCard({required this.member});

  static const gold = Color(0xFFD7BE69);

  String get _initials {
    final name  = (member['name'] as String? ?? '').trim();
    final parts = name.split(' ').where((p) => p.isNotEmpty).toList();
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  @override
  Widget build(BuildContext context) {
    final areas  = (member['areas'] as List?)?.cast<String>() ?? [];

    return Card(
      color: Colors.white,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 1.5,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: gold.withValues(alpha: 0.15),
              child: Text(_initials,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: gold)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text((member['name'] ?? '').toString(),
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600))),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF8E1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text('Salesman',
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: gold)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text((member['mobile'] ?? '').toString(),
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                  if (areas.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 4, runSpacing: 4,
                      children: areas.map((a) => Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: gold.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: gold.withValues(alpha: 0.30)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.location_on_rounded, size: 10, color: Color(0xFFB89A3E)),
                            const SizedBox(width: 3),
                            Text(a, style: const TextStyle(fontSize: 10,
                                color: Color(0xFFB89A3E), fontWeight: FontWeight.w500)),
                          ],
                        ),
                      )).toList(),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

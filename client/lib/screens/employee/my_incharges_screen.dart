import 'package:flutter/material.dart';

import '../../services/api_service.dart';
import '../../services/user_service.dart';

class MyInchargesScreen extends StatefulWidget {
  const MyInchargesScreen({super.key});

  @override
  State<MyInchargesScreen> createState() => _MyInchargesScreenState();
}

class _MyInchargesScreenState extends State<MyInchargesScreen> {
  static const purpleDark = Color(0xFFD7BE69);

  bool   _loading = true;
  String _error   = '';

  List<Map<String, dynamic>> _incharges = [];

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
      final assignRes  = await ApiService.getInchargeAssign(mobile);
      final allStaff   = await ApiService.getEmployees(perPage: 500);
      final allAreaAssigns = await ApiService.getAllAreaAssigns();
      if (!mounted) return;

      // My assigned incharge IDs
      final myInchargeIds = <int>[];
      final assignData = assignRes?['data'];
      if (assignData is Map) {
        final ids = assignData['incharge_ids'];
        if (ids is List) {
          for (final id in ids) {
            final n = int.tryParse(id.toString());
            if (n != null) myInchargeIds.add(n);
          }
        }
      }

      // Build employee lookup
      final staffById = <String, Map<String, dynamic>>{};
      for (final e in allStaff) {
        final id = (e['deli_id'] ?? e['mobile'] ?? '').toString();
        staffById[id] = e;
      }

      // Build area map: employee_id → area names
      final areaMap = <String, List<String>>{};
      for (final a in allAreaAssigns) {
        final empId = (a['employee_id'] ?? '').toString();
        final names = a['area_names'];
        if (empId.isNotEmpty && names is List) {
          areaMap[empId] = List<String>.from(names.map((n) => n.toString()));
        }
      }

      final incharges = <Map<String, dynamic>>[];
      for (final incId in myInchargeIds) {
        // Find the employee by deli_id or numeric id match
        Map<String, dynamic>? emp;
        for (final e in allStaff) {
          final deliId = int.tryParse((e['deli_id'] ?? '').toString());
          final mobId  = int.tryParse((e['mobile']  ?? '').toString());
          if (deliId == incId || mobId == incId) { emp = e; break; }
        }
        final empId = (emp?['mobile'] ?? emp?['deli_id'] ?? incId).toString();
        incharges.add({
          'id':     empId,
          'name':   (emp?['name']   ?? 'Incharge $incId').toString(),
          'mobile': (emp?['mobile'] ?? '').toString(),
          'areas':  areaMap[empId] ?? <String>[],
        });
      }

      setState(() { _incharges = incharges; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = 'Failed to load incharges'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text('My Incharges'),
        backgroundColor: purpleDark,
        foregroundColor: Colors.white,
        actions: [
          IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: purpleDark))
          : _error.isNotEmpty
              ? Center(child: Text(_error, style: const TextStyle(color: Colors.red)))
              : _incharges.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.supervisor_account_outlined,
                              size: 64, color: Colors.grey.shade300),
                          const SizedBox(height: 12),
                          Text('No incharges assigned to you',
                              style: TextStyle(fontSize: 16, color: Colors.grey.shade500)),
                          const SizedBox(height: 6),
                          Text('Ask your admin to assign incharges',
                              style: TextStyle(fontSize: 13, color: Colors.grey.shade400)),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.all(14),
                        itemCount: _incharges.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (ctx, i) =>
                            _InchargeCard(incharge: _incharges[i]),
                      ),
                    ),
    );
  }
}

class _InchargeCard extends StatelessWidget {
  final Map<String, dynamic> incharge;
  const _InchargeCard({required this.incharge});

  static const purpleDark  = Color(0xFFD7BE69);
  static const purpleLight = Color(0xFFFFF8E1);
  static const gold        = Color(0xFFD7BE69);

  String get _initials {
    final name  = (incharge['name'] as String? ?? '').trim();
    final parts = name.split(' ').where((p) => p.isNotEmpty).toList();
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  @override
  Widget build(BuildContext context) {
    final areas = (incharge['areas'] as List?)?.cast<String>() ?? [];

    return Card(
      color: Colors.white,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: purpleDark.withValues(alpha: 0.15), width: 1),
      ),
      elevation: 1.5,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: purpleLight,
                  child: Text(_initials,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.bold, color: purpleDark)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text((incharge['name'] ?? '').toString(),
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                      Text((incharge['mobile'] ?? '').toString(),
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                      color: purpleLight, borderRadius: BorderRadius.circular(20)),
                  child: const Text('Incharge',
                      style: TextStyle(
                          fontSize: 10, fontWeight: FontWeight.w600, color: purpleDark)),
                ),
              ],
            ),

            // Areas
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.location_on_rounded, size: 13, color: gold),
                const SizedBox(width: 4),
                Text(
                  areas.isEmpty
                      ? 'No areas assigned'
                      : '${areas.length} area${areas.length == 1 ? '' : 's'}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: areas.isEmpty ? Colors.grey : const Color(0xFFB89A3E),
                  ),
                ),
              ],
            ),
            if (areas.isNotEmpty) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 4, runSpacing: 4,
                children: areas.map((a) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: gold.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: gold.withValues(alpha: 0.30)),
                  ),
                  child: Text(a,
                      style: const TextStyle(
                          fontSize: 10, color: Color(0xFFB89A3E), fontWeight: FontWeight.w500)),
                )).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

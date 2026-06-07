import 'package:flutter/material.dart';

import '../../services/api_service.dart';
import '../../services/user_service.dart';

class MyInchargesScreen extends StatefulWidget {
  const MyInchargesScreen({super.key});

  @override
  State<MyInchargesScreen> createState() => _MyInchargesScreenState();
}

class _MyInchargesScreenState extends State<MyInchargesScreen> {
  static const gold = Color(0xFFD7BE69);

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
      final results = await Future.wait([
        ApiService.getInchargeAssign(mobile),
        ApiService.getEmployees(perPage: 500),
        ApiService.getAllAreaAssigns(),
      ]);

      if (!mounted) return;

      final assignRes      = results[0] as Map<String, dynamic>?;
      final allStaff       = results[1] as List<Map<String, dynamic>>;
      final allAreaAssigns = results[2] as List<Map<String, dynamic>>;

      // ── Parse my assigned incharge IDs ──────────────────────────────────
      final myInchargeIds = <int>{};
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

      if (myInchargeIds.isEmpty) {
        setState(() { _incharges = []; _loading = false; });
        return;
      }

      // ── Build lookup: empKey → employee ─────────────────────────────────
      // empKey = mobile string (preferred) or deli_id string
      final allStaffByKey = <String, Map<String, dynamic>>{};
      for (final e in allStaff) {
        final mob  = (e['mobile']  ?? '').toString().trim();
        final deli = (e['deli_id'] ?? '').toString().trim();
        if (mob.isNotEmpty)  allStaffByKey[mob]  = e;
        if (deli.isNotEmpty) allStaffByKey[deli] = e;
      }

      // ── Build area lookups keyed by employee_id (same key as stored) ────
      // employee_id in area_assign_crm is stored as int (the mobile number)
      final empAreaIds   = <String, Set<int>>{};   // key → set of area int IDs
      final empAreaNames = <String, List<String>>{}; // key → area name list

      for (final a in allAreaAssigns) {
        final empKey = (a['employee_id'] ?? '').toString().trim();
        if (empKey.isEmpty || empKey == '0') continue;

        final rawIds   = a['area_ids']   as List?;
        final rawNames = a['area_names'] as List?;

        if (rawIds != null) {
          empAreaIds[empKey] = rawIds
              .map((x) => int.tryParse(x.toString()))
              .whereType<int>()
              .toSet();
        }
        if (rawNames != null) {
          empAreaNames[empKey] =
              rawNames.map((n) => n.toString()).toList();
        }
      }

      // ── Build salesman list (role = salesman) ────────────────────────────
      final salesmen = <Map<String, dynamic>>[];
      for (final e in allStaff) {
        final role = (e['role'] ?? '').toString().toLowerCase();
        if (role == 'salesman') salesmen.add(e);
      }

      // ── Build each incharge entry ────────────────────────────────────────
      final incharges = <Map<String, dynamic>>[];

      for (final incId in myInchargeIds) {
        // Find the employee whose mobile or deli_id equals incId
        Map<String, dynamic>? emp;
        final incKey = incId.toString();
        emp = allStaffByKey[incKey]; // try mobile/deli_id match directly

        if (emp == null) {
          // fallback: linear scan
          for (final e in allStaff) {
            final mobInt  = int.tryParse((e['mobile']  ?? '').toString());
            final deliInt = int.tryParse((e['deli_id'] ?? '').toString());
            if (mobInt == incId || deliInt == incId) { emp = e; break; }
          }
        }

        final empMobile = (emp?['mobile']  ?? '').toString().trim();
        final empDeliId = (emp?['deli_id'] ?? '').toString().trim();

        // Area lookup key: try mobile first, then deli_id, then incId
        String? areaKey;
        if (empAreaIds.containsKey(empMobile) && empMobile.isNotEmpty) {
          areaKey = empMobile;
        } else if (empAreaIds.containsKey(empDeliId) && empDeliId.isNotEmpty) {
          areaKey = empDeliId;
        } else if (empAreaIds.containsKey(incKey)) {
          areaKey = incKey;
        }

        final incAreaIds   = areaKey != null ? (empAreaIds[areaKey]   ?? <int>{}) : <int>{};
        final incAreaNames = areaKey != null ? (empAreaNames[areaKey] ?? <String>[]) : <String>[];

        // ── Find salesmen in this incharge's areas ─────────────────────────
        final team = <Map<String, dynamic>>[];
        if (incAreaIds.isNotEmpty) {
          for (final s in salesmen) {
            final salMobile = (s['mobile']  ?? '').toString().trim();
            final salDeli   = (s['deli_id'] ?? '').toString().trim();

            // Find this salesman's area IDs
            Set<int>? salAreaIds;
            if (empAreaIds.containsKey(salMobile) && salMobile.isNotEmpty) {
              salAreaIds = empAreaIds[salMobile];
            } else if (empAreaIds.containsKey(salDeli) && salDeli.isNotEmpty) {
              salAreaIds = empAreaIds[salDeli];
            }

            if (salAreaIds == null || salAreaIds.isEmpty) continue;

            // Shared area IDs (salesman in incharge's area)
            final sharedIds = salAreaIds.intersection(incAreaIds);
            if (sharedIds.isEmpty) continue;

            // Get shared area names
            final sharedNames = <String>[];
            final rawSalIds   = (allAreaAssigns
                .firstWhere(
                  (a) {
                    final k = (a['employee_id'] ?? '').toString().trim();
                    return k == salMobile || k == salDeli;
                  },
                  orElse: () => {},
                )['area_ids'] as List?) ?? [];
            final rawSalNames = (allAreaAssigns
                .firstWhere(
                  (a) {
                    final k = (a['employee_id'] ?? '').toString().trim();
                    return k == salMobile || k == salDeli;
                  },
                  orElse: () => {},
                )['area_names'] as List?) ?? [];

            for (var i = 0; i < rawSalIds.length; i++) {
              final n = int.tryParse(rawSalIds[i].toString());
              if (n != null && sharedIds.contains(n) && i < rawSalNames.length) {
                sharedNames.add(rawSalNames[i].toString());
              }
            }

            team.add({
              'name':   (s['name']   ?? '').toString(),
              'mobile': salMobile,
              'areas':  sharedNames,
            });
          }
          team.sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));
        }

        incharges.add({
          'name':   (emp?['name'] ?? 'Incharge $incId').toString(),
          'mobile': empMobile,
          'areas':  incAreaNames,
          'team':   team,
        });
      }

      setState(() { _incharges = incharges; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = 'Failed to load: $e'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text('My Incharges'),
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
                        separatorBuilder: (_, _) => const SizedBox(height: 12),
                        itemBuilder: (ctx, i) =>
                            _InchargeCard(incharge: _incharges[i]),
                      ),
                    ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _InchargeCard extends StatelessWidget {
  final Map<String, dynamic> incharge;
  const _InchargeCard({required this.incharge});

  static const gold       = Color(0xFFD7BE69);
  static const goldLight  = Color(0xFFFFF8E1);
  static const purple     = Color(0xFF7B68AA);

  String _initials(String name) {
    final parts = name.trim().split(' ').where((p) => p.isNotEmpty).toList();
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  @override
  Widget build(BuildContext context) {
    final name   = (incharge['name']   ?? '').toString();
    final mobile = (incharge['mobile'] ?? '').toString();
    final areas  = (incharge['areas']  as List?)?.cast<String>() ?? [];
    final team   = (incharge['team']   as List<dynamic>?)
                       ?.map((e) => e as Map<String, dynamic>)
                       .toList() ?? [];

    return Card(
      color: Colors.white,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: gold.withValues(alpha: 0.20), width: 1),
      ),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            // ── Incharge header ────────────────────────────────────────────
            Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: goldLight,
                  child: Text(_initials(name),
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.bold, color: gold)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name,
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w700)),
                      if (mobile.isNotEmpty)
                        Text(mobile,
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey.shade500)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                      color: goldLight, borderRadius: BorderRadius.circular(20)),
                  child: const Text('Incharge',
                      style: TextStyle(
                          fontSize: 10, fontWeight: FontWeight.w600, color: gold)),
                ),
              ],
            ),

            // ── Areas ─────────────────────────────────────────────────────
            const SizedBox(height: 10),
            _sectionLabel(Icons.location_on_rounded, gold,
                areas.isEmpty ? 'No areas assigned' : '${areas.length} Area${areas.length == 1 ? '' : 's'}'),
            if (areas.isNotEmpty) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 4, runSpacing: 4,
                children: areas.map((a) => _chip(a, gold)).toList(),
              ),
            ],

            // ── Team (salesmen) ───────────────────────────────────────────
            const SizedBox(height: 10),
            const Divider(height: 1, color: Color(0xFFEEEEEE)),
            const SizedBox(height: 10),
            _sectionLabel(Icons.groups_rounded, purple,
                team.isEmpty
                    ? 'No salesmen in areas'
                    : '${team.length} Salesman${team.length == 1 ? '' : 's'}',
                color: team.isEmpty ? Colors.grey : purple),

            if (team.isNotEmpty) ...[
              const SizedBox(height: 8),
              ...team.map((s) => _SalesmanRow(salesman: s)),
            ],

          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(IconData icon, Color iconColor, String text,
      {Color? color}) {
    return Row(
      children: [
        Icon(icon, size: 13, color: iconColor),
        const SizedBox(width: 5),
        Text(text,
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: color ?? iconColor)),
      ],
    );
  }

  Widget _chip(String label, Color base) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: base.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: base.withValues(alpha: 0.30)),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 10,
                color: base.withValues(alpha: 0.85),
                fontWeight: FontWeight.w500)),
      );
}

// ─────────────────────────────────────────────────────────────────────────────

class _SalesmanRow extends StatelessWidget {
  final Map<String, dynamic> salesman;
  const _SalesmanRow({required this.salesman});

  static const gold   = Color(0xFFD7BE69);
  static const purple = Color(0xFF7B68AA);

  String _initials(String name) {
    final parts = name.trim().split(' ').where((p) => p.isNotEmpty).toList();
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  @override
  Widget build(BuildContext context) {
    final name   = (salesman['name']   ?? '').toString();
    final mobile = (salesman['mobile'] ?? '').toString();
    final areas  = (salesman['areas']  as List?)?.cast<String>() ?? [];

    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: purple.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: purple.withValues(alpha: 0.12)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: purple.withValues(alpha: 0.12),
              child: Text(_initials(name),
                  style: const TextStyle(
                      fontSize: 11, fontWeight: FontWeight.bold, color: purple)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(name,
                            style: const TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w600)),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF8E1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Text('Salesman',
                            style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w600,
                                color: gold)),
                      ),
                    ],
                  ),
                  if (mobile.isNotEmpty)
                    Text(mobile,
                        style: TextStyle(
                            fontSize: 10, color: Colors.grey.shade500)),
                  if (areas.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 4, runSpacing: 3,
                      children: areas
                          .map((a) => Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: gold.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(5),
                                  border: Border.all(
                                      color: gold.withValues(alpha: 0.25)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.location_on_rounded,
                                        size: 9, color: Color(0xFFB89A3E)),
                                    const SizedBox(width: 2),
                                    Text(a,
                                        style: const TextStyle(
                                            fontSize: 9,
                                            color: Color(0xFFB89A3E),
                                            fontWeight: FontWeight.w500)),
                                  ],
                                ),
                              ))
                          .toList(),
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

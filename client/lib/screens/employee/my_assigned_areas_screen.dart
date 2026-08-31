import 'package:flutter/material.dart';

import '../../services/api_service.dart';
import '../../services/user_service.dart';

class MyAssignedAreasScreen extends StatefulWidget {
  const MyAssignedAreasScreen({super.key});

  @override
  State<MyAssignedAreasScreen> createState() => _MyAssignedAreasScreenState();
}

class _MyAssignedAreasScreenState extends State<MyAssignedAreasScreen> {
  static const gold = Color(0xFFD7BE69);

  bool   _loading = true;
  String _error   = '';

  List<Map<String, dynamic>>         _myAreas   = [];
  // areaId → list of salesman maps {name, mobile}
  Map<int, List<Map<String, dynamic>>> _salesmen = {};

  final Set<int> _expanded = {};

  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';

  // Area name, a pincode inside it, or (for an incharge) any salesman
  // covering it — so typing any of the three finds the right area.
  List<Map<String, dynamic>> get _filteredAreas {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _myAreas;
    return _myAreas.where((a) {
      final name = (a['name'] as String? ?? '').toLowerCase();
      if (name.contains(q)) return true;
      final pincodes = (a['pincodes'] as List?) ?? [];
      if (pincodes.any((p) => p.toString().toLowerCase().contains(q))) return true;
      final staff = _salesmen[a['id'] as int] ?? [];
      return staff.any((s) => (s['name'] as String? ?? '').toLowerCase().contains(q));
    }).toList();
  }

  bool get _isIncharge =>
      (UserService.currentRole ?? '').toLowerCase() == 'incharge';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = ''; });

    final mobile = UserService.currentMobile ?? '';
    if (mobile.isEmpty) {
      setState(() { _loading = false; _error = 'Not logged in'; });
      return;
    }

    try {
      final assignRes = await ApiService.getAreaAssign(mobile);
      if (!mounted) return;

      final assignData = assignRes?['data'];
      final myAreaIds  = <int>[];
      final myAreaNames = <String>[];

      if (assignData is Map) {
        final ids   = assignData['area_ids'];
        final names = assignData['area_names'];
        if (ids is List) {
          for (final id in ids) {
            final n = int.tryParse(id.toString());
            if (n != null) myAreaIds.add(n);
          }
        }
        if (names is List) {
          for (final n in names) { myAreaNames.add(n.toString()); }
        }
      }

      // Pincodes per area, so the search bar can match a pincode too — a
      // handful of areas at most (there are only ~25 in the whole system),
      // so fetching them all up front is cheap and avoids a per-tap fetch.
      final pincodesById = <int, List<String>>{};
      if (myAreaIds.isNotEmpty) {
        final details = await Future.wait(myAreaIds.map(ApiService.getArea));
        if (!mounted) return;
        for (var i = 0; i < myAreaIds.length; i++) {
          final raw = details[i]?['pincodes'];
          pincodesById[myAreaIds[i]] = raw is List ? raw.map((e) => e.toString()).toList() : [];
        }
      }

      // Build area cards with names
      final areas = <Map<String, dynamic>>[];
      for (var i = 0; i < myAreaIds.length; i++) {
        areas.add({
          'id':       myAreaIds[i],
          'name':     i < myAreaNames.length ? myAreaNames[i] : 'Area ${myAreaIds[i]}',
          'pincodes': pincodesById[myAreaIds[i]] ?? <String>[],
        });
      }

      // For incharge: find salesmen who share these areas
      final salesmenMap = <int, List<Map<String, dynamic>>>{};
      if (_isIncharge && myAreaIds.isNotEmpty) {
        final allAssigns = await ApiService.getAllAreaAssigns();
        final allStaff   = await ApiService.getEmployees(perPage: 500);
        if (!mounted) return;

        // Build staffId → employee info map (only salesmen)
        final staffById = <String, Map<String, dynamic>>{};
        for (final e in allStaff) {
          final role = (e['role'] ?? '').toString().toLowerCase();
          if (role != 'salesman') continue;
          final id = (e['mobile'] ?? e['deli_id'] ?? '').toString();
          staffById[id] = e;
        }

        for (final assign in allAssigns) {
          final empId  = (assign['employee_id'] ?? '').toString();
          final emp    = staffById[empId];
          if (emp == null) continue; // not a salesman

          final empAreaIds = assign['area_ids'];
          if (empAreaIds is! List) continue;

          for (final aId in empAreaIds) {
            final n = int.tryParse(aId.toString());
            if (n == null || !myAreaIds.contains(n)) continue;
            salesmenMap.putIfAbsent(n, () => []);
            // avoid duplicates
            if (!salesmenMap[n]!.any((s) => s['id'] == empId)) {
              salesmenMap[n]!.add({
                'id':     empId,
                'name':   (emp['name']   ?? '').toString(),
                'mobile': (emp['mobile'] ?? '').toString(),
              });
            }
          }
        }
      }

      setState(() {
        _myAreas  = areas;
        _salesmen = salesmenMap;
        _loading  = false;
      });
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = 'Failed to load areas'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text('My Assigned Areas'),
        backgroundColor: gold,
        foregroundColor: Colors.white,
        actions: [
          IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: _load),
        ],
      ),
      body: Column(
        children: [
          if (!_loading && _error.isEmpty && _myAreas.isNotEmpty) _searchBar(),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: gold))
                : _error.isNotEmpty
                    ? Center(child: Text(_error, style: const TextStyle(color: Colors.red)))
                    : _myAreas.isEmpty
                        ? _emptyState()
                        : _buildList(_filteredAreas),
          ),
        ],
      ),
    );
  }

  Widget _searchBar() => Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
        child: TextField(
          controller: _searchCtrl,
          onChanged: (v) => setState(() => _query = v),
          decoration: InputDecoration(
            hintText: 'Search area, pincode or salesman',
            prefixIcon: const Icon(Icons.search_rounded, size: 20),
            suffixIcon: _query.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close_rounded, size: 18),
                    onPressed: () => setState(() {
                      _searchCtrl.clear();
                      _query = '';
                    }),
                  ),
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      );

  Widget _buildList(List<Map<String, dynamic>> areas) {
    if (areas.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off_rounded, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text('No areas match "$_query"',
                style: TextStyle(fontSize: 15, color: Colors.grey.shade500)),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(14),
        itemCount: areas.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (ctx, i) => _AreaCard(
          area: areas[i],
          salesmen: _salesmen[areas[i]['id'] as int] ?? [],
          isIncharge: _isIncharge,
          expanded: _expanded.contains(areas[i]['id']),
          onToggle: () => setState(() {
            final id = areas[i]['id'] as int;
            if (_expanded.contains(id)) {
              _expanded.remove(id);
            } else {
              _expanded.add(id);
            }
          }),
          onTap: () => _showPincodes(context, areas[i]),
        ),
      ),
    );
  }

  void _showPincodes(BuildContext context, Map<String, dynamic> area) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PincodeSheet(areaId: area['id'] as int, areaName: area['name'] as String),
    );
  }

  Widget _emptyState() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.location_off_rounded, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text('No areas assigned yet',
                style: TextStyle(fontSize: 16, color: Colors.grey.shade500)),
            const SizedBox(height: 6),
            Text('Ask your admin to assign areas',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade400)),
          ],
        ),
      );
}

class _AreaCard extends StatelessWidget {
  final Map<String, dynamic>        area;
  final List<Map<String, dynamic>>  salesmen;
  final bool isIncharge;
  final bool expanded;
  final VoidCallback onToggle;
  final VoidCallback onTap;

  const _AreaCard({
    required this.area,
    required this.salesmen,
    required this.isIncharge,
    required this.expanded,
    required this.onToggle,
    required this.onTap,
  });

  static const gold      = Color(0xFFD7BE69);
  static const greenDark = Color(0xFF2E7D32);

  @override
  Widget build(BuildContext context) {
    final name = area['name'] as String? ?? '';

    return Card(
      color: Colors.white,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: 1.5,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Area header
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
            child: Row(
              children: [
                Container(
                  width: 42, height: 42,
                  decoration: BoxDecoration(
                    color: gold.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.location_on_rounded, color: gold, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Marketing Area',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey.shade500)),
                      const SizedBox(height: 2),
                      Text(name,
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
                if (isIncharge) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: salesmen.isEmpty
                          ? Colors.grey.shade100
                          : const Color(0xFFE8F5E9),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${salesmen.length} salesman${salesmen.length == 1 ? '' : 's'}',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: salesmen.isEmpty ? Colors.grey : greenDark,
                      ),
                    ),
                  ),
                  if (salesmen.isNotEmpty)
                    IconButton(
                      icon: Icon(expanded ? Icons.expand_less : Icons.expand_more,
                          color: greenDark),
                      onPressed: onToggle,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32),
                    ),
                ],
              ],
            ),
          ),

          // Salesmen list (expanded, incharge only)
          if (isIncharge && expanded && salesmen.isNotEmpty) ...[
            const Divider(height: 1, indent: 14, endIndent: 14),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Salesmen in this area',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                          color: Colors.grey.shade600)),
                  const SizedBox(height: 8),
                  ...salesmen.map((s) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 16,
                          backgroundColor: gold.withValues(alpha: 0.15),
                          child: Text(
                            (s['name'] as String? ?? '?').isNotEmpty
                                ? (s['name'] as String)[0].toUpperCase()
                                : '?',
                            style: const TextStyle(
                                fontSize: 12, fontWeight: FontWeight.bold, color: gold),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text((s['name'] ?? '').toString(),
                                  style: const TextStyle(
                                      fontSize: 13, fontWeight: FontWeight.w600)),
                              Text((s['mobile'] ?? '').toString(),
                                  style: TextStyle(
                                      fontSize: 11, color: Colors.grey.shade500)),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF8E1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text('Salesman',
                              style: TextStyle(fontSize: 9, color: gold,
                                  fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ),
                  )),
                ],
              ),
            ),
          ],
        ],
        ),
      ),
    );
  }
}

// ── Pincode bottom sheet (read-only) ─────────────────────────────────────────

class _PincodeSheet extends StatefulWidget {
  final int    areaId;
  final String areaName;
  const _PincodeSheet({required this.areaId, required this.areaName});

  @override
  State<_PincodeSheet> createState() => _PincodeSheetState();
}

class _PincodeSheetState extends State<_PincodeSheet> {
  static const gold = Color(0xFFD7BE69);

  bool           _loading = true;
  List<String>   _pincodes = [];
  // pincode → city name (null = still loading / unavailable)
  final Map<String, String?> _cities = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final data = await ApiService.getArea(widget.areaId);
    if (!mounted) return;
    final raw = data?['pincodes'];
    setState(() {
      _pincodes = raw is List ? raw.map((e) => e.toString()).toList() : [];
      _loading  = false;
    });
    _loadCities();
  }

  Future<void> _loadCities() async {
    for (final pin in _pincodes) {
      if (_cities.containsKey(pin)) continue;
      final info = await ApiService.lookupIndianPincode(pin);
      if (!mounted) return;
      final city = (info?['city'] ?? '').toString().trim();
      setState(() => _cities[pin] = city.isEmpty ? null : city);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.35,
      maxChildSize: 0.85,
      builder: (ctx, scroll) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // Handle
            Container(
              margin: const EdgeInsets.symmetric(vertical: 10),
              width: 36, height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: gold.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.location_on_rounded, color: gold, size: 18),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.areaName,
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                        Text(
                          _loading ? 'Loading…' : '${_pincodes.length} pincode${_pincodes.length == 1 ? '' : 's'}',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // Body
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: gold))
                  : _pincodes.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.pin_drop_outlined, size: 52, color: Colors.grey.shade300),
                              const SizedBox(height: 10),
                              Text('No pincodes for this area',
                                  style: TextStyle(fontSize: 14, color: Colors.grey.shade500)),
                            ],
                          ),
                        )
                      : ListView.separated(
                          controller: scroll,
                          padding: const EdgeInsets.all(14),
                          itemCount: _pincodes.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (_, i) => Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF9F9F9),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.grey.shade200),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(7),
                                  decoration: BoxDecoration(
                                    color: gold.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(Icons.pin_drop_rounded, color: gold, size: 16),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _pincodes[i],
                                        style: const TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w700,
                                            letterSpacing: 1),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        _cities.containsKey(_pincodes[i])
                                            ? (_cities[_pincodes[i]] ?? 'City not found')
                                            : 'Loading city…',
                                        style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w700,
                                            color: Colors.grey.shade900),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

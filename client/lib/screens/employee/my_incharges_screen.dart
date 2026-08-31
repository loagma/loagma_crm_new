import 'package:flutter/material.dart';

import '../../services/api_service.dart';
import '../../services/user_service.dart';
import '../admin/incharge_levels.dart';

/// Shows the logged-in incharge's full downward hierarchy:
///   Head Incharge  → Zonal Incharges → Area Incharges → Salesmen
///   Zonal Incharge → Area Incharges  → Salesmen  (+ Teleadmins → Telecallers)
///   Area Incharge  → Salesmen
///   Teleadmin      → Telecallers
///
/// Built by recursively walking the generic incharge-assign map
/// (parent mobile → child mobiles) starting from the current user.
class MyInchargesScreen extends StatefulWidget {
  const MyInchargesScreen({super.key});

  @override
  State<MyInchargesScreen> createState() => _MyInchargesScreenState();
}

class _MyInchargesScreenState extends State<MyInchargesScreen> {
  static const gold = Color(0xFFD7BE69);

  bool _loading = true;
  String _error = '';

  // Direct children of the logged-in user, each a fully-expanded subtree.
  List<_Node> _roots = [];

  final _searchCtrl = TextEditingController();
  String _query = '';

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

  // ── Search ────────────────────────────────────────────────────────────────
  // Matches a person on every field the screen shows: name, mobile, role
  // (raw + label), specialty badge, area names and pincodes.
  bool _nodeMatches(_Node n, String q) {
    final hay = <String>[
      n.name,
      n.mobile,
      n.role,
      _roleStyle(n.role).label,
      n.specialty.label ?? '',
      for (final a in n.areas) ...[a.name, ...a.pincodes],
    ].join(' ').toLowerCase();
    return q.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).every(hay.contains);
  }

  /// Every person in the whole tree that matches the query, each with the
  /// chain of managers above them (for the "under …" context line).
  List<_Match> _collectMatches(List<_Node> nodes, String q, List<_Node> chain) {
    final out = <_Match>[];
    for (final n in nodes) {
      if (_nodeMatches(n, q)) out.add(_Match(n, chain));
      out.addAll(_collectMatches(n.children, q, [...chain, n]));
    }
    return out;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });

    final mobile = (UserService.currentMobile ?? '').trim();
    if (mobile.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'Not logged in';
      });
      return;
    }

    try {
      final results = await Future.wait([
        ApiService.getAllInchargeAssigns(),
        ApiService.getEmployees(perPage: 500),
        ApiService.getAllAreaAssigns(),
      ]);
      final areasResp = await ApiService.getAreas(perPage: 1000);

      if (!mounted) return;

      final allAssigns = results[0];
      final allStaff = results[1];
      final allAreaAssigns = results[2];
      final allAreas = (areasResp['data'] as List?) ?? const [];

      // parent mobile → list of child mobile-id strings
      final childIdsOf = <String, List<String>>{};
      for (final a in allAssigns) {
        final parentId = (a['head_incharge_id'] ?? '').toString();
        final ids = a['incharge_ids'];
        if (parentId.isEmpty || parentId == '0' || ids is! List) continue;
        childIdsOf[parentId] = ids
            .map((e) => e.toString())
            .where((s) => s.isNotEmpty && s != '0')
            .toList();
      }

      // employee lookup keyed by mobile and deli_id
      final empByKey = <String, Map<String, dynamic>>{};
      for (final e in allStaff) {
        final mob = (e['mobile'] ?? '').toString().trim();
        final deli = (e['deli_id'] ?? '').toString().trim();
        if (mob.isNotEmpty) empByKey[mob] = e;
        if (deli.isNotEmpty) empByKey[deli] = e;
      }

      // area id → pincodes
      final pincodesByAreaId = <String, List<String>>{};
      for (final ar in allAreas) {
        if (ar is! Map) continue;
        final id = (ar['id'] ?? '').toString();
        final pins = (ar['pincodes'] as List?)?.map((p) => p.toString()).toList() ?? const [];
        if (id.isNotEmpty) pincodesByAreaId[id] = pins;
      }

      // employee key → assigned areas (name + its pincodes)
      final areaInfoOf = <String, List<_AreaInfo>>{};
      for (final a in allAreaAssigns) {
        final empKey = (a['employee_id'] ?? '').toString().trim();
        if (empKey.isEmpty) continue;
        final ids = (a['area_ids'] as List?) ?? const [];
        final names = (a['area_names'] as List?) ?? const [];
        final infos = <_AreaInfo>[];
        for (var i = 0; i < names.length; i++) {
          final id = i < ids.length ? ids[i].toString() : '';
          infos.add(_AreaInfo(
            name: names[i].toString(),
            pincodes: pincodesByAreaId[id] ?? const [],
          ));
        }
        areaInfoOf[empKey] = infos;
      }

      List<_AreaInfo> areasFor(Map<String, dynamic>? emp, String key) {
        final mob = (emp?['mobile'] ?? '').toString().trim();
        final deli = (emp?['deli_id'] ?? '').toString().trim();
        return areaInfoOf[mob] ?? areaInfoOf[deli] ?? areaInfoOf[key] ?? const [];
      }

      // Recursively build a subtree for one person, guarding against cycles.
      _Node buildNode(String key, Set<String> visited) {
        final emp = empByKey[key];
        final role = normalizeRole(emp?['role']);
        final children = <_Node>[];
        for (final childId in childIdsOf[key] ?? const <String>[]) {
          if (visited.contains(childId)) continue;
          visited.add(childId);
          children.add(buildNode(childId, visited));
        }

        return _Node(
          name: (emp?['name'] ?? 'Unknown ($key)').toString(),
          mobile: (emp?['mobile'] ?? key).toString(),
          role: role,
          areas: areasFor(emp, key),
          children: children,
          specialty: role == 'zonal_incharge'
              ? zonalSpecialtyFromRoles(children.map((c) => c.role))
              : ZonalSpecialty.none,
        );
      }

      final visited = <String>{mobile};
      final roots = <_Node>[];
      for (final childId in childIdsOf[mobile] ?? const <String>[]) {
        if (visited.contains(childId)) continue;
        visited.add(childId);
        roots.add(buildNode(childId, visited));
      }

      setState(() {
        _roots = roots;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Failed to load: $e';
        });
      }
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
              : _roots.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.supervisor_account_outlined, size: 64, color: Colors.grey.shade300),
                          const SizedBox(height: 12),
                          Text('No team assigned to you',
                              style: TextStyle(fontSize: 16, color: Colors.grey.shade500)),
                          const SizedBox(height: 6),
                          Text('Ask your admin to assign your team',
                              style: TextStyle(fontSize: 13, color: Colors.grey.shade400)),
                        ],
                      ),
                    )
                  : _buildTeam(),
    );
  }

  Widget _buildTeam() {
    final q = _query.toLowerCase().trim();

    return Column(
      children: [
        _buildSearchBar(),
        Expanded(
          child: q.isEmpty
              ? RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                    itemCount: _roots.length,
                    itemBuilder: (ctx, i) => _NodeTile(node: _roots[i], depth: 0),
                  ),
                )
              : _buildResults(q),
        ),
      ],
    );
  }

  // Flat list of everyone matching the query, wherever they sit in the tree.
  Widget _buildResults(String q) {
    final matches = _collectMatches(_roots, q, const []);

    if (matches.isEmpty) {
      return ListView(
        children: [
          const SizedBox(height: 80),
          Center(child: Icon(Icons.search_off_rounded, size: 56, color: Colors.grey.shade300)),
          const SizedBox(height: 12),
          Center(
            child: Text('No match for "$_query"',
                style: TextStyle(fontSize: 14, color: Colors.grey.shade500)),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 2),
          child: Text('${matches.length} result${matches.length == 1 ? '' : 's'}',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500, fontWeight: FontWeight.w600)),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
            itemCount: matches.length,
            itemBuilder: (ctx, i) => _ResultCard(match: matches[i], query: q),
          ),
        ),
      ],
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: TextField(
        controller: _searchCtrl,
        onChanged: (v) => setState(() => _query = v),
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: 'Search name, mobile, role, area, pincode…',
          hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
          prefixIcon: const Icon(Icons.search_rounded, color: gold),
          suffixIcon: _query.isEmpty
              ? null
              : IconButton(
                  icon: Icon(Icons.clear_rounded, size: 18, color: Colors.grey.shade500),
                  onPressed: () {
                    _searchCtrl.clear();
                    setState(() => _query = '');
                    FocusScope.of(context).unfocus();
                  },
                ),
          filled: true,
          fillColor: Colors.white,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: Colors.grey.shade200)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: gold, width: 1.5)),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _AreaInfo {
  final String name;
  final List<String> pincodes;
  const _AreaInfo({required this.name, required this.pincodes});
}

class _Node {
  final String name;
  final String mobile;
  final String role;
  final List<_AreaInfo> areas;
  final List<_Node> children;
  final ZonalSpecialty specialty; // derived sales/tele/both badge (zonal only)

  const _Node({
    required this.name,
    required this.mobile,
    required this.role,
    required this.areas,
    required this.children,
    this.specialty = ZonalSpecialty.none,
  });

  /// Total people in this subtree (excluding self).
  int get descendantCount =>
      children.fold(0, (sum, c) => sum + 1 + c.descendantCount);
}

({Color color, Color light, String label}) _roleStyle(String role) {
  switch (role) {
    case 'head_incharge':
      return (color: const Color(0xFFAB47BC), light: const Color(0xFFF3E5F5), label: 'Head Incharge');
    case 'zonal_incharge':
      return (color: const Color(0xFF42A5F5), light: const Color(0xFFE3F2FD), label: 'Zonal Incharge');
    case 'area_incharge':
      return (color: const Color(0xFFFF7043), light: const Color(0xFFFBE9E7), label: 'Area Incharge');
    case 'salesman':
      return (color: const Color(0xFF43A047), light: const Color(0xFFE8F5E9), label: 'Salesman');
    case 'telecaller':
      return (color: const Color(0xFF00838F), light: const Color(0xFFE0F7FA), label: 'Telecaller');
    case 'teleadmin':
      return (color: const Color(0xFF5E35B1), light: const Color(0xFFEDE7F6), label: 'Teleadmin');
    default:
      return (
        color: const Color(0xFF7B68AA),
        light: const Color(0xFFEDE7F6),
        label: role.isEmpty ? 'Staff' : role[0].toUpperCase() + role.substring(1),
      );
  }
}

/// A person that matched the search, plus the managers above them.
class _Match {
  final _Node node;
  final List<_Node> chain; // top-most … immediate manager
  const _Match(this.node, this.chain);
}

/// Splits [text] on [query] terms and bolds the matched spans.
List<TextSpan> _highlight(String text, String query, TextStyle base) {
  final terms = query
      .split(RegExp(r'\s+'))
      .where((t) => t.isNotEmpty)
      .map((t) => RegExp.escape(t))
      .toList();
  if (terms.isEmpty) return [TextSpan(text: text, style: base)];

  final re = RegExp('(${terms.join('|')})', caseSensitive: false);
  final spans = <TextSpan>[];
  var i = 0;
  for (final m in re.allMatches(text)) {
    if (m.start > i) spans.add(TextSpan(text: text.substring(i, m.start), style: base));
    spans.add(TextSpan(
      text: text.substring(m.start, m.end),
      style: base.copyWith(
        fontWeight: FontWeight.w800,
        color: const Color(0xFF4A3A0C),
        backgroundColor: const Color(0x99C09E3E),
      ),
    ));
    i = m.end;
  }
  if (i < text.length) spans.add(TextSpan(text: text.substring(i), style: base));
  return spans;
}

/// One search hit: person card with a "under …" breadcrumb of their managers.
class _ResultCard extends StatelessWidget {
  final _Match match;
  final String query;

  const _ResultCard({required this.match, required this.query});

  String _initials(String name) {
    final parts = name.trim().split(' ').where((p) => p.isNotEmpty).toList();
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  @override
  Widget build(BuildContext context) {
    final n = match.node;
    final style = _roleStyle(n.role);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        elevation: 1,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 4,
                height: 40,
                margin: const EdgeInsets.only(right: 10, top: 1),
                decoration: BoxDecoration(color: style.color, borderRadius: BorderRadius.circular(4)),
              ),
              CircleAvatar(
                radius: 19,
                backgroundColor: style.light,
                child: Text(_initials(n.name),
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: style.color)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text.rich(
                            TextSpan(children: _highlight(n.name, query,
                                const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.black87))),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(color: style.light, borderRadius: BorderRadius.circular(20)),
                          child: Text(style.label,
                              style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: style.color)),
                        ),
                      ],
                    ),
                    if (n.mobile.isNotEmpty)
                      Text.rich(
                        TextSpan(children: _highlight(n.mobile, query,
                            TextStyle(fontSize: 11, color: Colors.grey.shade600))),
                      ),
                    if (match.chain.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        'under ${match.chain.map((c) => c.name).join(' › ')}',
                        style: TextStyle(fontSize: 10.5, color: Colors.grey.shade400),
                      ),
                    ],
                    if (n.areas.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      ...n.areas.map((a) => _AreaBlock(area: a, color: style.color)),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One node of the hierarchy. Expandable when it has children.
class _NodeTile extends StatefulWidget {
  final _Node node;
  final int depth;

  const _NodeTile({required this.node, required this.depth});

  @override
  State<_NodeTile> createState() => _NodeTileState();
}

class _NodeTileState extends State<_NodeTile> {
  bool _expanded = true;

  String _initials(String name) {
    final parts = name.trim().split(' ').where((p) => p.isNotEmpty).toList();
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  @override
  Widget build(BuildContext context) {
    final node = widget.node;
    final style = _roleStyle(node.role);
    final hasChildren = node.children.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(left: widget.depth * 16.0, bottom: 8),
          child: Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            elevation: 1,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: hasChildren ? () => setState(() => _expanded = !_expanded) : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 4,
                      height: 40,
                      margin: const EdgeInsets.only(right: 10, top: 1),
                      decoration: BoxDecoration(color: style.color, borderRadius: BorderRadius.circular(4)),
                    ),
                    CircleAvatar(
                      radius: 19,
                      backgroundColor: style.light,
                      child: Text(_initials(node.name),
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: style.color)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(node.name,
                                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(color: style.light, borderRadius: BorderRadius.circular(20)),
                                child: Text(style.label,
                                    style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: style.color)),
                              ),
                              if (node.specialty.label != null) ...[
                                const SizedBox(width: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: node.specialty.color.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(color: node.specialty.color.withValues(alpha: 0.5)),
                                  ),
                                  child: Text(node.specialty.label!,
                                      style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: node.specialty.color)),
                                ),
                              ],
                            ],
                          ),
                          if (node.mobile.isNotEmpty)
                            Text(node.mobile, style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                          if (node.areas.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            ...node.areas.map((a) => _AreaBlock(area: a, color: style.color)),
                          ],
                        ],
                      ),
                    ),
                    if (hasChildren) ...[
                      const SizedBox(width: 4),
                      Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(color: style.color, borderRadius: BorderRadius.circular(10)),
                            child: Text('${node.children.length}',
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)),
                          ),
                          Icon(_expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                              size: 20, color: Colors.grey.shade500),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
        if (hasChildren && _expanded)
          ...node.children.map((c) => _NodeTile(node: c, depth: widget.depth + 1)),
      ],
    );
  }
}

/// One assigned area shown with its pincodes nested underneath.
class _AreaBlock extends StatelessWidget {
  final _AreaInfo area;
  final Color color;

  const _AreaBlock({required this.area, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 5),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.location_on_rounded, size: 13, color: color),
              const SizedBox(width: 4),
              Expanded(
                child: Text(area.name,
                    style: TextStyle(fontSize: 11.5, color: color, fontWeight: FontWeight.w700)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1.5),
                decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(10)),
                child: Text('${area.pincodes.length} PIN',
                    style: const TextStyle(fontSize: 8.5, color: Colors.white, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          if (area.pincodes.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: area.pincodes
                  .map((p) => Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: color.withValues(alpha: 0.35)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.pin_drop_outlined, size: 10, color: color),
                            const SizedBox(width: 3),
                            Text(p,
                                style: TextStyle(
                                    fontSize: 10.5, color: color, fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ))
                  .toList(),
            ),
          ] else
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('No pincodes',
                  style: TextStyle(fontSize: 9.5, color: Colors.grey.shade400, fontStyle: FontStyle.italic)),
            ),
        ],
      ),
    );
  }
}

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
  static const gold       = Color(0xFFD7BE69);
  static const greenCheck = Color(0xFF2E7D32);
  static const greenLight  = Color(0xFFE8F5E9);

  final Set<int> _assignedIds = {};
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
      _loading = false;
    });
  }

  int _idOf(Map<String, dynamic> area) =>
      int.tryParse((area['id'] ?? '').toString()) ?? 0;

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);

    final selectedAreas = _areas.where((a) => _assignedIds.contains(_idOf(a))).toList();
    final areaIds   = selectedAreas.map(_idOf).toList();
    final areaNames = selectedAreas.map((a) => (a['area_name'] ?? '').toString()).toList();

    final res = await ApiService.saveAreaAssign(_employeeId, areaIds, areaNames);

    if (!mounted) return;
    setState(() => _saving = false);

    if (res == null || res.containsKey('errors')) {
      Fluttertoast.showToast(msg: 'Failed to save assignment', backgroundColor: Colors.red, textColor: Colors.white);
    } else {
      Fluttertoast.showToast(
        msg: areaIds.isEmpty ? 'Assignment cleared' : '${areaIds.length} area(s) saved',
        backgroundColor: greenCheck,
        textColor: Colors.white,
      );
    }
  }

  String get _initials {
    final name  = (widget.salesman['name'] as String? ?? '').trim();
    final parts = name.split(' ').where((p) => p.isNotEmpty).toList();
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
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
          if (_assignedIds.isNotEmpty && _areas.isNotEmpty) _buildAssignedChips(),
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
    final progress = total == 0 ? 0.0 : assigned / total;

    return Container(
      decoration: const BoxDecoration(
        color: gold,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        children: [
          Row(
            children: [
              // avatar
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.25),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white.withValues(alpha: 0.6), width: 2),
                ),
                child: Center(
                  child: Text(_initials, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                ),
              ),
              const SizedBox(width: 12),
              // name + mobile
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white)),
                    if (mobile.isNotEmpty)
                      Text(mobile, style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.85))),
                    if (role.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      _RoleBadge(role: role),
                    ],
                  ],
                ),
              ),
              // assigned count pill
              Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.4)),
                    ),
                    child: Column(
                      children: [
                        Text(
                          '$assigned',
                          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white, height: 1),
                        ),
                        Text('assigned', style: TextStyle(fontSize: 10, color: Colors.white.withValues(alpha: 0.85))),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          // progress bar
          if (!_loading && total > 0) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progress,
                      backgroundColor: Colors.white.withValues(alpha: 0.25),
                      valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                      minHeight: 6,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '$assigned / $total areas',
                  style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.9), fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ── assigned chips ─────────────────────────────────────────────────────────

  Widget _buildAssignedChips() {
    final assignedAreas = _areas.where((a) => _assignedIds.contains(_idOf(a))).toList();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: greenLight,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFA5D6A7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.check_circle_rounded, size: 14, color: greenCheck),
              const SizedBox(width: 6),
              const Text(
                'Currently Assigned',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: greenCheck),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: greenCheck, borderRadius: BorderRadius.circular(10)),
                child: Text('${assignedAreas.length}', style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: assignedAreas.map((a) {
              final id = _idOf(a);
              return GestureDetector(
                onTap: () => setState(() => _assignedIds.remove(id)),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFA5D6A7)),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 4, offset: const Offset(0, 1))],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.location_on_rounded, size: 12, color: greenCheck),
                      const SizedBox(width: 4),
                      Text((a['area_name'] ?? '').toString(),
                          style: const TextStyle(fontSize: 11, color: greenCheck, fontWeight: FontWeight.w600)),
                      const SizedBox(width: 5),
                      const Icon(Icons.close_rounded, size: 12, color: Color(0xFF81C784)),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 4),
          Text('Tap a chip to remove', style: TextStyle(fontSize: 10, color: Colors.green.shade400)),
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
          final topGap = prev is _SectionHeader ? 0.0 : 6.0;

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
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isAssign ? const Color(0xFFA5D6A7) : Colors.transparent,
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: isAssign
                          ? greenCheck.withValues(alpha: 0.08)
                          : Colors.black.withValues(alpha: 0.04),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                  child: Row(
                    children: [
                      // icon box
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: isAssign ? greenLight : Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isAssign ? const Color(0xFFA5D6A7) : Colors.grey.shade200,
                          ),
                        ),
                        child: Icon(
                          Icons.location_on_rounded,
                          color: isAssign ? greenCheck : Colors.grey.shade400,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      // text info
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(areaName, style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: isAssign ? const Color(0xFF1B5E20) : Colors.grey.shade900,
                            )),
                            if (subtitle.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(subtitle, style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                            ],
                            if (pinList.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text('Pin: $pinList', style: TextStyle(fontSize: 10, color: Colors.grey.shade400)),
                            ],
                          ],
                        ),
                      ),
                      // checkbox
                      Transform.scale(
                        scale: 1.1,
                        child: Checkbox(
                          value: isAssign,
                          activeColor: greenCheck,
                          checkColor: Colors.white,
                          side: BorderSide(color: isAssign ? greenCheck : Colors.grey.shade400, width: 1.5),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
                          onChanged: (v) => setState(() {
                            if (v == true) { _assignedIds.add(id); } else { _assignedIds.remove(id); }
                          }),
                        ),
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

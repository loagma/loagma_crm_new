import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';

import '../../services/api_service.dart';
import '../../services/user_service.dart';

/// "Incharge Profile" — available to every role from the drawer.
///
/// Shows two things:
///  1. **My details** — the logged-in user's own profile in full: every field
///     the employee record carries (ID, name, mobile, role, city / state /
///     pincode, account status, shift timing, last location update).
///  2. **My reporting incharge** — the immediate senior this user reports to,
///     followed by the rest of the chain up to Admin. Built from the same
///     incharge-assign map the drawer's "Your Seniors" card uses.
class InchargeProfileScreen extends StatefulWidget {
  const InchargeProfileScreen({super.key});

  @override
  State<InchargeProfileScreen> createState() => _InchargeProfileScreenState();
}

class _Person {
  final String name;
  final String mobile;
  final String role;
  final String city;
  const _Person({
    required this.name,
    required this.mobile,
    required this.role,
    this.city = '',
  });
}

class _InchargeProfileScreenState extends State<InchargeProfileScreen> {
  static const _gold = Color(0xFFC09E3E);
  static const _bg = Color(0xFFF7F7F7);

  bool _loading = true;
  String? _error;

  // Full employee row for the logged-in user (null until loaded).
  Map<String, dynamic>? _me;
  // Ordered: immediate incharge first → … → Admin last.
  List<_Person> _seniors = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final myMobile = (UserService.currentMobile ?? '').trim();
    final myRole = (UserService.currentRole ?? '').toLowerCase().trim();

    if (myMobile.isEmpty) {
      setState(() {
        _me = {
          'name': UserService.currentName ?? '—',
          'role': myRole,
        };
        _loading = false;
        _error = 'You are not signed in.';
      });
      return;
    }

    try {
      final results = await Future.wait([
        ApiService.getEmployee(myMobile),
        ApiService.getAllInchargeAssigns(),
        ApiService.getEmployees(perPage: 1000),
      ]);
      final full = results[0] as Map<String, dynamic>?;
      final assigns = results[1] as List<Map<String, dynamic>>;
      final staff = results[2] as List<Map<String, dynamic>>;

      // Fallback: pull my row out of the list if the by-id call was blocked.
      final me = full ??
          staff.firstWhere(
            (e) => (e['mobile'] ?? '').toString().trim() == myMobile,
            orElse: () => <String, dynamic>{
              'name': UserService.currentName ?? '—',
              'mobile': myMobile,
              'role': myRole,
            },
          );

      // employee lookup keyed by both mobile and deli_id
      final empByKey = <String, Map<String, dynamic>>{};
      for (final e in staff) {
        final mob = (e['mobile'] ?? '').toString().trim();
        final deli = (e['deli_id'] ?? '').toString().trim();
        if (mob.isNotEmpty) empByKey[mob] = e;
        if (deli.isNotEmpty) empByKey[deli] = e;
      }

      _Person toPerson(Map<String, dynamic>? e, String fallbackKey) => _Person(
            name: (e?['name'] ?? 'Unknown').toString(),
            mobile: (e?['mobile'] ?? fallbackKey).toString(),
            role: (e?['role'] ?? '').toString().toLowerCase().trim(),
            city: (e?['city'] ?? '').toString().trim(),
          );

      // child key → parent key
      final parentOf = <String, String>{};
      for (final a in assigns) {
        final parentId = (a['head_incharge_id'] ?? '').toString().trim();
        if (parentId.isEmpty || parentId == '0') continue;
        final ids = a['incharge_ids'];
        if (ids is! List) continue;
        for (final c in ids) {
          final cid = c.toString().trim();
          if (cid.isEmpty || cid == '0') continue;
          parentOf[cid] = parentId;
        }
      }

      String? parentKeyOf(String key, Map<String, dynamic>? emp) {
        final direct = parentOf[key];
        if (direct != null) return direct;
        final deli = (emp?['deli_id'] ?? '').toString().trim();
        if (deli.isNotEmpty) return parentOf[deli];
        return null;
      }

      final chain = <_Person>[];
      final visited = <String>{myMobile};
      var cur = parentKeyOf(myMobile, empByKey[myMobile]);
      while (cur != null && cur.isNotEmpty && !visited.contains(cur)) {
        visited.add(cur);
        final emp = empByKey[cur];
        chain.add(toPerson(emp, cur));
        cur = parentKeyOf(cur, emp);
      }

      // Admin sits above everyone but is never in the incharge-assign map.
      if (!chain.any((s) => s.role == 'admin') && myRole != 'admin') {
        final admin = staff.firstWhere(
          (e) => (e['role'] ?? '').toString().toLowerCase().trim() == 'admin',
          orElse: () => <String, dynamic>{},
        );
        if (admin.isNotEmpty) chain.add(toPerson(admin, ''));
      }

      if (!mounted) return;
      setState(() {
        _me = me;
        _seniors = chain;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _me ??= {
          'name': UserService.currentName ?? '—',
          'mobile': myMobile,
          'role': myRole,
        };
        _loading = false;
        _error = 'Could not load your incharge details. Pull to refresh.';
      });
    }
  }

  ({String label, Color color}) _roleStyle(String role) {
    switch (role) {
      case 'head_incharge':
        return (label: 'Head Incharge', color: const Color(0xFFAB47BC));
      case 'zonal_incharge':
        return (label: 'Zonal Incharge', color: const Color(0xFF42A5F5));
      case 'area_incharge':
        return (label: 'Area Incharge', color: const Color(0xFFFF7043));
      case 'teleadmin':
        return (label: 'Teleadmin', color: const Color(0xFF5E35B1));
      case 'telecaller':
        return (label: 'Telecaller', color: const Color(0xFF00838F));
      case 'salesman':
        return (label: 'Salesman', color: const Color(0xFF43A047));
      case 'admin':
        return (label: 'Admin', color: const Color(0xFF5C6BC0));
      case 'manager':
        return (label: 'Manager', color: const Color(0xFF26A69A));
      default:
        return (
          label: role.isEmpty
              ? 'Staff'
              : role[0].toUpperCase() + role.substring(1).replaceAll('_', ' '),
          color: const Color(0xFF7B68AA),
        );
    }
  }

  void _copy(String value, String what) {
    if (value.trim().isEmpty) return;
    Clipboard.setData(ClipboardData(text: value));
    Fluttertoast.showToast(msg: '$what copied');
  }

  String _s(dynamic v) => v == null ? '' : v.toString().trim();

  String _fmtDateTime(dynamic v) {
    final raw = _s(v);
    if (raw.isEmpty) return '';
    final d = DateTime.tryParse(raw)?.toLocal();
    if (d == null) return raw;
    const mo = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final ap = d.hour < 12 ? 'AM' : 'PM';
    return '${d.day.toString().padLeft(2, '0')} ${mo[d.month - 1]} ${d.year} · '
        '$h:${d.minute.toString().padLeft(2, '0')} $ap';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _gold,
        foregroundColor: Colors.white,
        title: const Text('Incharge Profile',
            style: TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _gold))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 14, 12, 28),
                children: [
                  _sectionTitle('My Personal Details', Icons.person_rounded),
                  const SizedBox(height: 8),
                  if (_me != null) _myCard(_me!),
                  const SizedBox(height: 20),
                  _sectionTitle(
                      'My Reporting Incharge', Icons.supervisor_account_rounded),
                  const SizedBox(height: 8),
                  if (_error != null) _noticeCard(_error!),
                  if (_error == null && _seniors.isEmpty)
                    _noticeCard('No incharge has been assigned to you yet.'),
                  ..._seniors.asMap().entries.map(
                        (e) => _seniorCard(e.value, isImmediate: e.key == 0),
                      ),
                ],
              ),
            ),
    );
  }

  Widget _sectionTitle(String t, IconData icon) => Row(
        children: [
          Icon(icon, size: 17, color: _gold),
          const SizedBox(width: 7),
          Text(t,
              style: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w800, color: Colors.black87)),
        ],
      );

  Widget _card({required Widget child}) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFEEEEEE)),
          boxShadow: const [
            BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2)),
          ],
        ),
        child: child,
      );

  Widget _myCard(Map<String, dynamic> m) {
    final role = _s(m['role']).toLowerCase();
    final style = _roleStyle(role);
    final name = _s(m['name']).isEmpty ? '—' : _s(m['name']);

    final locked = m['is_locked'] == true || m['is_locked'] == 1;
    final place = [_s(m['city']), _s(m['state'])]
        .where((s) => s.isNotEmpty)
        .join(', ');
    final geo = (_s(m['lat']).isNotEmpty && _s(m['lng']).isNotEmpty)
        ? '${m['lat']}, ${m['lng']}'
        : '';
    final shiftIn = _s(m['punch_in_time']);
    final shiftOut = _s(m['punch_out_time']);
    final shift = (shiftIn.isNotEmpty || shiftOut.isNotEmpty)
        ? '${shiftIn.isEmpty ? '—' : shiftIn}  to  ${shiftOut.isEmpty ? '—' : shiftOut}'
        : '';
    final grace = _s(m['grace_minutes']);
    final approval = m.containsKey('approval_required')
        ? ((m['approval_required'] == true || m['approval_required'] == 1)
            ? 'Required'
            : 'Not required')
        : '';
    final lastLoc = _fmtDateTime(m['location_last_updated']);

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: style.color.withValues(alpha: 0.15),
                child: Icon(Icons.person_rounded, color: style.color, size: 26),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: style.color.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(style.label.toUpperCase(),
                              style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w800,
                                  color: style.color)),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: (locked ? Colors.red : Colors.green)
                                .withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(locked ? 'LOCKED' : 'ACTIVE',
                              style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w800,
                                  color: locked ? Colors.red : Colors.green)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Divider(height: 1, color: Color(0xFFEEEEEE)),
          ),
          _pair(
            _cell(Icons.badge_rounded, 'Employee ID', _s(m['deli_id'])),
            _cell(Icons.phone_rounded, 'Mobile', _s(m['mobile']),
                onTap: () => _copy(_s(m['mobile']), 'Mobile')),
          ),
          _pair(
            _cell(Icons.work_rounded, 'Role', style.label),
            _cell(Icons.markunread_mailbox_rounded, 'Pincode', _s(m['pincode'])),
          ),
          _pair(
            _cell(Icons.location_city_rounded, 'City / State', place),
            _cell(Icons.my_location_rounded, 'Geo (lat, lng)', geo,
                onTap: geo.isEmpty ? null : () => _copy(geo, 'Location')),
          ),
          _pair(
            _cell(Icons.schedule_rounded, 'Shift', shift),
            _cell(Icons.timelapse_rounded, 'Grace minutes', grace),
          ),
          _pair(
            _cell(Icons.verified_user_rounded, 'Punch approval', approval),
            _cell(Icons.admin_panel_settings_rounded, 'Admin ID',
                _s(m['admin_id'])),
          ),
          _pair(
            _cell(Icons.update_rounded, 'Last location update', lastLoc),
            null,
          ),
        ],
      ),
    );
  }

  Widget _seniorCard(_Person p, {required bool isImmediate}) {
    final style = _roleStyle(p.role);
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 9,
                height: 9,
                decoration:
                    BoxDecoration(color: style.color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(style.label,
                    style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: style.color)),
              ),
              if (isImmediate)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: _gold.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text('Reports to',
                      style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: _gold)),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(p.name,
              style:
                  const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          if (p.mobile.isNotEmpty)
            _row(Icons.phone_rounded, 'Mobile', p.mobile,
                onTap: () => _copy(p.mobile, 'Mobile')),
          if (p.city.isNotEmpty)
            _row(Icons.location_city_rounded, 'City', p.city),
        ],
      ),
    );
  }

  /// One line holding two field cells (the second may be null → left cell keeps
  /// its half-width so columns stay aligned down the card).
  Widget _pair(Widget left, Widget? right) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: left),
            const SizedBox(width: 12),
            Expanded(child: right ?? const SizedBox.shrink()),
          ],
        ),
      );

  Widget _cell(IconData icon, String label, String value, {VoidCallback? onTap}) {
    final shown = value.trim().isEmpty ? '—' : value;
    return InkWell(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 13, color: Colors.grey.shade500),
              const SizedBox(width: 5),
              Expanded(
                child: Text(label,
                    style: TextStyle(
                        fontSize: 10.5,
                        color: Colors.grey.shade500,
                        fontWeight: FontWeight.w600)),
              ),
              if (onTap != null)
                Icon(Icons.copy_rounded, size: 12, color: Colors.grey.shade400),
            ],
          ),
          const SizedBox(height: 2),
          Padding(
            padding: const EdgeInsets.only(left: 18),
            child: Text(shown,
                style: const TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Widget _row(IconData icon, String label, String value, {VoidCallback? onTap}) {
    final shown = value.trim().isEmpty ? '—' : value;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 15, color: Colors.grey.shade500),
            const SizedBox(width: 8),
            SizedBox(
              width: 118,
              child: Text(label,
                  style: TextStyle(
                      fontSize: 11.5,
                      color: Colors.grey.shade500,
                      fontWeight: FontWeight.w600)),
            ),
            Expanded(
              child: Text(shown,
                  style: const TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w600)),
            ),
            if (onTap != null)
              Icon(Icons.copy_rounded, size: 13, color: Colors.grey.shade400),
          ],
        ),
      ),
    );
  }

  Widget _noticeCard(String t) => _card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Text(t,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12.5, color: Colors.black54)),
        ),
      );
}

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:fluttertoast/fluttertoast.dart';

import '../services/api_service.dart';

class AppDrawer extends StatelessWidget {
  final String role;
  final String userName;
  final Future<void> Function(BuildContext)? onLogout;

  const AppDrawer({
    Key? key,
    required this.role,
    this.userName = '',
    this.onLogout,
  }) : super(key: key);

  static const _accent1 = Color(0xFFD7BE69);
  static const _accent2 = Color(0xFFC09E3E);
  static const _bg      = Color(0xFFF7F7F7);

  // ── Role-based nav items ─────────────────────────────────────────────────

  List<Map<String, dynamic>> _menuForRole(String r) {
    switch (r.toLowerCase().trim()) {
      case 'admin':
        return [
          {'title': 'Dashboard',    'icon': Icons.dashboard_rounded,              'route': '/admin/dashboard'},
          {'title': 'Employee List','icon': Icons.people_alt_rounded,             'route': '/employee-list'},
          {'title': 'Lead Account', 'icon': Icons.account_balance_wallet_rounded, 'route': '/lead-accounts'},
          {'title': 'Marketing Area','icon': Icons.location_on_rounded,           'route': '/marketing-area', 'subtitle': 'Pincode allotment'},
          {'title': 'Area Assign',  'icon': Icons.location_history_rounded,       'route': '/area-assign',    'subtitle': 'Sales Team'},
          {'title': 'Attendance',   'icon': Icons.fact_check_outlined,            'route': '/attendance-manage'},
          {'title': 'Settings',     'icon': Icons.settings_rounded,               'route': '/admin/settings'},
        ];
      case 'manager':
        return [
          {'title': 'Team',    'icon': Icons.groups_rounded,   'route': '/manager/team'},
          {'title': 'Reports', 'icon': Icons.bar_chart_rounded, 'route': '/manager/reports'},
        ];
      case 'salesman':
      case 'telecaller':
        return [];
      case 'user':
        return [
          {'title': 'Profile',  'icon': Icons.person_rounded,   'route': '/profile'},
          {'title': 'Requests', 'icon': Icons.list_alt_rounded,  'route': '/requests'},
        ];
      default:
        return [];
    }
  }

  static List<Map<String, dynamic>> menuForRole(String r) {
    switch (r.toLowerCase().trim()) {
      case 'admin':
        return [
          {'title': 'Dashboard',    'icon': Icons.dashboard_rounded,              'route': '/admin/dashboard'},
          {'title': 'Employee List','icon': Icons.people_alt_rounded,             'route': '/employee-list'},
          {'title': 'Lead Account', 'icon': Icons.account_balance_wallet_rounded, 'route': '/lead-accounts'},
          {'title': 'Marketing Area','icon': Icons.location_on_rounded,           'route': '/marketing-area', 'subtitle': 'Pincode allotment'},
          {'title': 'Area Assign',  'icon': Icons.location_history_rounded,       'route': '/area-assign',    'subtitle': 'Sales Team'},
          {'title': 'Attendance',   'icon': Icons.fact_check_outlined,            'route': '/attendance-manage'},
          {'title': 'Settings',     'icon': Icons.settings_rounded,               'route': '/admin/settings'},
        ];
      case 'manager':
        return [
          {'title': 'Team',    'icon': Icons.groups_rounded,   'route': '/manager/team'},
          {'title': 'Reports', 'icon': Icons.bar_chart_rounded, 'route': '/manager/reports'},
        ];
      case 'salesman':
        return [
          {'title': 'Lead Accounts', 'icon': Icons.account_balance_wallet_rounded,  'route': '/lead-accounts'},
        ];
      case 'telecaller':
return [
  {
    'title': 'Home',
    'icon': Icons.home_rounded,
    'route': '/dashboard/telecaller'
  },
  {
    'title': 'Lead Accounts',
    'icon': Icons.people_alt_rounded,
    'route': '/lead-accounts'
  },
  {
    'title': 'Allotted Customer Accounts',
    'icon': Icons.assignment_ind_rounded,
    'route': '/allotted-customer-accounts'
  },
  {
    'title': 'Verify Lead Accounts',
    'icon': Icons.verified_user_rounded,
    'route': '/verify-lead-accounts'
  },
  {
    'title': 'Profile',
    'icon': Icons.person_rounded,
    'route': '/profile'
  },
];
      case 'user':
        return [
          {'title': 'Profile',  'icon': Icons.person_rounded,   'route': '/profile'},
          {'title': 'Requests', 'icon': Icons.list_alt_rounded,  'route': '/requests'},
        ];
      default:
        return [];
    }
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  bool get _showAttendance {
    final r = role.toLowerCase().trim();
    return r == 'salesman' || r == 'telecaller' || r == 'manager';
  }

  @override
  Widget build(BuildContext context) {
    final items = _menuForRole(role);

    return Drawer(
      backgroundColor: _bg,
      child: SafeArea(
        child: Column(
          children: [

            // ── Header ────────────────────────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [_accent1, _accent2],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(20),
                  bottomRight: Radius.circular(20),
                ),
              ),
              child: Column(
                children: [
                  // Logo row
                  Row(
                    children: [
                      Container(
                        height: 44,
                        width: 44,
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Image.asset('assets/logo.png', fit: BoxFit.contain),
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'LoagmaCRM',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // User card
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 20,
                          backgroundColor: Colors.white,
                          child: const Icon(Icons.person_rounded, color: _accent1, size: 22),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                userName.isNotEmpty ? userName : 'Guest User',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                role.toUpperCase(),
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w500,
                                  letterSpacing: 0.6,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // ── Attendance card (salesman / telecaller only) ───────────────
            if (_showAttendance)
              const _AttendanceDrawerCard(),

            // ── Navigation items ──────────────────────────────────────────
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                itemCount: items.length,
                itemBuilder: (ctx, i) {
                  final it = items[i];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Material(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      elevation: 0.5,
                      child: ListTile(
                        dense: true,
                        visualDensity: const VisualDensity(vertical: -1.5),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        leading: Container(
                          padding: const EdgeInsets.all(7),
                          decoration: BoxDecoration(
                            color: _accent1.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(it['icon'] as IconData, color: _accent2, size: 19),
                        ),
                        title: Text(
                          it['title'] as String,
                          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                        ),
                        subtitle: it['subtitle'] != null
                            ? Text(
                                it['subtitle'] as String,
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: Color(0xFFB89A3E),
                                  fontWeight: FontWeight.w500,
                                ),
                              )
                            : null,
                        trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 12, color: Colors.grey),
                        onTap: () {
                          Navigator.of(ctx).pop();
                          final route = it['route'] as String?;
                          if (route != null && route.isNotEmpty) context.go(route);
                        },
                      ),
                    ),
                  );
                },
              ),
            ),

            // ── Footer ────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Column(
                children: [
                  Material(
                    color: Colors.red.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    child: ListTile(
                      dense: true,
                      visualDensity: const VisualDensity(vertical: -1),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      leading: const Icon(Icons.logout_rounded, color: Colors.red, size: 20),
                      title: const Text(
                        'Logout',
                        style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                      onTap: () {
                        if (onLogout != null) {
                          onLogout!(context);
                        } else {
                          Navigator.of(context).pop();
                          context.go('/login');
                        }
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text('Version 1.0.0', style: TextStyle(fontSize: 11, color: Colors.grey)),
                ],
              ),
            ),

          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Attendance Drawer Card — self-contained stateful widget
// ─────────────────────────────────────────────────────────────────────────────

class _AttendanceDrawerCard extends StatefulWidget {
  const _AttendanceDrawerCard();

  @override
  State<_AttendanceDrawerCard> createState() => _AttendanceDrawerCardState();
}

class _AttendanceDrawerCardState extends State<_AttendanceDrawerCard> {
  // ── Local timer state ─────────────────────────────────────────────────────
  bool     _isPunchedIn   = false;
  bool     _isPunchedOut  = false;
  Duration _workDuration  = Duration.zero;
  Duration _breakDuration = Duration.zero;
  String?  _currentBreak; // 'tea' | 'lunch' | 'emergency'
  bool     _lunchTaken    = false;
  Timer?   _timer;

  // ── API / server state ────────────────────────────────────────────────────
  String   _attendanceStatus = 'on_time';
  TimeOfDay? _shiftPunchIn;
  TimeOfDay? _shiftPunchOut;
  int      _graceMinutes  = 15;
  bool     _initLoading   = true;
  bool     _actionLoading = false;

  static const _green = Color(0xFF43A047);
  static const _amber = Color(0xFFF59E0B);

  @override
  void initState() {
    super.initState();
    _loadTodayRecord();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  // ── Load today's attendance from API ──────────────────────────────────────

  Future<void> _loadTodayRecord() async {
    if (!mounted) return;
    setState(() => _initLoading = true);
    try {
      final res = await ApiService.attendanceToday();
      if (!mounted) return;

      final settings = res?['settings'] as Map<String, dynamic>?;
      if (settings != null) {
        _shiftPunchIn  = _parseTimeStr(settings['punch_in_time']  as String?);
        _shiftPunchOut = _parseTimeStr(settings['punch_out_time'] as String?);
        _graceMinutes  = (settings['grace_minutes'] as int?) ?? 15;
      }

      final record = res?['data'];
      if (record != null && record is Map) {
        _attendanceStatus = record['status'] as String? ?? 'on_time';

        final punchInStr  = record['punch_in_time']  as String?;
        final punchOutStr = record['punch_out_time'] as String?;

        if (punchInStr != null) {
          final punchInAt = DateTime.tryParse(punchInStr)?.toLocal();

          if (punchOutStr != null) {
            // Already punched out today
            _isPunchedOut  = true;
            _workDuration  = Duration(minutes: (record['total_work_minutes']  as int?) ?? 0);
            _breakDuration = Duration(minutes: (record['total_break_minutes'] as int?) ?? 0);
          } else if (punchInAt != null) {
            // Still punched in — restore timer
            _isPunchedIn = true;

            final breaks = (record['break_details'] as List?) ?? [];
            _lunchTaken = breaks.any((b) => (b as Map?)?['type'] == 'lunch');

            Map? openBreak;
            for (final b in breaks.reversed) {
              final bMap = b as Map?;
              if (bMap?['end'] == null) { openBreak = bMap; break; }
            }
            _currentBreak = openBreak?['type'] as String?;

            final now               = DateTime.now();
            final elapsed           = now.difference(punchInAt);
            final recordedBreakMins = (record['total_break_minutes'] as int?) ?? 0;
            var   totalBreak        = Duration(minutes: recordedBreakMins);

            if (openBreak != null && openBreak['start'] != null) {
              final breakStart = DateTime.tryParse(openBreak['start'] as String)?.toLocal();
              if (breakStart != null) totalBreak += now.difference(breakStart);
            }

            _breakDuration = totalBreak;
            _workDuration  = elapsed - totalBreak;
            if (_workDuration.isNegative) _workDuration = Duration.zero;

            _startTimer();
          }
        }
      }
    } catch (_) {
      // Silently fall through — card still shows, just not restored
    } finally {
      if (mounted) setState(() => _initLoading = false);
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        if (_currentBreak != null) {
          _breakDuration += const Duration(seconds: 1);
        } else {
          _workDuration += const Duration(seconds: 1);
        }
      });
    });
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  TimeOfDay? _parseTimeStr(String? raw) {
    if (raw == null) return null;
    try {
      final parts = raw.split(':');
      return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
    } catch (_) {
      return null;
    }
  }

  bool _isLateNow() {
    if (_shiftPunchIn == null) return false;
    final now      = TimeOfDay.now();
    final limit    = _shiftPunchIn!.hour * 60 + _shiftPunchIn!.minute + _graceMinutes;
    return now.hour * 60 + now.minute > limit;
  }

  bool _isEarlyNow() {
    if (_shiftPunchOut == null) return false;
    final now      = TimeOfDay.now();
    final expected = _shiftPunchOut!.hour * 60 + _shiftPunchOut!.minute;
    return now.hour * 60 + now.minute < expected;
  }

  Future<String?> _showReasonDialog(String message) async {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Reason Required',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message,
                style: const TextStyle(fontSize: 12.5, color: Colors.black54)),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              decoration: const InputDecoration(
                hintText: 'Enter your reason...',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              maxLines: 3,
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              if (ctrl.text.trim().isEmpty) {
                Fluttertoast.showToast(msg: 'Please enter a reason');
                return;
              }
              Navigator.pop(ctx, ctrl.text.trim());
            },
            child: const Text('Submit'),
          ),
        ],
      ),
    );
  }

  // ── Punch In / Out ────────────────────────────────────────────────────────

  Future<void> _togglePunch() async {
    if (_actionLoading) return;

    if (_isPunchedIn) {
      // ── Punch Out ─────────────────────────────────────────────────────────
      String? reason;
      if (_isEarlyNow()) {
        reason = await _showReasonDialog(
            'You are punching out early. Please provide a reason.');
        if (reason == null) return;
      }
      setState(() => _actionLoading = true);
      try {
        final res = await ApiService.attendancePunchOut(
          earlyReason:  reason,
          workMinutes:  _workDuration.inMinutes,
          breakMinutes: _breakDuration.inMinutes,
        );
        if (!mounted) return;
        if (res != null && res['success'] == true) {
          _timer?.cancel();
          _timer = null;
          final data = res['data'] as Map<String, dynamic>?;
          setState(() {
            _isPunchedIn      = false;
            _isPunchedOut     = true;
            _currentBreak     = null;
            _attendanceStatus = (data?['status'] as String?) ?? _attendanceStatus;
          });
          Fluttertoast.showToast(msg: 'Punched out successfully');
        } else {
          Fluttertoast.showToast(msg: 'Punch out failed. Please try again.');
        }
      } catch (e) {
        if (mounted) Fluttertoast.showToast(msg: 'Error: $e');
      } finally {
        if (mounted) setState(() => _actionLoading = false);
      }
    } else {
      // ── Punch In ──────────────────────────────────────────────────────────
      String? reason;
      if (_isLateNow()) {
        reason = await _showReasonDialog(
            'You are late. Please provide a reason for the late punch-in.');
        if (reason == null) return;
      }
      setState(() => _actionLoading = true);
      try {
        final res = await ApiService.attendancePunchIn(lateReason: reason);
        if (!mounted) return;
        if (res != null && res['success'] == true) {
          final data = res['data'] as Map<String, dynamic>?;
          setState(() {
            _attendanceStatus = (data?['status'] as String?) ?? 'on_time';
            _isPunchedIn      = true;
            _workDuration     = Duration.zero;
            _breakDuration    = Duration.zero;
          });
          _startTimer();
          Fluttertoast.showToast(msg: 'Punched in successfully');
        } else {
          final msg = (res?['message'] as String?) ?? 'Punch in failed. Please try again.';
          Fluttertoast.showToast(msg: msg);
        }
      } catch (e) {
        if (mounted) Fluttertoast.showToast(msg: 'Error: $e');
      } finally {
        if (mounted) setState(() => _actionLoading = false);
      }
    }
  }

  // ── Break ─────────────────────────────────────────────────────────────────

  Future<void> _onBreakTap(String type) async {
    if (!_isPunchedIn) {
      Fluttertoast.showToast(msg: 'Please punch in first');
      return;
    }
    if (type == 'lunch' && _lunchTaken && _currentBreak != 'lunch') {
      Fluttertoast.showToast(msg: 'Only one lunch break allowed per day');
      return;
    }
    final action = _currentBreak == type ? 'end' : 'start';
    setState(() {
      if (_currentBreak == type) {
        _currentBreak = null;
      } else {
        _currentBreak = type;
        if (type == 'lunch') _lunchTaken = true;
      }
    });
    // Optimistic — sync in background
    ApiService.attendanceBreak(type: type, action: action).catchError((_) => null);
  }

  String _fmt(Duration d) {
    final h = d.inHours.toString().padLeft(2, '0');
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_initLoading) {
      return Container(
        margin: const EdgeInsets.fromLTRB(10, 10, 10, 0),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 2))],
        ),
        child: const Center(
            child: SizedBox(
                width: 24, height: 24,
                child: CircularProgressIndicator(strokeWidth: 2))),
      );
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(10, 10, 10, 0),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          // Title
          const Text(
            "Today's Attendance",
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Colors.black87),
          ),

          // ── Pending approval banner ─────────────────────────────────────
          if (_attendanceStatus == 'pending') ...[
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 10),
              decoration: BoxDecoration(
                color: _amber.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _amber.withValues(alpha: 0.3)),
              ),
              child: const Text(
                '⏳ Awaiting admin approval',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 10.5, color: Color(0xFFF59E0B), fontWeight: FontWeight.w600),
              ),
            ),
          ],

          // ── Approved banner ─────────────────────────────────────────────
          if (_attendanceStatus == 'approved') ...[
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 10),
              decoration: BoxDecoration(
                color: _green.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                '✓ Approved by admin',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 10.5, color: Color(0xFF43A047), fontWeight: FontWeight.w600),
              ),
            ),
          ],

          // ── Punched out message ─────────────────────────────────────────
          if (_isPunchedOut) ...[
            const SizedBox(height: 6),
            const Text(
              'You have completed your shift for today.',
              style: TextStyle(fontSize: 10.5, color: Colors.grey),
            ),
          ],

          // ── Not yet punched in ──────────────────────────────────────────
          if (!_isPunchedIn && !_isPunchedOut) ...[
            const SizedBox(height: 4),
            const Text(
              'Tap Punch In to start your day.',
              style: TextStyle(fontSize: 10.5, color: Colors.grey),
            ),
          ],

          const SizedBox(height: 10),

          // ── Stats row ───────────────────────────────────────────────────
          Row(
            children: [
              _Stat(icon: Icons.login_rounded, label: 'Elapsed',
                    value: _isPunchedIn || _isPunchedOut
                        ? _fmt(_workDuration + _breakDuration) : '—',
                    color: _amber),
              _divider(),
              _Stat(icon: Icons.timer_outlined, label: 'Work',
                    value: _fmt(_workDuration), color: _amber),
              _divider(),
              _Stat(icon: Icons.local_cafe_outlined, label: 'Breaks',
                    value: _fmt(_breakDuration), color: _amber),
            ],
          ),

          // ── Break buttons (only while punched in) ───────────────────────
          if (_isPunchedIn) ...[
            const SizedBox(height: 10),
            const Divider(height: 1, color: Color(0xFFEEEEEE)),
            const SizedBox(height: 10),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _BreakBtn(icon: Icons.emoji_food_beverage_outlined, label: 'Tea',
                          active: _currentBreak == 'tea',
                          enabled: true,
                          onTap: () => _onBreakTap('tea')),
                _BreakBtn(icon: Icons.restaurant_outlined, label: 'Lunch',
                          active: _currentBreak == 'lunch',
                          enabled: !_lunchTaken || _currentBreak == 'lunch',
                          onTap: () => _onBreakTap('lunch')),
                _BreakBtn(icon: Icons.emergency_outlined, label: 'Emergency',
                          active: _currentBreak == 'emergency',
                          enabled: true,
                          onTap: () => _onBreakTap('emergency')),
              ],
            ),

            const SizedBox(height: 6),
            const Center(
              child: Text(
                'You can take one lunch break per day',
                style: TextStyle(fontSize: 9.5, color: Colors.grey, fontStyle: FontStyle.italic),
              ),
            ),

            // Active break banner
            if (_currentBreak != null) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 10),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'On ${_currentBreak![0].toUpperCase()}${_currentBreak!.substring(1)} break — tap to end',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 10.5, color: Colors.orange, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ],

          const SizedBox(height: 12),

          // ── Punch In / Out button ───────────────────────────────────────
          if (!_isPunchedOut)
            SizedBox(
              width: double.infinity,
              height: 42,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isPunchedIn ? Colors.red.shade600 : _green,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  elevation: 1,
                ),
                icon: _actionLoading
                    ? const SizedBox(
                        width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Icon(_isPunchedIn ? Icons.logout_rounded : Icons.login_rounded, size: 18),
                label: Text(
                  _isPunchedIn ? 'Punch Out' : 'Punch In',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                ),
                onPressed: _actionLoading ? null : _togglePunch,
              ),
            ),

        ],
      ),
    );
  }

  Widget _divider() => Container(height: 32, width: 1, color: const Color(0xFFEEEEEE));
}

// ── Compact stat cell ─────────────────────────────────────────────────────────

class _Stat extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _Stat({required this.icon, required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(height: 3),
          Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
          const SizedBox(height: 1),
          Text(value, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.black87)),
        ],
      ),
    );
  }
}

// ── Break button ──────────────────────────────────────────────────────────────

class _BreakBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final bool enabled;
  final VoidCallback onTap;

  const _BreakBtn({
    required this.icon,
    required this.label,
    required this.active,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = active ? Colors.orange : (enabled ? Colors.black54 : Colors.black26);
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: active
                  ? Colors.orange.withValues(alpha: 0.12)
                  : Colors.grey.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(height: 3),
          Text(label, style: TextStyle(fontSize: 9.5, color: color, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

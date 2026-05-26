import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:fluttertoast/fluttertoast.dart';

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
    return r == 'salesman' || r == 'telecaller';
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
  bool     _isPunchedIn  = false;
  Duration _workDuration = Duration.zero;
  Duration _breakDuration = Duration.zero;
  String?  _currentBreak; // 'tea' | 'lunch' | 'emergency'
  bool     _lunchTaken   = false;
  Timer?   _timer;

  static const _green  = Color(0xFF43A047);
  static const _amber  = Color(0xFFF59E0B);

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _togglePunch() {
    setState(() {
      if (_isPunchedIn) {
        _isPunchedIn = false;
        _currentBreak = null;
        _timer?.cancel();
        _timer = null;
      } else {
        _isPunchedIn = true;
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
    });
  }

  void _onBreakTap(String type) {
    if (!_isPunchedIn) {
      Fluttertoast.showToast(msg: 'Please punch in first');
      return;
    }
    if (type == 'lunch' && _lunchTaken && _currentBreak != 'lunch') {
      Fluttertoast.showToast(msg: 'Only one lunch break allowed per day');
      return;
    }
    setState(() {
      if (_currentBreak == type) {
        _currentBreak = null;
      } else {
        _currentBreak = type;
        if (type == 'lunch') _lunchTaken = true;
      }
    });
  }

  String _fmt(Duration d) {
    final h = d.inHours.toString().padLeft(2, '0');
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 10, 10, 0),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          // Title
          const Text(
            "Today's Attendance",
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Colors.black87),
          ),

          if (!_isPunchedIn) ...[
            const SizedBox(height: 4),
            const Text(
              'Tap Punch In to start your day.',
              style: TextStyle(fontSize: 10.5, color: Colors.grey),
            ),
          ],

          const SizedBox(height: 10),

          // Stats row
          Row(
            children: [
              _Stat(icon: Icons.login_rounded, label: 'Punch In',
                    value: _isPunchedIn ? _fmt(_workDuration + _breakDuration) : '—',
                    color: _amber),
              _divider(),
              _Stat(icon: Icons.timer_outlined, label: 'Work',
                    value: _fmt(_workDuration), color: _amber),
              _divider(),
              _Stat(icon: Icons.local_cafe_outlined, label: 'Breaks',
                    value: _fmt(_breakDuration), color: _amber),
            ],
          ),

          const SizedBox(height: 10),
          const Divider(height: 1, color: Color(0xFFEEEEEE)),
          const SizedBox(height: 10),

          // Break buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _BreakBtn(icon: Icons.emoji_food_beverage_outlined, label: 'Tea',
                        active: _currentBreak == 'tea',
                        enabled: _isPunchedIn,
                        onTap: () => _onBreakTap('tea')),
              _BreakBtn(icon: Icons.restaurant_outlined, label: 'Lunch',
                        active: _currentBreak == 'lunch',
                        enabled: _isPunchedIn && (!_lunchTaken || _currentBreak == 'lunch'),
                        onTap: () => _onBreakTap('lunch')),
              _BreakBtn(icon: Icons.emergency_outlined, label: 'Emergency',
                        active: _currentBreak == 'emergency',
                        enabled: _isPunchedIn,
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
                'On ${_currentBreak![0].toUpperCase()}${_currentBreak!.substring(1)} break — tap to resume',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 10.5, color: Colors.orange, fontWeight: FontWeight.w600),
              ),
            ),
          ],

          const SizedBox(height: 12),

          // Punch In / Out button
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
              icon: Icon(_isPunchedIn ? Icons.logout_rounded : Icons.login_rounded, size: 18),
              label: Text(
                _isPunchedIn ? 'Punch Out' : 'Punch In',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              ),
              onPressed: _togglePunch,
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

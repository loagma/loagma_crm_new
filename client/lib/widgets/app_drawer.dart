import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';

import '../services/api_service.dart';
import '../services/notification_service.dart';
import '../services/tracking_service.dart';

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
  static const _bg = Color(0xFFF7F7F7);

  static List<Map<String, dynamic>> menuForRole(String r) {
    switch (r.toLowerCase().trim()) {
      case 'admin':
        return [
          {
            'title': 'Dashboard',
            'icon': Icons.dashboard_rounded,
            'route': '/admin/dashboard',
            'color': const Color(0xFF5C6BC0),
          },
          {
            'title': 'Employee List',
            'icon': Icons.people_alt_rounded,
            'route': '/employee-list',
            'color': const Color(0xFF26A69A),
          },
          {
            'title': 'Lead Account',
            'icon': Icons.account_balance_wallet_rounded,
            'route': '/lead-accounts',
            'color': const Color(0xFF42A5F5),
          },
          {
            'title': 'Marketing Area',
            'icon': Icons.location_on_rounded,
            'route': '/marketing-area',
            'color': const Color(0xFFEF5350),
            'subtitle': 'Pincode allotment',
          },
          {
            'title': 'Area Assign',
            'icon': Icons.location_history_rounded,
            'route': '/area-assign',
            'color': const Color(0xFFFF7043),
            'subtitle': 'Salesman & Telecaller',
          },
          {
            'title': 'Assign',
            'icon': Icons.supervisor_account_rounded,
            'route': '/incharge-assign',
            'color': const Color(0xFFAB47BC),
            'subtitle': 'Head / Zonal / Area Incharge',
          },
          {
            'title': 'Attendance',
            'icon': Icons.fact_check_outlined,
            'route': '/attendance-manage',
            'color': const Color(0xFF66BB6A),
          },
          {
            'title': 'Live Salesmen',
            'icon': Icons.location_searching_rounded,
            'route': '/live-salesmen',
            'color': const Color(0xFF2F9E57),
            'subtitle': 'On-duty tracking',
          },
          {
            'title': 'Settings',
            'icon': Icons.settings_rounded,
            'route': '/admin/settings',
            'color': const Color(0xFF78909C),
          },
        ];
      case 'manager':
        return [
          {
            'title': 'Team',
            'icon': Icons.groups_rounded,
            'route': '/manager/team',
            'color': const Color(0xFF26A69A),
          },
          {
            'title': 'Reports',
            'icon': Icons.bar_chart_rounded,
            'route': '/manager/reports',
            'color': const Color(0xFF5C6BC0),
          },
          {
            'title': 'Live Salesmen',
            'icon': Icons.location_searching_rounded,
            'route': '/live-salesmen',
            'color': const Color(0xFF2F9E57),
            'subtitle': 'On-duty tracking',
          },
        ];

      case 'head_incharge':
        return [
          {
            'title': 'My Team',
            'icon': Icons.supervisor_account_rounded,
            'route': '/my-incharges',
            'color': const Color(0xFFAB47BC),
          },
          {
            'title': 'Live Salesmen',
            'icon': Icons.location_searching_rounded,
            'route': '/live-salesmen',
            'color': const Color(0xFF2F9E57),
            'subtitle': 'On-duty tracking',
          },
        ];
      case 'zonal_incharge':
        return [
          {
            'title': 'My Team',
            'icon': Icons.supervisor_account_rounded,
            'route': '/my-incharges',
            'color': const Color(0xFFAB47BC),
          },
          {
            'title': 'Live Salesmen',
            'icon': Icons.location_searching_rounded,
            'route': '/live-salesmen',
            'color': const Color(0xFF2F9E57),
            'subtitle': 'On-duty tracking',
          },
        ];
      case 'area_incharge':
        return [
          {
            'title': 'My Team',
            'icon': Icons.supervisor_account_rounded,
            'route': '/my-incharges',
            'color': const Color(0xFFAB47BC),
          },
          {
            'title': 'Live Salesmen',
            'icon': Icons.location_searching_rounded,
            'route': '/live-salesmen',
            'color': const Color(0xFF2F9E57),
            'subtitle': 'On-duty tracking',
          },
        ];
         case 'teleadmin':
        return [
          {
            'title': 'My Team',
            'icon': Icons.supervisor_account_rounded,
            'route': '/my-incharges',
            'color': const Color(0xFFAB47BC),
          },
          {
            'title': 'Live Salesmen',
            'icon': Icons.location_searching_rounded,
            'route': '/live-salesmen',
            'color': const Color(0xFF2F9E57),
            'subtitle': 'On-duty tracking',
          },
        ];
      case 'salesman':
        return [
          {
            'title': 'Create Lead Accounts',
            'icon': Icons.account_balance_wallet_rounded,
            'route': '/lead-accounts',
            'color': const Color(0xFF42A5F5),
          },
          {
            'title': 'My Areas',
            'icon': Icons.location_on_rounded,
            'route': '/my-areas',
            'color': const Color(0xFFEF5350),
            'subtitle': 'Assigned areas',
          },
          {
            'title': 'Alloted Customers',
            'icon': Icons.people_alt_rounded,
            'route': '/allotted-customer-accounts',
            'color': const Color(0xFF26A69A),
            'subtitle': 'Lead & Customers',
          },
          {
            'title': 'Todays Beat Plan',
            'icon': Icons.today_rounded,
            'route': '/todays-beat-plan',
            'color': const Color(0xFF66BB6A),
          },
          {
            'title': 'All Beat Plan',
            'icon': Icons.calendar_month_rounded,
            'route': '/all-beat-plan',
            'color': const Color(0xFF5C6BC0),
          },
          // {'title': 'Apply  Leave',      'icon': Icons.beach_access_rounded,          'route': '/apply-leave',              'color': const Color(0xFFFF7043)},
        ];
      case 'telecaller':
        return [
          {
            'title': 'Home',
            'icon': Icons.home_rounded,
            'route': '/dashboard/telecaller',
            'color': const Color(0xFF5C6BC0),
          },
          {
            'title': 'Live Dashboard',
            'icon': Icons.dashboard_rounded,
            'route': '/telecaller/dashboard',
            'color': const Color(0xFFD7BE69),
            'subtitle': 'Live numbers & charts',
          },
          {
            'title': 'Create Lead Accounts',
            'icon': Icons.people_alt_rounded,
            'route': '/lead-account',
            'color': const Color(0xFF42A5F5),
          },
          {
            'title': 'My Area',
            'icon': Icons.location_on_rounded,
            'route': '/my-areas',
            'color': const Color.fromARGB(255, 140, 33, 157),
            'subtitle': 'Assigned areas',
          },
          {
            'title': 'Allotted Customer Accounts',
            'icon': Icons.assignment_ind_rounded,
            'route': '/allotted-customer-accounts',
            'color': const Color(0xFF26A69A),
          },
          // {
          //   'title': 'Verify Lead Accounts',
          //   'icon': Icons.verified_user_rounded,
          //   'route': '/verify-lead-accounts',
          //   'color': const Color(0xFF66BB6A),
          // },
          // {
          //   'title': "Today's Callbacks",
          //   'icon': Icons.event_repeat_rounded,
          //   'route': '/telecaller/callbacks',
          //   'color': const Color(0xFFFB8C00),
          // },
          {
            'title': 'Call History',
            'icon': Icons.history_rounded,
            'route': '/telecaller/call-history',
            'color': const Color(0xFF1E88E5),
          },
          {
            'title': 'Today Worklist',
            'icon': Icons.checklist_rounded,
            'route': '/telecaller/worklist',
            'color': const Color(0xFF8E24AA),
          },
          {
            'title': 'Call Scripts',
            'icon': Icons.menu_book_rounded,
            'route': '/telecaller/call-scripts',
            'color': const Color(0xFF00897B),
          },
          {
            'title': 'Profile',
            'icon': Icons.person_rounded,
            'route': '/profile',
            'color': const Color(0xFF78909C),
          },
        ];
      case 'user':
        return [
          {
            'title': 'Profile',
            'icon': Icons.person_rounded,
            'route': '/profile',
            'color': const Color(0xFF78909C),
          },
          {
            'title': 'Requests',
            'icon': Icons.list_alt_rounded,
            'route': '/requests',
            'color': const Color(0xFF42A5F5),
          },
        ];
      default:
        return [];
    }
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  bool get _showAttendance {
    final r = role.toLowerCase().trim();
    return r == 'salesman' ||
        r == 'telecaller' ||
        r == 'manager' ||
        r == 'incharge' ||
        r == 'head_incharge' ||
        r == 'zonal_incharge' ||
        r == 'area_incharge';
  }

  @override
  Widget build(BuildContext context) {
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
                        child: Image.asset(
                          'assets/logo.png',
                          fit: BoxFit.contain,
                        ),
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 20,
                          backgroundColor: Colors.white,
                          child: const Icon(
                            Icons.person_rounded,
                            color: _accent1,
                            size: 22,
                          ),
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
            if (_showAttendance) const _AttendanceDrawerCard(),

            const Spacer(),

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
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      leading: const Icon(
                        Icons.logout_rounded,
                        color: Colors.red,
                        size: 20,
                      ),
                      title: const Text(
                        'Logout',
                        style: TextStyle(
                          color: Colors.red,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
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
                  const Text(
                    'Version 1.0.0',
                    style: TextStyle(fontSize: 11, color: Colors.grey),
                  ),
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
  bool _isPunchedIn = false;
  bool _isPunchedOut = false;
  Duration _workDuration = Duration.zero;
  Duration _breakDuration = Duration.zero;
  String? _currentBreak; // 'tea' | 'lunch' | 'emergency'
  bool _lunchTaken = false;
  Timer? _timer;

  // ── API / server state ────────────────────────────────────────────────────
  String _attendanceStatus = 'on_time';
  TimeOfDay? _shiftPunchIn;
  TimeOfDay? _shiftPunchOut;
  int _graceMinutes = 15;
  bool _approvalRequired = true;
  bool _initLoading = true;
  bool _actionLoading = false;
  // True when approved but employee hasn't yet confirmed with photo+location
  bool _needsConfirmIn = false;
  bool _needsConfirmOut = false;
  DateTime?
  _punchInAt; // punch-in anchor time (set to confirm-tap time after approval)
  Timer? _pollTimer; // polls for approval when status is pending

  // ── Computed state getters ─────────────────────────────────────────────────
  // Timer running: employee is actively working
  bool get _isWorking =>
      _isPunchedIn &&
      !_isPunchedOut &&
      (_attendanceStatus == 'on_time' ||
          _attendanceStatus == 'early_in' ||
          (_attendanceStatus == 'approved' && !_needsConfirmIn));

  // Late punch-in submitted, waiting for admin to approve
  bool get _isPunchInPending =>
      _isPunchedIn && !_isPunchedOut && _attendanceStatus == 'pending';

  // Early punch-out submitted, waiting for admin to approve
  bool get _isPunchOutPending =>
      _isPunchedOut && _attendanceStatus == 'pending';

  // Shift fully complete (punch-out confirmed)
  bool get _isShiftComplete =>
      _isPunchedOut &&
      (_attendanceStatus == 'on_time' ||
          _attendanceStatus == 'early_in' ||
          (_attendanceStatus == 'approved' && !_needsConfirmOut));

  // Record rejected by admin
  bool get _isRejected => _attendanceStatus == 'rejected';

  static const _green = Color(0xFF43A047);
  static const _amber = Color(0xFFF59E0B);

  @override
  void initState() {
    super.initState();
    _loadTodayRecord();
    // Poll every 30 s — keeps settings (approval_required, shift times) and
    // pending approval state in sync without restarting the app.
    _pollTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) _loadTodayRecord();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pollTimer?.cancel();
    super.dispose();
  }

  // ── Load today's attendance from API ──────────────────────────────────────

  Future<void> _loadTodayRecord() async {
    if (!mounted) return;
    final firstLoad = _initLoading;
    if (firstLoad) setState(() => _initLoading = true);
    try {
      final res = await ApiService.attendanceToday();
      if (!mounted) return;

      final settings = res?['settings'] as Map<String, dynamic>?;
      if (settings != null) {
        _shiftPunchIn = _parseTimeStr(settings['punch_in_time'] as String?);
        _shiftPunchOut = _parseTimeStr(settings['punch_out_time'] as String?);
        _graceMinutes = (settings['grace_minutes'] as int?) ?? 15;
        // Use == true to safely handle int 0/1 and null from older DB rows
        final ar = settings['approval_required'];
        _approvalRequired = (ar == null) ? true : (ar == true || ar == 1);
      }

      final record = res?['data'];
      if (record != null && record is Map) {
        final prevStatus = _attendanceStatus;
        _attendanceStatus = record['status'] as String? ?? 'on_time';

        // Notify once, the moment our own pending request gets a verdict.
        if (prevStatus == 'pending' &&
            (_attendanceStatus == 'approved' || _attendanceStatus == 'rejected')) {
          final approved = _attendanceStatus == 'approved';
          NotificationService.showNow(
            id: 9200,
            title: approved ? 'Attendance approved' : 'Attendance rejected',
            body: approved
                ? 'Your punch request was approved. Confirm with photo to continue.'
                : 'Your punch request was rejected.',
          );
        }

        final punchInStr = record['punch_in_time'] as String?;
        final punchOutStr = record['punch_out_time'] as String?;
        final isLate = record['is_late'] == true;
        final isEarlyOut = record['is_early_out'] == true;
        final isApproved = _attendanceStatus == 'approved';

        // Needs confirmation: approved late punch-in with no photo yet
        _needsConfirmIn =
            isApproved && isLate && record['punch_in_photo'] == null;
        _needsConfirmOut =
            isApproved && isEarlyOut && record['punch_out_photo'] == null;

        if (punchInStr != null) {
          _punchInAt = DateTime.tryParse(punchInStr)?.toLocal();
          _timer?.cancel(); // cancel any running timer before re-computing

          if (punchOutStr != null) {
            _isPunchedOut = true;
            _workDuration = Duration(
              minutes: (record['total_work_minutes'] as int?) ?? 0,
            );
            _breakDuration = Duration(
              minutes: (record['total_break_minutes'] as int?) ?? 0,
            );
          } else if (_punchInAt != null) {
            _isPunchedIn = true;

            final breaks = (record['break_details'] as List?) ?? [];
            _lunchTaken = breaks.any((b) => (b as Map?)?['type'] == 'lunch');

            Map? openBreak;
            for (final b in breaks.reversed) {
              final bMap = b as Map?;
              if (bMap?['end'] == null) {
                openBreak = bMap;
                break;
              }
            }
            _currentBreak = openBreak?['type'] as String?;

            // Only run timer if on_time / early_in / fully confirmed after approval
            final timerShouldRun =
                _attendanceStatus == 'on_time' ||
                _attendanceStatus == 'early_in' ||
                (_attendanceStatus == 'approved' && !_needsConfirmIn);

            if (timerShouldRun) {
              final now = DateTime.now();
              final elapsed = now.difference(_punchInAt!);

              // Build total break duration from break_details (not total_break_minutes
              // which is only written to the server at punch-out, so it's 0 mid-session)
              var totalBreak = Duration.zero;
              for (final b in breaks) {
                final bm = b as Map?;
                final startStr = bm?['start'] as String?;
                final endStr = bm?['end'] as String?;
                if (startStr == null) continue;
                final bStart = DateTime.tryParse(startStr)?.toLocal();
                if (bStart == null) continue;
                if (endStr != null) {
                  // closed break — add full duration
                  final bEnd = DateTime.tryParse(endStr)?.toLocal();
                  if (bEnd != null) totalBreak += bEnd.difference(bStart);
                } else {
                  // open break (same as openBreak) — add elapsed so far
                  totalBreak += now.difference(bStart);
                }
              }

              _breakDuration = totalBreak;
              _workDuration = elapsed - totalBreak;
              if (_workDuration.isNegative) _workDuration = Duration.zero;

              _startTimer();
            }
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
    final now = TimeOfDay.now();
    final limit =
        _shiftPunchIn!.hour * 60 + _shiftPunchIn!.minute + _graceMinutes;
    return now.hour * 60 + now.minute > limit;
  }

  bool _isEarlyNow() {
    if (_shiftPunchOut == null) return false;
    final now = TimeOfDay.now();
    final expected = _shiftPunchOut!.hour * 60 + _shiftPunchOut!.minute;
    return now.hour * 60 + now.minute < expected;
  }

  // True when punching in before scheduled shift start (no grace applied)
  bool _isEarlyInNow() {
    if (_shiftPunchIn == null) return false;
    final now = TimeOfDay.now();
    final shift = _shiftPunchIn!.hour * 60 + _shiftPunchIn!.minute;
    return now.hour * 60 + now.minute < shift;
  }

  Future<String?> _showReasonDialog(String message) async {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'Reason Required',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message,
              style: const TextStyle(fontSize: 12.5, color: Colors.black54),
            ),
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
            child: const Text('Cancel'),
          ),
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

  // ── Location capture (best-effort) ───────────────────────────────────────

  Future<Map<String, dynamic>?> _captureLocation() async {
    try {
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        await Geolocator.requestPermission();
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      ).timeout(const Duration(seconds: 10));
      return {'lat': pos.latitude, 'lng': pos.longitude};
    } catch (_) {
      return null;
    }
  }

  // ── Confirm punch after admin approval ───────────────────────────────────

  Future<void> _confirmPunch(String type) async {
    if (_actionLoading) return;
    setState(() => _actionLoading = true);
    try {
      // Photo
      String? photoUrl;
      try {
        final picked = await ImagePicker().pickImage(
          source: ImageSource.camera,
          imageQuality: 70,
          maxWidth: 1280,
        );
        if (picked != null && mounted) {
          Fluttertoast.showToast(msg: 'Uploading photo…');
          photoUrl = await ApiService.uploadAttendancePhoto(picked.path);
        }
      } catch (_) {}

      // Location
      final location = await _captureLocation();

      if (!mounted) return;

      final res = await ApiService.attendanceConfirmPunch(
        type: type,
        photo: photoUrl,
        location: location,
      );

      if (!mounted) return;
      if (res != null && res['success'] == true) {
        _pollTimer?.cancel(); // no longer need to poll once confirmed
        setState(() {
          if (type == 'in') {
            _needsConfirmIn = false;
            // Timer starts from the moment the employee taps Confirm
            _punchInAt = DateTime.now();
            _workDuration = Duration.zero;
            _breakDuration = Duration.zero;
            _startTimer();
            TrackingService.start();
          } else {
            _needsConfirmOut = false;
          }
        });
        Fluttertoast.showToast(
          msg: type == 'in'
              ? 'Punch-in confirmed! Timer started.'
              : 'Punch-out confirmed!',
        );
      } else {
        final msg =
            (res?['message'] as String?) ?? 'Confirmation failed. Try again.';
        Fluttertoast.showToast(msg: msg);
      }
    } catch (e) {
      if (mounted) Fluttertoast.showToast(msg: 'Error: $e');
    } finally {
      if (mounted) setState(() => _actionLoading = false);
    }
  }

  // ── Punch In / Out ────────────────────────────────────────────────────────

  Future<void> _togglePunch() async {
    if (_actionLoading) return;

    if (_isPunchedIn) {
      // ── Punch Out ─────────────────────────────────────────────────────────
      final isEarly = _isEarlyNow(); // physical reality
      final needsApproval =
          _approvalRequired && isEarly; // requires admin approval

      String? reason;
      if (isEarly) {
        // Always ask for reason when early — for records even if approval not required
        reason = await _showReasonDialog(
          'You are punching out early. Please provide a reason.',
        );
        if (reason == null) return;
      }

      // Capture photo + location when no approval needed (on-time OR free-punch early)
      String? photoUrl;
      Map<String, dynamic>? location;
      if (!needsApproval) {
        try {
          final picked = await ImagePicker().pickImage(
            source: ImageSource.camera,
            imageQuality: 70,
            maxWidth: 1280,
          );
          if (picked != null && mounted) {
            Fluttertoast.showToast(msg: 'Uploading photo…');
            photoUrl = await ApiService.uploadAttendancePhoto(picked.path);
          }
        } catch (_) {}
        location = await _captureLocation();
      }

      if (!mounted) return;
      setState(() => _actionLoading = true);
      try {
        final res = await ApiService.attendancePunchOut(
          earlyReason: reason,
          workMinutes: _workDuration.inMinutes,
          breakMinutes: _breakDuration.inMinutes,
          punchOutPhoto: photoUrl,
          punchOutLocation: location,
        );
        if (!mounted) return;
        if (res != null && res['success'] == true) {
          _timer?.cancel();
          _timer = null;
          TrackingService.stop();
          final data = res['data'] as Map<String, dynamic>?;
          setState(() {
            _isPunchedIn = false;
            _isPunchedOut = true;
            _currentBreak = null;
            _attendanceStatus =
                (data?['status'] as String?) ?? _attendanceStatus;
            _needsConfirmOut = needsApproval && _attendanceStatus == 'pending';
          });
          String msg;
          if (needsApproval) {
            msg = 'Punched out — awaiting admin approval';
          } else if (isEarly) {
            msg = 'Punched out (approval not required)';
          } else {
            msg = 'Punched out successfully';
          }
          Fluttertoast.showToast(msg: msg);
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
      final isLate = _isLateNow(); // physically late
      final isEarlyIn =
          !isLate && _isEarlyInNow(); // early (mutually exclusive with late)
      final needsApproval =
          _approvalRequired && isLate; // early-in never needs approval

      String? reason;
      if (isLate) {
        // Always ask reason when late (for records even if approval not required)
        reason = await _showReasonDialog(
          'You are late. Please provide a reason for the late punch-in.',
        );
        if (reason == null) return;
      } else if (isEarlyIn) {
        // Always ask reason when early
        reason = await _showReasonDialog(
          'You are punching in early. Please provide a reason.',
        );
        if (reason == null) return;
      }

      // Capture photo + location: on-time, early-in, and free-punch-late all get it immediately
      String? photoUrl;
      Map<String, dynamic>? location;
      if (!needsApproval) {
        try {
          final picked = await ImagePicker().pickImage(
            source: ImageSource.camera,
            imageQuality: 70,
            maxWidth: 1280,
          );
          if (picked != null && mounted) {
            Fluttertoast.showToast(msg: 'Uploading photo…');
            photoUrl = await ApiService.uploadAttendancePhoto(picked.path);
          }
        } catch (_) {}
        location = await _captureLocation();
      }

      if (!mounted) return;
      setState(() => _actionLoading = true);
      try {
        final res = await ApiService.attendancePunchIn(
          lateReason: isLate ? reason : null,
          earlyInReason: isEarlyIn ? reason : null,
          punchInPhoto: photoUrl,
          punchInLocation: location,
        );
        if (!mounted) return;
        if (res != null && res['success'] == true) {
          final data = res['data'] as Map<String, dynamic>?;
          final newStatus = (data?['status'] as String?) ?? 'on_time';
          _punchInAt = DateTime.now();
          setState(() {
            _attendanceStatus = newStatus;
            _isPunchedIn = true;
            _needsConfirmIn = false;
            _workDuration = Duration.zero;
            _breakDuration = Duration.zero;
          });
          // Start timer for on_time and early_in (both are immediate punch-ins)
          if (newStatus == 'on_time' || newStatus == 'early_in') {
            _startTimer();
            TrackingService.start();
          }
          final String msg;
          if (needsApproval) {
            msg = 'Punched in — awaiting admin approval';
          } else if (isLate) {
            msg = 'Punched in (approval not required)';
          } else if (isEarlyIn) {
            msg = 'Punched in early';
          } else {
            msg = 'Punched in successfully';
          }
          Fluttertoast.showToast(msg: msg);
        } else {
          final msg =
              (res?['message'] as String?) ??
              'Punch in failed. Please try again.';
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
    ApiService.attendanceBreak(
      type: type,
      action: action,
    ).catchError((_) => null);
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
          boxShadow: const [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 6,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: const Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

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
          // Title row with optional Free Punch badge + refresh button
          Row(
            children: [
              const Text(
                "Today's Attendance",
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: Colors.black87,
                ),
              ),
              if (!_approvalRequired) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: _green.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _green.withValues(alpha: 0.30)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.verified_rounded, size: 10, color: _green),
                      SizedBox(width: 3),
                      Text(
                        'Free Punch',
                        style: TextStyle(
                          fontSize: 9,
                          color: _green,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const Spacer(),
              GestureDetector(
                onTap: _initLoading ? null : _loadTodayRecord,
                child: _initLoading
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 1.5),
                      )
                    : const Icon(
                        Icons.refresh_rounded,
                        size: 16,
                        color: Colors.black45,
                      ),
              ),
            ],
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
                style: TextStyle(
                  fontSize: 10.5,
                  color: Color(0xFFF59E0B),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],

          // ── Approved banner + confirm buttons ────────────────────────────
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
                style: TextStyle(
                  fontSize: 10.5,
                  color: Color(0xFF43A047),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            // Confirm punch-in with photo + location
            if (_needsConfirmIn) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                height: 40,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _green,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: _actionLoading
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.camera_alt_rounded, size: 16),
                  label: const Text(
                    'Confirm Punch-In (Photo + Location)',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                  onPressed: _actionLoading ? null : () => _confirmPunch('in'),
                ),
              ),
            ],
            // Confirm punch-out with photo + location
            if (_needsConfirmOut) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                height: 40,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange.shade700,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: _actionLoading
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.camera_alt_rounded, size: 16),
                  label: const Text(
                    'Confirm Punch-Out (Photo + Location)',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                  onPressed: _actionLoading ? null : () => _confirmPunch('out'),
                ),
              ),
            ],
          ],

          // ── Punched out message (only when fully confirmed) ────────────
          if (_isShiftComplete) ...[
            const SizedBox(height: 6),
            const Text(
              'You have completed your shift for today.',
              style: TextStyle(fontSize: 10.5, color: Colors.grey),
            ),
          ],

          // ── Not yet punched in ──────────────────────────────────────────
          if (!_isPunchedIn && !_isPunchedOut && !_isRejected) ...[
            const SizedBox(height: 4),
            const Text(
              'Tap Punch In to start your day.',
              style: TextStyle(fontSize: 10.5, color: Colors.grey),
            ),
          ],

          const SizedBox(height: 10),

          // ── Stats row ───────────────────────────────────────────────────
          // Show real numbers only when timer is running or shift is done.
          // Pending/rejected/awaiting-confirm states show '—' to avoid 00:00:00.
          Builder(
            builder: (context) {
              final showStats =
                  _isWorking || _isShiftComplete || _isPunchOutPending;
              return Row(
                children: [
                  _Stat(
                    icon: Icons.login_rounded,
                    label: 'Elapsed',
                    value: showStats
                        ? _fmt(_workDuration + _breakDuration)
                        : '—',
                    color: _amber,
                  ),
                  _divider(),
                  _Stat(
                    icon: Icons.timer_outlined,
                    label: 'Work',
                    value: showStats ? _fmt(_workDuration) : '—',
                    color: _amber,
                  ),
                  _divider(),
                  _Stat(
                    icon: Icons.local_cafe_outlined,
                    label: 'Breaks',
                    value: showStats ? _fmt(_breakDuration) : '—',
                    color: _amber,
                  ),
                ],
              );
            },
          ),

          // ── Break buttons (only while actively working) ─────────────────
          if (_isWorking) ...[
            const SizedBox(height: 10),
            const Divider(height: 1, color: Color(0xFFEEEEEE)),
            const SizedBox(height: 10),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _BreakBtn(
                  icon: Icons.emoji_food_beverage_outlined,
                  label: 'Tea',
                  active: _currentBreak == 'tea',
                  enabled: true,
                  onTap: () => _onBreakTap('tea'),
                ),
                _BreakBtn(
                  icon: Icons.restaurant_outlined,
                  label: 'Lunch',
                  active: _currentBreak == 'lunch',
                  enabled: !_lunchTaken || _currentBreak == 'lunch',
                  onTap: () => _onBreakTap('lunch'),
                ),
                _BreakBtn(
                  icon: Icons.emergency_outlined,
                  label: 'Emergency',
                  active: _currentBreak == 'emergency',
                  enabled: true,
                  onTap: () => _onBreakTap('emergency'),
                ),
              ],
            ),

            const SizedBox(height: 6),
            const Center(
              child: Text(
                'You can take one lunch break per day',
                style: TextStyle(
                  fontSize: 9.5,
                  color: Colors.grey,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),

            // Active break banner
            if (_currentBreak != null) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  vertical: 5,
                  horizontal: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'On ${_currentBreak![0].toUpperCase()}${_currentBreak!.substring(1)} break — tap to end',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 10.5,
                    color: Colors.orange,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ],

          const SizedBox(height: 12),

          // ── Rejected: show card, no button ─────────────────────────────
          if (_isRejected)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.red.withValues(alpha: 0.30)),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.block_rounded, size: 16, color: Colors.red),
                  SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      'Attendance rejected — contact your admin',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.red,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            )
          // ── Pending punch-in or punch-out: lock card ────────────────────
          else if (_isPunchInPending || _isPunchOutPending)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
              decoration: BoxDecoration(
                color: _amber.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _amber.withValues(alpha: 0.35)),
              ),
              child: Column(
                children: [
                  const Icon(
                    Icons.lock_clock_outlined,
                    size: 22,
                    color: _amber,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _isPunchInPending
                        ? 'Punch-in pending approval'
                        : 'Punch-out pending approval',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: _amber,
                    ),
                  ),
                  const SizedBox(height: 3),
                  const Text(
                    'You will be notified once approved',
                    style: TextStyle(fontSize: 10, color: Colors.black45),
                  ),
                ],
              ),
            )
          // ── Normal Punch In / Punch Out button ──────────────────────────
          // Hidden when: rejected, pending, awaiting confirm, or shift done
          else if (!_isShiftComplete &&
              !(_attendanceStatus == 'approved' &&
                  (_needsConfirmIn || _needsConfirmOut)))
            SizedBox(
              width: double.infinity,
              height: 42,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isWorking ? Colors.red.shade600 : _green,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  elevation: 1,
                ),
                icon: _actionLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Icon(
                        _isWorking ? Icons.logout_rounded : Icons.login_rounded,
                        size: 18,
                      ),
                label: Text(
                  _isWorking ? 'Punch Out' : 'Punch In',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                onPressed: _actionLoading ? null : _togglePunch,
              ),
            ),
        ],
      ),
    );
  }

  Widget _divider() =>
      Container(height: 32, width: 1, color: const Color(0xFFEEEEEE));
}

// ── Compact stat cell ─────────────────────────────────────────────────────────

class _Stat extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _Stat({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(height: 3),
          Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
          const SizedBox(height: 1),
          Text(
            value,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Colors.black87,
            ),
          ),
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
    final color = active
        ? Colors.orange
        : (enabled ? Colors.black54 : Colors.black26);
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
          Text(
            label,
            style: TextStyle(
              fontSize: 9.5,
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

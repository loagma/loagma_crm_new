import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../services/api_service.dart';
import '../../services/notification_service.dart';
import '../../services/user_service.dart';
import '../../widgets/app_drawer.dart';

class EmployeeHomeScreen extends StatefulWidget {
  final String role;
  const EmployeeHomeScreen({super.key, required this.role});

  @override
  State<EmployeeHomeScreen> createState() => _EmployeeHomeScreenState();
}

class _EmployeeHomeScreenState extends State<EmployeeHomeScreen> {
  static const _accent1 = Color(0xFFD7BE69);
  static const _accent2 = Color(0xFFC09E3E);

  int _pendingCount = 0;
  int _assignedComplaintCount = 0;
  Timer? _pollTimer;

  // Any role above the leaf submitter roles (salesman/telecaller) can be an
  // approver somewhere in the hierarchy, so gate on exclusion rather than an
  // allow-list — this keeps working if new incharge-type roles are added.
  bool get _showBell {
    final r = widget.role.toLowerCase().trim();
    return r.isNotEmpty && r != 'salesman' && r != 'telecaller';
  }

  @override
  void initState() {
    super.initState();
    _loadCounts();
    // Poll while this screen is alive so approvers get a device notification
    // the moment a new request comes in below them, and ANY role (including
    // salesman/telecaller) gets notified the moment a complaint is assigned
    // to them — assignment can be delegated all the way down the hierarchy.
    _pollTimer = Timer.periodic(const Duration(seconds: 30), (_) => _loadCounts());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadCounts() async {
    if (_showBell) await _loadPendingCount();
    await _loadAssignedComplaintCount();
  }

  Future<void> _loadPendingCount() async {
    final count = await ApiService.adminPendingCount();
    if (!mounted) return;
    if (count > _pendingCount) {
      NotificationService.showNow(
        id: 9100,
        title: 'Attendance approval needed',
        body: count == 1
            ? 'You have 1 pending punch request to review.'
            : 'You have $count pending punch requests to review.',
      );
    }
    setState(() => _pendingCount = count);
  }

  Future<void> _loadAssignedComplaintCount() async {
    final count = await ApiService.complaintAssignedCount();
    if (!mounted) return;
    if (count > _assignedComplaintCount) {
      NotificationService.showNow(
        id: 9200,
        title: 'Complaint assigned to you',
        body: count == 1
            ? 'You have 1 complaint to handle.'
            : 'You have $count complaints to handle.',
      );
    }
    setState(() => _assignedComplaintCount = count);
  }

  Future<void> _logout(BuildContext context) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              Navigator.of(context).pop();
            },
            child: const Text('No', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              Navigator.of(context).pop();
              try { await ApiService.logout(); } catch (_) {}
              await UserService.logout();
            },
            child: const Text('Yes', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final name      = UserService.currentName ?? 'Employee';
    final roleLabel = widget.role[0].toUpperCase() + widget.role.substring(1).toLowerCase();
    final menuItems = AppDrawer.menuForRole(widget.role).where((m) {
      final t = (m['title'] as String).toLowerCase();
      return t != 'home' && t != 'dashboard' && t != 'profile' && t != 'settings';
    }).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      drawer: AppDrawer(role: widget.role, userName: name, onLogout: _logout),
      appBar: AppBar(
        backgroundColor: _accent1,
        elevation: 0,
        leading: Builder(
          builder: (ctx) => IconButton(
            icon: const Icon(Icons.menu_rounded, color: Colors.white),
            onPressed: () => Scaffold.of(ctx).openDrawer(),
          ),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$roleLabel Dashboard',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            Text(name, style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ],
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          if (_showBell)
            Stack(
              clipBehavior: Clip.none,
              children: [
                IconButton(
                  icon: const Icon(Icons.notifications_outlined, color: Colors.white),
                  tooltip: 'Pending Approvals',
                  onPressed: () async {
                    await context.push('/admin-notifications');
                    if (mounted) _loadPendingCount();
                  },
                ),
                if (_pendingCount > 0)
                  Positioned(
                    right: 6,
                    top: 6,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                      constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                      child: Text(
                        _pendingCount > 99 ? '99+' : '$_pendingCount',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w700),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
          Stack(
            clipBehavior: Clip.none,
            children: [
              IconButton(
                icon: const Icon(Icons.assignment_ind_outlined, color: Colors.white),
                tooltip: 'Complaints assigned to me',
                onPressed: () async {
                  await context.push('/complaints', extra: {'assignedToMe': true});
                  if (mounted) _loadAssignedComplaintCount();
                },
              ),
              if (_assignedComplaintCount > 0)
                Positioned(
                  right: 6,
                  top: 6,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                    constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                    child: Text(
                      _assignedComplaintCount > 99 ? '99+' : '$_assignedComplaintCount',
                      style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (menuItems.isNotEmpty)
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 1.1,
                ),
                itemCount: menuItems.length,
                itemBuilder: (context, index) {
                  final it = menuItems[index];
                  return GestureDetector(
                    onTap: () {
                      final route = it['route'] as String?;
                      if (route != null && route.isNotEmpty) context.push(route);
                    },
                    child: Builder(builder: (ctx) {
                      final ic = (it['color'] as Color?) ?? _accent2;
                      return Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFEEEEEE)),
                          boxShadow: const [
                            BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 3)),
                          ],
                        ),
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              height: 50,
                              width: 50,
                              decoration: BoxDecoration(
                                color: ic.withValues(alpha: 0.14),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(it['icon'] as IconData, size: 26, color: ic),
                            ),
                            const SizedBox(height: 8),
                            Flexible(
                              child: Text(
                                it['title'] as String,
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.black87,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

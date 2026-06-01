import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:fluttertoast/fluttertoast.dart';

import '../../services/api_service.dart';
import '../../services/user_service.dart';
import '../../widgets/app_drawer.dart';

class RoleDashboardTemplate extends StatefulWidget {
  final String role;

  const RoleDashboardTemplate({super.key, required this.role});

  @override
  State<RoleDashboardTemplate> createState() => _RoleDashboardTemplateState();
}

class _RoleDashboardTemplateState extends State<RoleDashboardTemplate> {
  int _pendingCount = 0;

  bool get _showBell {
    final r = widget.role.toLowerCase();
    return r == 'admin' || r == 'incharge' || r == 'head_incharge';
  }

  @override
  void initState() {
    super.initState();
    if (_showBell) _loadPendingCount();
  }

  Future<void> _loadPendingCount() async {
    final count = await ApiService.adminPendingCount();
    if (mounted) setState(() => _pendingCount = count);
  }

  Future<void> _logout(BuildContext context) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Logout'),
          content: const Text('Are you sure you want to logout?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('No', style: TextStyle(color: Colors.grey)),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(dialogContext);
                try {
                  await ApiService.logout();
                  await UserService.logout();
                  Fluttertoast.showToast(msg: 'Logged out successfully');
                  if (context.mounted) context.go('/login');
                } catch (e) {
                  await UserService.logout();
                  if (context.mounted) {
                    Fluttertoast.showToast(msg: 'Logged out');
                    context.go('/login');
                  }
                }
              },
              child: const Text('Yes',
                  style: TextStyle(color: Color.fromARGB(255, 225, 85, 30))),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDrawer(BuildContext context) {
    return AppDrawer(
        role: widget.role,
        userName: UserService.currentName ?? '',
        onLogout: _logout);
  }

  @override
  Widget build(BuildContext context) {
    final menuItems  = AppDrawer.menuForRole(widget.role);
    final featureItems = menuItems.where((m) {
      final t = (m['title'] as String).toLowerCase();
      return t != 'dashboard' && t != 'home' && t != 'settings';
    }).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      drawer: _buildDrawer(context),
      appBar: AppBar(
        backgroundColor: const Color(0xFFD7BE69),
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${widget.role[0].toUpperCase()}${widget.role.substring(1)} Dashboard',
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 2),
            Text(
              UserService.currentName ?? 'Staff',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        ),
        actions: [
          if (_showBell)
            Stack(
              clipBehavior: Clip.none,
              children: [
                IconButton(
                  icon: const Icon(Icons.notifications_outlined,
                      color: Colors.white),
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
                      constraints:
                          const BoxConstraints(minWidth: 16, minHeight: 16),
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
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: GridView.builder(
                padding: const EdgeInsets.only(top: 8, bottom: 8),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 14,
                  mainAxisSpacing: 14,
                  childAspectRatio: 1.05,
                ),
                itemCount: featureItems.length,
                itemBuilder: (context, index) {
                  final it = featureItems[index];
                  final ic = (it['color'] as Color?) ?? const Color(0xFFC09E3E);
                  return GestureDetector(
                    onTap: () {
                      final route = it['route'] as String?;
                      if (route != null && route.isNotEmpty) {
                        context.push(route);
                      }
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFEEEEEE)),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black12,
                            blurRadius: 10,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            height: 52,
                            width: 52,
                            decoration: BoxDecoration(
                              color: ic.withValues(alpha: 0.14),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              it['icon'] as IconData,
                              size: 28,
                              color: ic,
                            ),
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
                          if (it['subtitle'] != null) ...[
                            const SizedBox(height: 3),
                            Text(
                              it['subtitle'] as String,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w500,
                                color: Colors.black45,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

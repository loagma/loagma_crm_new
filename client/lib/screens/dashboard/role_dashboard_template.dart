import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:fluttertoast/fluttertoast.dart';

import '../../services/api_service.dart';
import '../../services/user_service.dart';
import '../../widgets/app_drawer.dart';

class RoleDashboardTemplate extends StatelessWidget {
  final String role;

  const RoleDashboardTemplate({super.key, required this.role});

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
                  if (context.mounted) {
                    context.go('/login');
                  }
                } catch (e) {
                  print('Logout error: $e');
                  // Always clear local data and navigate, even if API fails
                  await UserService.logout();
                  if (context.mounted) {
                    Fluttertoast.showToast(msg: 'Logged out');
                    context.go('/login');
                  }
                }
              },
              child: const Text('Yes', style: TextStyle(color: Color.fromARGB(255, 225, 85, 30))),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDrawer(BuildContext context) {
    // Use the centralized AppDrawer so menu changes based on `role`.
    return AppDrawer(role: role, userName: UserService.currentName ?? '', onLogout: _logout);
  }

  @override
  Widget build(BuildContext context) {
    final menuItems = AppDrawer.menuForRole(role);
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
              '${role[0].toUpperCase()}${role.substring(1)} Dashboard',
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
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 6),
            Expanded(
              flex: 1,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Welcome',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      UserService.currentName ?? 'Staff',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${role[0].toUpperCase()}${role.substring(1)} Dashboard',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Feature icons grid (built from drawer nav links)
            Expanded(
              flex: 3,
              child: GridView.builder(
                padding: const EdgeInsets.only(top: 8, bottom: 8),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 14,
                  mainAxisSpacing: 14,
                  childAspectRatio: 1.15,
                ),
                itemCount: featureItems.length,
                itemBuilder: (context, index) {
                  final it = featureItems[index];
                  return GestureDetector(
                    onTap: () {
                      final route = it['route'] as String?;
                      if (route != null && route.isNotEmpty) {
                        Navigator.of(context).pushNamed(route);
                      }
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Colors.white, Color(0xFFFFFCF4)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFF1E3B2)),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black12,
                            blurRadius: 10,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            height: 68,
                            width: 68,
                            decoration: BoxDecoration(
                              color: const Color(0xFFD7BE69).withValues(alpha: 0.14),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              it['icon'] as IconData,
                              size: 40,
                              color: const Color(0xFFC09E3E),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            it['title'] as String,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.black87,
                            ),
                          ),
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

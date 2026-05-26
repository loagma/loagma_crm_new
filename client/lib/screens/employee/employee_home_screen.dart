import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../services/api_service.dart';
import '../../services/user_service.dart';
import '../../widgets/app_drawer.dart';

class EmployeeHomeScreen extends StatelessWidget {
  final String role;
  const EmployeeHomeScreen({super.key, required this.role});

  static const _accent1 = Color(0xFFD7BE69);
  static const _accent2 = Color(0xFFC09E3E);

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
              Navigator.pop(dialogContext);  // close dialog
              Navigator.of(context).pop();  // close drawer
            },
            child: const Text('No', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogContext);  // close dialog
              Navigator.of(context).pop();  // close drawer
              try { await ApiService.logout(); } catch (_) {}
              await UserService.logout();    // GoRouter auto-navigates to /login
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
    final id        = UserService.currentId;
    final roleLabel = role[0].toUpperCase() + role.substring(1).toLowerCase();
    final menuItems = AppDrawer.menuForRole(role).where((m) {
      final t = (m['title'] as String).toLowerCase();
      return t != 'home' && t != 'dashboard' && t != 'profile' && t != 'settings';
    }).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      drawer: AppDrawer(role: role, userName: name, onLogout: _logout),
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
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

          

        

            // ── Feature grid ─────────────────────────────────────────
            if (menuItems.isNotEmpty) ...[
             
          
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
                              color: _accent1.withValues(alpha: 0.14),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(it['icon'] as IconData, size: 26, color: _accent2),
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
                    ),
                  );
                },
              ),
              const SizedBox(height: 20),
            ],

                 ],
        ),
      ),
    );
  }
}

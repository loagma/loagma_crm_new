import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

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

  List<Map<String, dynamic>> _menuForRole(String role) {
    final common = <Map<String, dynamic>>[];

    final admin = [
      {
        'title': 'Dashboard',
        'icon': Icons.dashboard_rounded,
        'route': '/admin/dashboard'
      },
      {
        'title': 'Employee List',
        'icon': Icons.people_alt_rounded,
        'route': '/employee-list'
      },
      {
        'title': 'Lead Account',
        'icon': Icons.account_balance_wallet_rounded,
        'route': '/lead-accounts'
      },
      {
        'title': 'Marketing Area (pincode allotment)',
        'icon': Icons.location_on_rounded,
        'route': '/marketing-area'
      },
      {
        'title': 'Area Assign',
        'icon': Icons.location_history_rounded,
        'route': '/area-assign'
      },
      {
        'title': 'Settings',
        'icon': Icons.settings_rounded,
        'route': '/admin/settings'
      },
    ];

    final manager = [
      {
        'title': 'Team',
        'icon': Icons.groups_rounded,
        'route': '/manager/team'
      },
      {
        'title': 'Reports',
        'icon': Icons.bar_chart_rounded,
        'route': '/manager/reports'
      },
    ];

    final user = [
      {
        'title': 'Profile',
        'icon': Icons.person_rounded,
        'route': '/profile'
      },
      {
        'title': 'Requests',
        'icon': Icons.list_alt_rounded,
        'route': '/requests'
      },
    ];

    switch (role.toLowerCase()) {
      case 'admin':
        return [...common, ...admin];
      case 'manager':
        return [...common, ...manager];
      case 'user':
        return [...common, ...user];
      default:
        return common;
    }
  }

  // Expose menu for other screens (e.g., dashboard feature tiles)
  static List<Map<String, dynamic>> menuForRole(String role) {
    final common = <Map<String, dynamic>>[];

    final admin = [
      {'title': 'Dashboard', 'icon': Icons.dashboard, 'route': '/admin/dashboard'},
      {'title': 'Employee List', 'icon': Icons.people_alt_rounded, 'route': '/employee-list'},
      {'title': 'Lead Account', 'icon': Icons.account_balance_wallet_rounded, 'route': '/lead-accounts'},
      {'title': 'Marketing Area (pincode allotment)', 'icon': Icons.location_on, 'route': '/marketing-area'},
      {'title': 'Area Assign', 'icon': Icons.location_history_rounded, 'route': '/area-assign'},
      // {'title': 'Users', 'icon': Icons.people, 'route': '/admin/users'},
      {'title': 'Settings', 'icon': Icons.settings, 'route': '/admin/settings'},
    ];

    final manager = [
      {'title': 'Team', 'icon': Icons.group, 'route': '/manager/team'},
      {'title': 'Reports', 'icon': Icons.bar_chart, 'route': '/manager/reports'},
    ];

    final user = [
      {'title': 'Profile', 'icon': Icons.person, 'route': '/profile'},
      {'title': 'Requests', 'icon': Icons.list_alt, 'route': '/requests'},
    ];

    switch (role.toLowerCase()) {
      case 'admin':
        return [...common, ...admin];
      case 'manager':
        return [...common, ...manager];
      case 'user':
        return [...common, ...user];
      default:
        return common;
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _menuForRole(role);

    const accent1 = Color(0xFFD7BE69);
    const accent2 = Color(0xFFC09E3E);
    const bgColor = Color(0xFFF7F7F7);

    return Drawer(
      backgroundColor: bgColor,
      child: SafeArea(
        child: Column(
          children: [

            /// =========================
            /// HEADER
            /// =========================
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [accent1, accent2],
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

                  /// LOGO + APP NAME
                  Row(
                    children: [
                      Container(
                        height: 46,
                        width: 46,
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

                  const SizedBox(height: 14),

                  /// USER CARD
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 22,
                          backgroundColor: Colors.white,
                          child: const Icon(
                            Icons.person_rounded,
                            color: accent1,
                            size: 24,
                          ),
                        ),

                        const SizedBox(width: 10),

                        Expanded(
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              Text(
                                userName.isNotEmpty
                                    ? userName
                                    : 'Guest User',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),

                              const SizedBox(height: 2),

                              Text(
                                role.toUpperCase(),
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 11,
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

            /// =========================
            /// NAVIGATION LINKS
            /// =========================
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 10,
                ),
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
                        visualDensity: const VisualDensity(
                          vertical: -1.5,
                        ),
                        contentPadding:
                            const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 2,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(12),
                        ),

                        leading: Container(
                          padding: const EdgeInsets.all(7),
                          decoration: BoxDecoration(
                          color:
                            accent1.withValues(alpha: 0.12),
                            borderRadius:
                                BorderRadius.circular(10),
                          ),
                          child: Icon(
                            it['icon'] as IconData,
                            color: accent2,
                            size: 19,
                          ),
                        ),

                        title: Text(
                          it['title'] as String,
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),

                        trailing: const Icon(
                          Icons.arrow_forward_ios_rounded,
                          size: 12,
                          color: Colors.grey,
                        ),

                        onTap: () {
                          Navigator.of(context).pop();

                          final route = it['route'] as String?;

                          if (route != null && route.isNotEmpty) {
                            context.go(route);
                          }
                        },
                      ),
                    ),
                  );
                },
              ),
            ),

            /// =========================
            /// FOOTER
            /// =========================
            Padding(
              padding:
                  const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Column(
                children: [

                  /// LOGOUT BUTTON
                  Material(
                    color: Colors.red.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    child: ListTile(
                      dense: true,
                      visualDensity:
                          const VisualDensity(vertical: -1),
                      contentPadding:
                          const EdgeInsets.symmetric(
                        horizontal: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(12),
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
                      onTap: () async {
                        Navigator.of(context).pop();

                        if (onLogout != null) {
                          await onLogout!(context);
                        } else {
                          context.go('/login');
                        }
                      },
                    ),
                  ),

                  const SizedBox(height: 8),

                  /// VERSION
                  const Text(
                    'Version 1.0.0',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey,
                    ),
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
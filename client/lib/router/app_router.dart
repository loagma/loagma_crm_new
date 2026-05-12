import 'package:go_router/go_router.dart';

import '../screens/auth/login_screen.dart';
import '../screens/auth/otp_screen.dart';
import '../screens/auth/no_role_screen.dart';
import '../screens/auth/splash_screen.dart';
import '../screens/dashboard/role_dashboard_template.dart';
import '../services/user_service.dart';
import 'auth_guard.dart';
import 'role_guard.dart';

final appRouter = GoRouter(
  initialLocation: '/splash',
  redirect: authGuard,
  refreshListenable: UserService(),
  routes: [
    GoRoute(
      path: '/splash',
      builder: (context, state) => const SplashScreen(),
    ),
    GoRoute(
      path: '/login',
      builder: (context, state) => const LoginScreen(),
    ),
    GoRoute(
      path: '/otp',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>?;
        final contactNumber = extra?['contactNumber'] as String? ?? '';
        return OtpScreen(contactNumber: contactNumber);
      },
    ),
    GoRoute(
      path: '/no-role',
      builder: (context, state) => const NoRoleScreen(),
    ),
    GoRoute(
      path: '/dashboard/:role',
      redirect: roleGuard,
      builder: (context, state) {
        final role = state.pathParameters['role'] ?? '';
        return RoleDashboardTemplate(role: role);
      },
    ),
  ],
);

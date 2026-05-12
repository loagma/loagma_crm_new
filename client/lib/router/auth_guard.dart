import 'package:go_router/go_router.dart';
import '../services/user_service.dart';

String? authGuard(context, GoRouterState state) {
  final isLogged = UserService.isLoggedIn;
  final path = state.uri.path; // safer than toString()

  // PUBLIC ROUTES (Unauthenticated Allowed)
  const publicRoutes = ['/splash', '/login', '/otp', '/no-role'];

  // Allow public routes
  if (publicRoutes.contains(path)) {
    return null;
  }

  // If NOT logged in => redirect to login
  if (!isLogged) {
    return '/login';
  }

  // Check if user has a role assigned
  final userRole = UserService.currentRole;
  if (userRole == null || userRole.isEmpty) {
    return '/no-role';
  }

  // Otherwise allow access
  return null;
}

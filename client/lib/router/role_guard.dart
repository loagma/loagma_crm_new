import 'package:go_router/go_router.dart';
import '../services/user_service.dart';

/// Normalize role for comparison: "tele admin" and "teleadmin" match.
String _normalizeRole(String? r) =>
    (r ?? '').toLowerCase().trim().replaceAll(' ', '');

String? roleGuard(context, GoRouterState state) {
  final urlRole = state.pathParameters['role']?.toLowerCase().trim();
  final savedRole = UserService.currentRole?.toLowerCase().trim();
  final isLogged = UserService.isLoggedIn;

  // Not logged in → authGuard handles it
  if (!isLogged) return null;

  // No saved role → force clear and login (corrupted session)
  if (savedRole == null || savedRole.isEmpty) {
    UserService.logout();
    return '/login';
  }

  // URL missing a role → correct it (should NEVER navigate without role)
  if (urlRole == null || urlRole.isEmpty) {
    return '/dashboard/$savedRole';
  }

  // URL trying to access a DIFFERENT role → fix it (compare normalized so "tele admin" == "teleadmin")
  if (_normalizeRole(urlRole) != _normalizeRole(savedRole)) {
    return '/dashboard/$savedRole';
  }

  // PERFECT → access granted
  return null;
}

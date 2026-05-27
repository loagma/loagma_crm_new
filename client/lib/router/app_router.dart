import 'package:go_router/go_router.dart';

import '../screens/auth/login_screen.dart';
import '../screens/auth/otp_screen.dart';
import '../screens/auth/no_role_screen.dart';
import '../screens/auth/splash_screen.dart';
import '../screens/dashboard/role_dashboard_template.dart';
import '../screens/employee/employee_home_screen.dart';
import '../screens/admin/employee_list_screen.dart';
import '../screens/admin/employee_detail_screen.dart';
import '../screens/admin/employee_create_screen.dart';
import '../screens/admin/area_assign_screen.dart';
import '../screens/admin/salesman_area_assign_screen.dart';
import '../screens/admin/attendance_manage_screen.dart';
import '../screens/admin/attendance_employee_screen.dart';
import '../screens/admin/attendance_settings_screen.dart';
import '../screens/admin/admin_notifications_screen.dart';
import '../screens/lead/lead_account_screen.dart';
import '../screens/lead/lead_account_list_screen.dart';
import '../screens/lead/lead_account_detail_screen.dart';
import '../screens/marketing/marketing_area_screen.dart';
import '../screens/marketing/area_pincode_screen.dart';
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
        final normalized = role.toLowerCase().trim();
        if (normalized == 'salesman' || normalized == 'telecaller' || normalized == 'manager') {
          return EmployeeHomeScreen(role: role);
        }
        return RoleDashboardTemplate(role: role);
      },
    ),
    // Lead account — create form (existing menu entry)
    GoRoute(
      path: '/lead-account',
      builder: (context, state) => const LeadAccountScreen(),
    ),
    // Lead accounts list
    GoRoute(
      path: '/lead-accounts',
      builder: (context, state) => const LeadAccountListScreen(),
    ),
    // Lead account detail
    GoRoute(
      path: '/lead-accounts/:id',
      builder: (context, state) {
        final id    = state.pathParameters['id'] ?? '';
        final extra = state.extra as Map<String, dynamic>?;
        return LeadAccountDetailScreen(id: id, initialData: extra);
      },
    ),
    // Lead account edit form
    GoRoute(
      path: '/lead-accounts/:id/edit',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>?;
        final id = state.pathParameters['id'];
        return LeadAccountScreen(initialData: extra, leadId: id);
      },
    ),
    GoRoute(
      path: '/marketing-area',
      builder: (context, state) => const MarketingAreaScreen(),
    ),
    GoRoute(
      path: '/marketing-area/:id',
      builder: (context, state) {
        final area = state.extra as Map<String, dynamic>? ?? {'id': int.tryParse(state.pathParameters['id'] ?? '') ?? 0, 'area_name': ''};
        return AreaPincodeScreen(area: area);
      },
    ),
    GoRoute(
      path: '/employee-list',
      builder: (context, state) => const EmployeeListScreen(),
    ),
    GoRoute(
      path: '/employee/create',
      builder: (context, state) => const EmployeeCreateScreen(),
    ),
    GoRoute(
      path: '/employee/edit/:id',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>?;
        return EmployeeCreateScreen(initialData: extra);
      },
    ),
    GoRoute(
      path: '/employee/:id',
      builder: (context, state) {
        final id = state.pathParameters['id'] ?? '';
        final extra = state.extra as Map<String, dynamic>?;
        return EmployeeDetailScreen(employee: extra, id: id);
      },
    ),
    GoRoute(
      path: '/attendance-manage',
      builder: (context, state) => const AttendanceManageScreen(),
    ),
    GoRoute(
      path: '/attendance-manage/:id',
      builder: (context, state) {
        final mobile = state.pathParameters['id'] ?? '';
        final extra  = state.extra as Map<String, dynamic>?;
        return AttendanceEmployeeScreen(employeeMobile: mobile, initialEmployee: extra);
      },
    ),
    GoRoute(
      path: '/attendance-manage/:id/settings',
      builder: (context, state) {
        final mobile = state.pathParameters['id'] ?? '';
        final extra  = state.extra as Map<String, dynamic>?;
        return AttendanceSettingsScreen(employeeMobile: mobile, initialEmployee: extra);
      },
    ),
    GoRoute(
      path: '/admin-notifications',
      builder: (context, state) => const AdminNotificationsScreen(),
    ),
    GoRoute(
      path: '/area-assign',
      builder: (context, state) => const AreaAssignScreen(),
    ),
    GoRoute(
      path: '/area-assign/:id',
      builder: (context, state) {
        final salesman = state.extra as Map<String, dynamic>? ??
            {'id': int.tryParse(state.pathParameters['id'] ?? '') ?? 0, 'name': '', 'mobile': ''};
        return SalesmanAreaAssignScreen(salesman: salesman);
      },
    ),
  ],
);

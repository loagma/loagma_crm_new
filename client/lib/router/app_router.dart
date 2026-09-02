import 'package:flutter/material.dart';
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
import '../screens/admin/live_salesmen_screen.dart';
import '../screens/admin/live_route_screen.dart';
import '../screens/admin/route_history_screen.dart';
import '../screens/admin/route_view_screen.dart';
import '../screens/admin/history_roster_screen.dart';
import '../screens/admin/admin_notifications_screen.dart';
import '../screens/admin/admin_target_screen.dart';
import '../screens/admin/admin_reports_screen.dart';
import '../screens/lead/pending_leads_screen.dart';
import '../screens/complaints/complaints_screen.dart';
import '../screens/admin/admin_incharge_assign_screen.dart';
import '../screens/admin/incharge_levels.dart';
import '../screens/admin/incharge_parent_list_screen.dart';
import '../screens/admin/incharge_child_assign_screen.dart';
import '../screens/employee/my_assigned_areas_screen.dart';
import '../screens/employee/my_team_screen.dart';
import '../screens/employee/my_incharges_screen.dart';
import '../screens/employee/incharge_profile_screen.dart';
import '../screens/employee/allotted_customer_accounts_screen.dart';
import '../screens/employee/todays_beat_plan_screen.dart';
import '../screens/employee/all_beat_plan_screen.dart';
import '../screens/employee/beat_plan_day_screen.dart';
import '../screens/shared/worklist_visit_screen.dart';
import '../screens/employee/assignment_view_screen.dart';
import '../screens/lead/lead_account_screen.dart';
import '../screens/lead/lead_account_list_screen.dart';
import '../screens/lead/lead_account_detail_screen.dart';
import '../screens/marketing/marketing_area_screen.dart';
import '../screens/marketing/area_pincode_screen.dart';
import '../screens/telecaller/verify_lead_accounts_screen.dart';
import '../screens/telecaller/verify_pincode_detail_screen.dart';
import '../screens/telecaller/telecaller_call_screen.dart';
import '../screens/telecaller/telecaller_dashboard_screen.dart';
import '../screens/telecaller/telecaller_callbacks_screen.dart';
import '../screens/telecaller/call_date_filter.dart';
import '../screens/telecaller/team_call_agents_screen.dart';
import '../screens/telecaller/telecaller_call_history_screen.dart';
import '../screens/telecaller/order_list_screen.dart';
import '../screens/telecaller/telecaller_worklist_screen.dart';
import '../screens/telecaller/telecaller_all_worklist_screen.dart';
import '../screens/telecaller/telecaller_worklist_day_screen.dart';
import '../screens/telecaller/telecaller_profile_screen.dart';
import '../screens/telecaller/telecaller_call_scripts_screen.dart';
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
        if (normalized == 'salesman'      || normalized == 'telecaller'     ||
            normalized == 'manager'       || normalized == 'incharge'       ||
            normalized == 'head_incharge' || normalized == 'zonal_incharge' ||
            normalized == 'area_incharge' || normalized == 'teleadmin') {
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
      path: '/live-salesmen',
      builder: (context, state) => const LiveSalesmenScreen(),
    ),
    GoRoute(
      path: '/live-route',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>? ?? {};
        return LiveRouteScreen(
          mobile: extra['mobile'] as String? ?? '',
          name: extra['name'] as String? ?? '',
        );
      },
    ),
    GoRoute(
      path: '/route-history',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>? ?? {};
        return RouteHistoryScreen(
          mobile: extra['mobile'] as String? ?? '',
          name: extra['name'] as String? ?? '',
        );
      },
    ),
    GoRoute(
      path: '/route-view',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>? ?? {};
        return RouteViewScreen(
          mobile: extra['mobile'] as String? ?? '',
          name: extra['name'] as String? ?? '',
          date: extra['date'] as String? ?? '',
        );
      },
    ),
    GoRoute(
      path: '/history-roster',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>? ?? {};
        return HistoryRosterScreen(
          date: extra['date'] as String? ?? '',
        );
      },
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
      path: '/admin/target',
      builder: (context, state) => const AdminTargetScreen(),
    ),
    GoRoute(
      path: '/admin/reports',
      builder: (context, state) => const AdminReportsScreen(),
    ),
    GoRoute(
      path: '/incharge-profile',
      builder: (context, state) => const InchargeProfileScreen(),
    ),
    GoRoute(
      path: '/pending-leads',
      builder: (context, state) => const PendingLeadsScreen(),
    ),
    GoRoute(
      path: '/complaints',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>?;
        return ComplaintsScreen(initialAssignedToMe: extra?['assignedToMe'] == true);
      },
    ),
    GoRoute(
      path: '/incharge-assign',
      builder: (context, state) => const AdminInchargeAssignScreen(),
    ),
    // List of parents for a level (head | zonal | area)
    GoRoute(
      path: '/incharge-assign/list/:level',
      builder: (context, state) {
        final level = InchargeLevel.byKey(state.pathParameters['level']) ?? InchargeLevel.head;
        return InchargeParentListScreen(level: level);
      },
    ),
    // Multi-select children to assign to one parent
    GoRoute(
      path: '/incharge-assign/assign/:level/:id',
      builder: (context, state) {
        final level = InchargeLevel.byKey(state.pathParameters['level']) ?? InchargeLevel.head;
        final parent = state.extra as Map<String, dynamic>? ??
            {'id': state.pathParameters['id'] ?? '', 'name': '', 'mobile': ''};
        return InchargeChildAssignScreen(level: level, parent: parent);
      },
    ),
    GoRoute(
      path: '/my-areas',
      builder: (context, state) => const MyAssignedAreasScreen(),
    ),
    GoRoute(
      path: '/my-team',
      builder: (context, state) => const MyTeamScreen(),
    ),
    GoRoute(
      path: '/my-incharges',
      builder: (context, state) => const MyInchargesScreen(),
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
    GoRoute(
      path: '/allotted-customer-accounts',
      builder: (context, state) => const AllottedCustomerAccountsScreen(),
    ),
    GoRoute(
      path: '/verify-lead-accounts',
      builder: (context, state) => const VerifyLeadAccountsScreen(),
    ),
    GoRoute(
      path: '/verify-lead-accounts/:pincode',
      builder: (context, state) {
        final pincode = state.pathParameters['pincode'] ?? '';
        final extra   = state.extra as Map<String, dynamic>? ?? {};
        return VerifyPincodeDetailScreen(pincode: pincode, initialData: extra);
      },
    ),
    GoRoute(
      path: '/telecaller/call',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>? ?? {};
        return TelecallerCallScreen(
          account:        extra['account']        as Map<String, dynamic>? ?? {},
          accountType:    extra['accountType']    as String?               ?? 'lead',
          returnOnFinish: extra['returnOnFinish'] == true,
        );
      },
    ),
    // Telecaller enhancement modules (UI with static data)
    GoRoute(
      path: '/telecaller/dashboard',
      builder: (context, state) => const TelecallerDashboardScreen(),
    ),
    GoRoute(
      path: '/telecaller/callbacks',
      builder: (context, state) => const TelecallerCallbacksScreen(),
    ),
    GoRoute(
      path: '/telecaller/call-history',
      builder: (context, state) => const TelecallerCallHistoryScreen(),
    ),
    // Team Call History opens on the telecaller roster; the two leaf routes are
    // the per-agent drill-in and the "everyone merged" view the module used to
    // land on directly.
    GoRoute(
      path: '/team-call-history',
      builder: (context, state) => const TeamCallAgentsScreen(),
    ),
    GoRoute(
      path: '/team-call-history/all',
      builder: (context, state) => const TelecallerCallHistoryScreen(teamMode: true),
    ),
    GoRoute(
      path: '/team-call-history/agent',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>? ?? {};
        return TelecallerCallHistoryScreen(
          teamMode: true,
          agentMobile: extra['mobile'] as String? ?? '',
          agentName: extra['name'] as String? ?? '',
          initialDateFilter: extra['dateFilter'] as CallDateFilter? ?? CallDateFilter.all,
          initialCustomRange: extra['customRange'] as DateTimeRange?,
        );
      },
    ),
    GoRoute(
      path: '/orders-list',
      builder: (context, state) => const OrderListScreen(),
    ),
    GoRoute(
      path: '/telecaller/worklist',
      builder: (context, state) => const TelecallerWorklistScreen(),
    ),
    GoRoute(
      path: '/telecaller/all-worklist',
      builder: (context, state) => const TelecallerAllWorklistScreen(),
    ),
    GoRoute(
      path: '/telecaller/worklist/day',
      builder: (context, state) {
        final date  = state.uri.queryParameters['date']  ?? '';
        final label = state.uri.queryParameters['label'] ?? '';
        return TelecallerWorklistDayScreen(date: date, label: label);
      },
    ),
    GoRoute(
      path: '/telecaller/profile',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>? ?? {};
        return TelecallerProfileScreen(
          account:               extra['account']               as Map<String, dynamic>? ?? {},
          accountType:           extra['accountType']           as String?               ?? 'lead',
          onCalled:              extra['onCalled']              as VoidCallback?,
          onFollowUpScheduled:   extra['onFollowUpScheduled']   as void Function(String)?,
        );
      },
    ),
    GoRoute(
      path: '/telecaller/call-scripts',
      builder: (context, state) => const TelecallerCallScriptsScreen(),
    ),
    GoRoute(
      path: '/todays-beat-plan',
      builder: (context, state) => const TodaysBeatPlanScreen(),
    ),
    GoRoute(
      path: '/all-beat-plan',
      builder: (context, state) => const AllBeatPlanScreen(),
    ),
    GoRoute(
      path: '/beat-plan/day',
      builder: (context, state) {
        final date = state.uri.queryParameters['date'] ?? '';
        return BeatPlanDayScreen(date: date);
      },
    ),
    GoRoute(
      path: '/assignment-view',
      builder: (context, state) => const AssignmentViewScreen(),
    ),
    // Unified worklist-visit screen (salesman Beat Plan + telecaller Worklist).
    // `/order-funnel/:id` kept as an alias for one release.
    GoRoute(
      path: '/visit/:id',
      builder: _worklistVisitBuilder,
    ),
    GoRoute(
      path: '/order-funnel/:id',
      builder: _worklistVisitBuilder,
    ),
  ],
);

Widget _worklistVisitBuilder(BuildContext context, GoRouterState state) {
  final id = state.pathParameters['id'] ?? '';
  final extra = state.extra as Map<String, dynamic>? ?? const {};
  final role = (UserService.currentRole ?? '').toLowerCase().trim() == 'telecaller'
      ? 'telecaller'
      : 'salesman';
  return WorklistVisitScreen(
    accountId: id,
    account: extra,
    role: (extra['role'] as String?) ?? role,
    accountType: (extra['account_type'] as String?) ?? 'lead',
    beatPlanId: extra['beat_plan_id'] is int ? extra['beat_plan_id'] as int : null,
  );
}

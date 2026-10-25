import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../core/di/service_locator.dart';
import '../core/layout/app_shell.dart';
import '../core/layout/project_detail_shell.dart';
import '../core/layout/project_tabs.dart';
import '../core/layout/role_navigation.dart';
import '../data/services/approval_inbox.dart';
import '../data/services/session_service.dart';
import '../features/auth/views/choose_role_page.dart';
import '../features/auth/views/forgot_password_page.dart';
import '../features/auth/views/login_page.dart';
import '../features/auth/views/profile_page.dart';
import '../features/schedule/views/schedule_categories_page.dart';
import '../features/schedule/views/schedule_gantt_page.dart';
import '../features/schedule/views/schedule_projects_page.dart';
import '../features/schedule/views/schedule_verification_page.dart';
import '../features/billing/views/billing_detail_page.dart';
import '../features/billing/views/billing_form_page.dart';
import '../features/billing/views/billings_page.dart';
import '../features/billing/views/expense_reports_page.dart';
import '../features/billing/views/project_financials_page.dart';
import '../features/billing/views/retention_page.dart';
import '../features/billing/views/variation_order_detail_page.dart';
import '../features/billing/views/variation_order_form_page.dart';
import '../features/billing/views/variation_orders_page.dart';
import '../features/client_portal/views/client_billing_detail_page.dart';
import '../features/client_portal/views/client_billings_page.dart';
import '../features/client_portal/views/client_photos_page.dart';
import '../features/client_portal/views/client_progress_page.dart';
import '../features/client_portal/views/client_projects_page.dart';
import '../features/client_portal/views/client_variation_order_detail_page.dart';
import '../features/client_portal/views/client_variation_orders_page.dart';
import '../features/daily_reports/views/daily_report_detail_page.dart';
import '../features/daily_reports/views/daily_report_form_page.dart';
import '../features/daily_reports/views/daily_reports_page.dart';
import '../features/dashboard/views/approvals_page.dart';
import '../features/dashboard/views/dashboard_page.dart';
import '../features/dashboard/views/notifications_page.dart';
import '../features/documents/views/project_documents_page.dart';
import '../features/labor/views/attendance_page.dart';
import '../features/labor/views/payroll_period_detail_page.dart';
import '../features/labor/views/payroll_periods_page.dart';
import '../features/labor/views/project_labor_page.dart';
import '../features/labor/views/workers_page.dart';
import '../features/procurement/views/deliveries_page.dart';
import '../features/procurement/views/delivery_confirm_page.dart';
import '../features/procurement/views/material_request_detail_page.dart';
import '../features/procurement/views/material_request_form_page.dart';
import '../features/procurement/views/material_requests_page.dart';
import '../features/procurement/views/payables_page.dart';
import '../features/procurement/views/project_materials_page.dart';
import '../features/procurement/views/purchase_order_create_page.dart';
import '../features/procurement/views/purchase_order_detail_page.dart';
import '../features/procurement/views/purchase_orders_page.dart';
import '../features/procurement/views/site_inventory_page.dart';
import '../features/procurement/views/suppliers_page.dart';
import '../features/projects/views/project_form_page.dart';
import '../features/projects/views/project_overview_page.dart';
import '../features/projects/views/projects_page.dart';
import '../features/user_management/views/company_profile_page.dart';
import '../features/user_management/views/master_lists_page.dart';
import '../features/user_management/views/settings_page.dart';
import '../features/user_management/views/user_form_page.dart';
import '../features/user_management/views/users_page.dart';

abstract final class AppRoutes {
  static const login = '/login';
  static const forgotPassword = '/forgot-password';
  static const chooseRole = '/choose-role';
  static const notifications = '/notifications';
  static const profile = '/profile';

  static const adminUsers = '/admin/users';
  static const adminUserNew = '/admin/users/new';
  static String adminUser(int userId) => '$adminUsers/$userId';
  static const adminCompany = '/admin/company';
  static const adminMasterLists = '/admin/master-lists';
  static const adminSettings = '/admin/settings';

  static const dashboard = '/dashboard';
  static const approvals = '/approvals';

  static const projects = '/projects';
  static const projectNew = '/projects/new';
  static String projectEdit(int projectId) => '$projects/$projectId/edit';
  static String projectTab(int projectId, ProjectTab tab) =>
      '$projects/$projectId/${tab.segment}';

  static const schedule = '/schedule';
  static const todoVerification = '/todo-verification';

  static const dailyReports = '/daily-reports';
  static const dailyReportNew = '/daily-reports/new';
  static String dailyReport(int id) => '$dailyReports/$id';
  static String dailyReportEdit(int id) => '$dailyReports/$id/edit';

  static const materialRequests = '/material-requests';
  static const materialRequestNew = '/material-requests/new';
  static String materialRequest(int id) => '$materialRequests/$id';
  static String materialRequestOrder(int id) => '$materialRequests/$id/order';
  static const requestQueue = '/purchasing/requests';
  static const purchaseOrders = '/purchase-orders';
  static String purchaseOrder(int id) => '$purchaseOrders/$id';
  static const suppliers = '/suppliers';
  static const deliveries = '/deliveries';
  static String deliveryConfirm(int purchaseOrderId) =>
      '$deliveries/confirm/$purchaseOrderId';
  static const siteInventory = '/site-inventory';
  static const payables = '/payables';

  static const attendance = '/attendance';
  static const workers = '/workers';
  static const payroll = '/payroll';
  static String payrollPeriod(int id) => '$payroll/$id';

  static const billings = '/billings';
  static const billingNew = '/billings/new';
  static String billing(int id) => '$billings/$id';
  static const variationOrders = '/variation-orders';
  static const variationOrderNew = '/variation-orders/new';
  static String variationOrder(int id) => '$variationOrders/$id';
  static const retention = '/retention';
  static const expenseReports = '/expense-reports';

  static const clientProjects = '/client/projects';
  static const clientProgress = '/client/progress';
  static String clientProgressFor(int projectId) =>
      '$clientProgress/$projectId';
  static const clientPhotos = '/client/photos';
  static const clientBillings = '/client/billings';
  static String clientBilling(int id) => '$clientBillings/$id';
  static const clientVariationOrders = '/client/variation-orders';
  static String clientVariationOrder(int id) => '$clientVariationOrders/$id';
}

/// Reads an integer path parameter.
int _id(GoRouterState state, String name) =>
    int.parse(state.pathParameters[name]!);

/// Reads an optional integer query parameter, e.g. `?projectId=1`.
int? _queryId(GoRouterState state, String name) =>
    int.tryParse(state.uri.queryParameters[name] ?? '');

GoRoute _route(String path, Widget Function(GoRouterState state) page) =>
    GoRoute(path: path, builder: (context, state) => page(state));

/// Pages for each project detail tab.
final _projectTabPages = <ProjectTab, Widget Function(int projectId)>{
  ProjectTab.overview: (id) => ProjectOverviewPage(projectId: id),
  ProjectTab.schedule: (id) => ScheduleCategoriesPage(projectId: id),
  ProjectTab.gantt: (id) => ScheduleGanttPage(projectId: id),
  ProjectTab.dailyReports: (id) => DailyReportsPage(projectId: id),
  ProjectTab.materials: (id) => ProjectMaterialsPage(projectId: id),
  ProjectTab.labor: (id) => ProjectLaborPage(projectId: id),
  ProjectTab.financials: (id) => ProjectFinancialsPage(projectId: id),
  ProjectTab.documents: (id) => ProjectDocumentsPage(projectId: id),
};

/// Project detail: a nested shell with one route per tab.
final _projectDetailRoutes = ShellRoute(
  builder: (context, state, child) {
    final tab = ProjectTab.fromSegment(state.uri.pathSegments[2])!;
    return ProjectDetailShell(
      projectId: _id(state, 'projectId'),
      tab: tab,
      child: child,
    );
  },
  routes: [
    for (final tab in ProjectTab.values)
      _route('${AppRoutes.projects}/:projectId/${tab.segment}', (state) {
        final id = _id(state, 'projectId');
        return _projectTabPages[tab]!(id);
      }),
  ],
);

/// Feature routes. They are flat siblings, not nested, so returning to a list
/// rebuilds it with fresh data.
final _featureRoutes = <GoRoute>[
  // auth
  _route(AppRoutes.profile, (_) => const ProfilePage()),
  // user_management
  _route(AppRoutes.adminUsers, (_) => const UsersPage()),
  _route(AppRoutes.adminUserNew, (_) => const UserFormPage()),
  _route(
    '${AppRoutes.adminUsers}/:userId',
    (state) => UserFormPage(
      key: ValueKey(state.pathParameters['userId']),
      userId: _id(state, 'userId'),
    ),
  ),
  _route(AppRoutes.adminCompany, (_) => const CompanyProfilePage()),
  _route(AppRoutes.adminMasterLists, (_) => const MasterListsPage()),
  _route(AppRoutes.adminSettings, (_) => const SettingsPage()),
  // client_portal
  _route(AppRoutes.clientProjects, (_) => const ClientProjectsPage()),
  _route(AppRoutes.clientProgress, (_) => const ClientProgressPage()),
  _route(
    '${AppRoutes.clientProgress}/:projectId',
    (state) => ClientProgressPage(projectId: _id(state, 'projectId')),
  ),
  _route(AppRoutes.clientPhotos, (_) => const ClientPhotosPage()),
  _route(AppRoutes.clientBillings, (_) => const ClientBillingsPage()),
  _route(
    '${AppRoutes.clientBillings}/:billingId',
    (state) => ClientBillingDetailPage(billingId: _id(state, 'billingId')),
  ),
  _route(
    AppRoutes.clientVariationOrders,
    (_) => const ClientVariationOrdersPage(),
  ),
  _route(
    '${AppRoutes.clientVariationOrders}/:voId',
    (state) => ClientVariationOrderDetailPage(voId: _id(state, 'voId')),
  ),
  // dashboard
  _route(AppRoutes.dashboard, (_) => const DashboardPage()),
  _route(
    AppRoutes.approvals,
    (state) => ApprovalsPage(
      initialKind: ApprovalKind.values
          .where((k) => k.name == state.uri.queryParameters['kind'])
          .firstOrNull,
    ),
  ),
  _route(AppRoutes.notifications, (_) => const NotificationsPage()),
  // projects
  _route(AppRoutes.projects, (_) => const ProjectsPage()),
  _route(AppRoutes.projectNew, (_) => const ProjectFormPage()),
  _route(
    '${AppRoutes.projects}/:projectId/edit',
    (state) => ProjectFormPage(projectId: _id(state, 'projectId')),
  ),
  GoRoute(
    path: '${AppRoutes.projects}/:projectId',
    redirect: (context, state) =>
        AppRoutes.projectTab(_id(state, 'projectId'), ProjectTab.overview),
  ),
  // daily_reports
  _route(AppRoutes.dailyReports, (_) => const DailyReportsPage()),
  _route(
    AppRoutes.dailyReportNew,
    (state) => DailyReportFormPage(projectId: _queryId(state, 'projectId')),
  ),
  _route(
    '${AppRoutes.dailyReports}/:reportId',
    (state) => DailyReportDetailPage(reportId: _id(state, 'reportId')),
  ),
  _route(
    '${AppRoutes.dailyReports}/:reportId/edit',
    (state) => DailyReportFormPage(reportId: _id(state, 'reportId')),
  ),
  // procurement
  _route(AppRoutes.materialRequests, (_) => const MaterialRequestsPage()),
  _route(
    AppRoutes.materialRequestNew,
    (state) => MaterialRequestFormPage(projectId: _queryId(state, 'projectId')),
  ),
  _route(
    '${AppRoutes.materialRequests}/:requestId',
    (state) => MaterialRequestDetailPage(requestId: _id(state, 'requestId')),
  ),
  _route(
    '${AppRoutes.materialRequests}/:requestId/order',
    (state) => PurchaseOrderCreatePage(requestId: _id(state, 'requestId')),
  ),
  _route(
    AppRoutes.requestQueue,
    (_) => const MaterialRequestsPage(queue: true),
  ),
  _route(AppRoutes.purchaseOrders, (_) => const PurchaseOrdersPage()),
  _route(
    '${AppRoutes.purchaseOrders}/:orderId',
    (state) => PurchaseOrderDetailPage(orderId: _id(state, 'orderId')),
  ),
  _route(AppRoutes.suppliers, (_) => const SuppliersPage()),
  _route(AppRoutes.deliveries, (_) => const DeliveriesPage()),
  _route(
    '${AppRoutes.deliveries}/confirm/:orderId',
    (state) => DeliveryConfirmPage(orderId: _id(state, 'orderId')),
  ),
  _route(AppRoutes.siteInventory, (_) => const SiteInventoryPage()),
  _route(AppRoutes.payables, (_) => const PayablesPage()),
  // billing
  _route(AppRoutes.billings, (_) => const BillingsPage()),
  _route(
    AppRoutes.billingNew,
    (state) => BillingFormPage(projectId: _queryId(state, 'projectId')),
  ),
  _route(
    '${AppRoutes.billings}/:billingId',
    (state) => BillingDetailPage(billingId: _id(state, 'billingId')),
  ),
  _route(AppRoutes.variationOrders, (_) => const VariationOrdersPage()),
  _route(
    AppRoutes.variationOrderNew,
    (state) => VariationOrderFormPage(projectId: _queryId(state, 'projectId')),
  ),
  _route(
    '${AppRoutes.variationOrders}/:voId',
    (state) => VariationOrderDetailPage(voId: _id(state, 'voId')),
  ),
  _route(
    '${AppRoutes.variationOrders}/:voId/edit',
    (state) => VariationOrderFormPage(voId: _id(state, 'voId')),
  ),
  _route(AppRoutes.retention, (_) => const RetentionPage()),
  _route(AppRoutes.expenseReports, (_) => const ExpenseReportsPage()),
  // labor
  _route(
    AppRoutes.attendance,
    (state) => AttendancePage(projectId: _queryId(state, 'projectId')),
  ),
  _route(AppRoutes.workers, (_) => const WorkersPage()),
  _route(AppRoutes.payroll, (_) => const PayrollPeriodsPage()),
  _route(
    '${AppRoutes.payroll}/:periodId',
    (state) => PayrollPeriodDetailPage(periodId: _id(state, 'periodId')),
  ),
  // schedule
  _route(AppRoutes.schedule, (_) => const ScheduleProjectsPage()),
  _route(AppRoutes.todoVerification, (_) => const ScheduleVerificationPage()),
];

GoRouter createRouter() {
  final session = getIt<SessionService>();
  return GoRouter(
    initialLocation: AppRoutes.login,
    refreshListenable: session,
    redirect: (context, state) {
      final location = state.uri.path;
      final public =
          location == AppRoutes.login || location == AppRoutes.forgotPassword;
      final role = session.activeRole;
      if (!session.isSignedIn || role == null) {
        return public ? null : AppRoutes.login;
      }
      if (public) return RoleNavigation.homeFor(role);
      if (location == AppRoutes.chooseRole) return null;
      if (!RoleNavigation.allows(role, location)) {
        return RoleNavigation.homeFor(role);
      }
      return null;
    },
    routes: [
      _route(AppRoutes.login, (_) => const LoginPage()),
      _route(AppRoutes.forgotPassword, (_) => const ForgotPasswordPage()),
      _route(AppRoutes.chooseRole, (_) => const ChooseRolePage()),
      ShellRoute(
        builder: (context, state, child) =>
            AppShell(location: state.uri.path, child: child),
        routes: [..._featureRoutes, _projectDetailRoutes],
      ),
    ],
  );
}

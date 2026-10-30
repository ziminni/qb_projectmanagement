import 'package:flutter/material.dart';

import '../../data/models/app_role.dart';
import '../../routes/routes.dart';
import 'project_tabs.dart';

class RoleDestination {
  const RoleDestination(this.label, this.icon, this.path);

  final String label;
  final IconData icon;
  final String path;
}

/// Navigation for each role's app shell, from "Screens by role". The first
/// destination is the role's landing screen.
abstract final class RoleNavigation {
  static const _destinations = <AppRole, List<RoleDestination>>{
    AppRole.admin: [
      RoleDestination('Users', Icons.people_outline, AppRoutes.adminUsers),
      RoleDestination(
        'Company profile',
        Icons.business_outlined,
        AppRoutes.adminCompany,
      ),
      RoleDestination(
        'Master lists',
        Icons.list_alt_outlined,
        AppRoutes.adminMasterLists,
      ),
      RoleDestination(
        'Settings',
        Icons.settings_outlined,
        AppRoutes.adminSettings,
      ),
    ],
    AppRole.owner: [
      RoleDestination(
        'Dashboard',
        Icons.dashboard_outlined,
        AppRoutes.dashboard,
      ),
      RoleDestination(
        'My projects',
        Icons.apartment_outlined,
        AppRoutes.projects,
      ),
      RoleDestination('Approvals', Icons.inbox_outlined, AppRoutes.approvals),
      RoleDestination(
        'Purchasing',
        Icons.shopping_cart_outlined,
        AppRoutes.requestQueue,
      ),
      RoleDestination(
        'Billing',
        Icons.receipt_long_outlined,
        AppRoutes.billings,
      ),
      RoleDestination(
        'Variation orders',
        Icons.difference_outlined,
        AppRoutes.variationOrders,
      ),
      RoleDestination(
        'Price lists',
        Icons.list_alt_outlined,
        AppRoutes.adminMasterLists,
      ),
    ],
    AppRole.siteEngineer: [
      RoleDestination(
        'My sites',
        Icons.location_city_outlined,
        AppRoutes.projects,
      ),
      RoleDestination(
        'Daily reports',
        Icons.edit_note_outlined,
        AppRoutes.dailyReports,
      ),
      RoleDestination(
        'To-do checklist',
        Icons.checklist_outlined,
        AppRoutes.schedule,
      ),
      RoleDestination('Attendance', Icons.badge_outlined, AppRoutes.attendance),
      RoleDestination(
        'Material requests',
        Icons.inventory_2_outlined,
        AppRoutes.materialRequests,
      ),
      RoleDestination(
        'Deliveries',
        Icons.local_shipping_outlined,
        AppRoutes.deliveries,
      ),
    ],
    AppRole.accountant: [
      RoleDestination('Payroll', Icons.payments_outlined, AppRoutes.payroll),
      RoleDestination(
        'Billings and payments',
        Icons.receipt_long_outlined,
        AppRoutes.billings,
      ),
      RoleDestination(
        'Supplier payables',
        Icons.request_quote_outlined,
        AppRoutes.payables,
      ),
      RoleDestination('Retention', Icons.savings_outlined, AppRoutes.retention),
      RoleDestination(
        'Expense reports',
        Icons.summarize_outlined,
        AppRoutes.expenseReports,
      ),
      RoleDestination('Workers', Icons.engineering_outlined, AppRoutes.workers),
    ],
    AppRole.client: [
      RoleDestination(
        'My projects',
        Icons.apartment_outlined,
        AppRoutes.clientProjects,
      ),
      RoleDestination(
        'Progress',
        Icons.insights_outlined,
        AppRoutes.clientProgress,
      ),
      RoleDestination(
        'Photos',
        Icons.photo_library_outlined,
        AppRoutes.clientPhotos,
      ),
      RoleDestination(
        'Billings',
        Icons.receipt_long_outlined,
        AppRoutes.clientBillings,
      ),
      RoleDestination(
        'Variation orders',
        Icons.difference_outlined,
        AppRoutes.clientVariationOrders,
      ),
    ],
  };

  /// Screens a role reaches from links rather than its navigation, following
  /// the permission matrix.
  static const _linked = <AppRole, List<String>>{
    AppRole.owner: [
      AppRoutes.schedule,
      AppRoutes.todoVerification,
      AppRoutes.dailyReports,
      AppRoutes.materialRequests,
      AppRoutes.purchaseOrders,
      AppRoutes.payroll,
      AppRoutes.workers,
      AppRoutes.retention,
      AppRoutes.expenseReports,
      AppRoutes.suppliers,
      AppRoutes.siteInventory,
      AppRoutes.deliveries,
    ],
    AppRole.siteEngineer: [AppRoutes.variationOrders, AppRoutes.purchaseOrders],
    AppRole.accountant: [AppRoutes.projects, AppRoutes.purchaseOrders],
  };

  /// Screens every user has, reached from the app bar.
  static const common = [
    RoleDestination(
      'Notifications',
      Icons.notifications_outlined,
      AppRoutes.notifications,
    ),
    RoleDestination('My profile', Icons.person_outline, AppRoutes.profile),
  ];

  /// Every section of the app, used to title pages a role reaches from a
  /// link rather than its navigation, and to give them a way back.
  static const _sections = [
    RoleDestination('Projects', Icons.apartment_outlined, AppRoutes.projects),
    RoleDestination(
      'Schedule',
      Icons.view_timeline_outlined,
      AppRoutes.schedule,
    ),
    RoleDestination(
      'To-do verification',
      Icons.fact_check_outlined,
      AppRoutes.todoVerification,
    ),
    RoleDestination(
      'Daily reports',
      Icons.edit_note_outlined,
      AppRoutes.dailyReports,
    ),
    RoleDestination(
      'Material requests',
      Icons.inventory_2_outlined,
      AppRoutes.materialRequests,
    ),
    RoleDestination(
      'Purchase orders',
      Icons.shopping_cart_outlined,
      AppRoutes.purchaseOrders,
    ),
    RoleDestination(
      'Deliveries',
      Icons.local_shipping_outlined,
      AppRoutes.deliveries,
    ),
    RoleDestination('Payroll', Icons.payments_outlined, AppRoutes.payroll),
    RoleDestination('Workers', Icons.engineering_outlined, AppRoutes.workers),
    RoleDestination('Billing', Icons.receipt_long_outlined, AppRoutes.billings),
    RoleDestination(
      'Variation orders',
      Icons.difference_outlined,
      AppRoutes.variationOrders,
    ),
    RoleDestination('Retention', Icons.savings_outlined, AppRoutes.retention),
    RoleDestination(
      'Expense reports',
      Icons.summarize_outlined,
      AppRoutes.expenseReports,
    ),
    ...common,
  ];

  /// The section [location] belongs to, whether or not it is in the
  /// role's navigation.
  static RoleDestination? sectionFor(String location) {
    RoleDestination? best;
    for (final s in _sections) {
      if (_isWithin(location, s.path) &&
          (best == null || s.path.length > best.path.length)) {
        best = s;
      }
    }
    return best;
  }

  /// Only owners create and edit projects.
  static const _projectEditors = [AppRole.owner];

  static List<RoleDestination> forRole(AppRole role) => _destinations[role]!;

  static String homeFor(AppRole role) => forRole(role).first.path;

  static Iterable<RoleDestination> get all =>
      _destinations.values.expand((d) => d);

  /// Index of the destination [location] belongs to, or -1.
  static int indexFor(AppRole role, String location) {
    final destinations = forRole(role);
    var best = -1;
    var bestLength = -1;
    for (var i = 0; i < destinations.length; i++) {
      final path = destinations[i].path;
      if (_isWithin(location, path) && path.length > bestLength) {
        best = i;
        bestLength = path.length;
      }
    }
    return best;
  }

  /// Whether [role] may open [location].
  static bool allows(AppRole role, String location) {
    final reachable =
        indexFor(role, location) >= 0 ||
        (_linked[role] ?? const []).any((p) => _isWithin(location, p)) ||
        common.any((d) => _isWithin(location, d.path));
    if (!reachable) return false;
    if (_isWithin(location, AppRoutes.projects)) {
      return _allowsProjectPath(role, location);
    }
    return true;
  }

  static bool _allowsProjectPath(AppRole role, String location) {
    final segments = Uri.parse(location).pathSegments;
    // /projects/new and /projects/:id/edit
    if (segments.length >= 2 && segments[1] == 'new') {
      return _projectEditors.contains(role);
    }
    if (segments.length >= 3 && segments[2] == 'edit') {
      return _projectEditors.contains(role);
    }
    // /projects/:id/:tab
    if (segments.length >= 3) {
      final tab = ProjectTab.fromSegment(segments[2]);
      return tab != null && tab.roles.contains(role);
    }
    return true;
  }

  static bool _isWithin(String location, String path) =>
      location == path || location.startsWith('$path/');
}

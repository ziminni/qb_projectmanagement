import 'package:flutter/foundation.dart' show ChangeNotifier;

import '../../../data/models/app_role.dart';
import '../../../data/models/audit_log.dart';
import '../../../data/models/client.dart';
import '../../../data/models/project_assignment.dart';
import '../../../data/models/user.dart';
import '../../../data/repositories/audit_log_repository.dart';
import '../../../data/repositories/client_repository.dart';
import '../../../data/repositories/company_repository.dart';
import '../../../data/repositories/project_repository.dart';
import '../../../data/repositories/user_repository.dart';
import '../../../data/services/master_data_rules.dart';
import '../../../routes/routes.dart';

/// Something the admin should look at, linking to where it is fixed.
class AdminAttention {
  const AdminAttention(this.title, this.detail, {this.userId, this.path});

  final String title;
  final String detail;

  /// Opens this user's details when set.
  final int? userId;

  /// Opens this route when set (and [userId] is not).
  final String? path;
}

/// The admin's landing screen: account health, roles, open issues and
/// recent activity. Shows no financial figures.
class AdminOverviewViewModel extends ChangeNotifier {
  AdminOverviewViewModel({
    required UserRepository users,
    required ClientRepository clients,
    required ProjectRepository projects,
    required AuditLogRepository auditLog,
    required CompanyRepository company,
    DateTime Function()? now,
  }) : _users = users,
       _clients = clients,
       _projects = projects,
       _auditLog = auditLog,
       _company = company,
       _now = now ?? DateTime.now;

  final UserRepository _users;
  final ClientRepository _clients;
  final ProjectRepository _projects;
  final AuditLogRepository _auditLog;
  final CompanyRepository _company;
  final DateTime Function() _now;

  bool _loading = true;
  String? _error;
  List<User> _allUsers = const [];
  Map<int, List<AppRole>> _rolesByUser = const {};
  List<Client> _clientList = const [];
  List<AuditLog> _log = const [];
  final List<AdminAttention> _attention = [];

  bool get isLoading => _loading;
  String? get error => _error;

  int get totalUsers => _allUsers.length;
  int get activeUsers => _allUsers.where((u) => u.isActive).length;
  int get inactiveUsers => totalUsers - activeUsers;

  /// Clients in the master list with no portal login linked.
  List<Client> get clientsWithoutLogin =>
      _clientList.where((c) => c.userId == null).toList();

  /// Active users holding each role. A user with two roles counts twice.
  Map<AppRole, int> get usersByRole => {
    for (final r in AppRole.values)
      r: _allUsers
          .where((u) => u.isActive && (_rolesByUser[u.id] ?? []).contains(r))
          .length,
  };

  /// Audit entries in the last seven days.
  int get activityThisWeek {
    final since = _now().subtract(const Duration(days: 7));
    return _log.where((l) => l.createdAt.isAfter(since)).length;
  }

  List<AuditLog> get recentActivity => _log.take(8).toList();

  List<AdminAttention> get attention => _attention;

  String userName(int id) {
    for (final u in _allUsers) {
      if (u.id == id) return u.fullName;
    }
    return 'User #$id';
  }

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _allUsers = await _users.getUsers();
      final roles = await _users.getAllUserRoles();
      _rolesByUser = {
        for (final u in _allUsers)
          u.id: [
            for (final r in roles)
              if (r.userId == u.id) r.role,
          ],
      };
      _clientList = await _clients.getClients();
      _log = await _auditLog.getAll();
      await _buildAttention();
    } catch (e) {
      _error = 'Could not load the overview. $e';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> _buildAttention() async {
    _attention.clear();

    final company = await _company.getCompany();
    final pcab = MasterDataRules.pcabReminder(
      company.pcabLicenseExpiry,
      _now(),
    );
    if (pcab != null) {
      _attention.add(
        AdminAttention('PCAB license', pcab, path: AppRoutes.adminLicenses),
      );
    }

    for (final c in clientsWithoutLogin) {
      _attention.add(
        AdminAttention(
          '${c.name} has no portal login',
          'The client cannot accept project requests or view progress '
              'until you create a login for them.',
          path: AppRoutes.adminUserNew,
        ),
      );
    }

    // Field staff with no project to work on.
    for (final u in _allUsers.where((u) => u.isActive)) {
      final roles = _rolesByUser[u.id] ?? const [];
      if (roles.isEmpty) {
        _attention.add(
          AdminAttention(
            '${u.fullName} has no role',
            'They cannot sign in until they are given a role.',
            userId: u.id,
          ),
        );
        continue;
      }
      if (!roles.contains(AppRole.siteEngineer)) continue;
      final assignments = await _projects.getAssignmentsForUser(u.id);
      final active = assignments.where(
        (a) =>
            a.roleOnProject == AppRole.siteEngineer &&
            a.response != RequestResponse.declined,
      );
      if (active.isEmpty) {
        _attention.add(
          AdminAttention(
            '${u.fullName} is not on any site',
            'Assign them to a project so they can file daily reports and '
                'attendance.',
            userId: u.id,
          ),
        );
      }
    }
  }
}

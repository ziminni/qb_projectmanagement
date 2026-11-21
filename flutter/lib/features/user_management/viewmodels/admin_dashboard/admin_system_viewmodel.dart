import '../../../../data/models/app_role.dart';
import '../../../../data/models/audit_log.dart';
import '../../../../data/models/client.dart';
import '../../../../data/models/project_assignment.dart';
import '../../../../data/models/user.dart';
import '../../../../data/repositories/audit_log_repository.dart';
import '../../../../data/repositories/client_repository.dart';
import '../../../../data/repositories/company_repository.dart';
import '../../../../data/repositories/project_repository.dart';
import '../../../../data/repositories/user_repository.dart';
import '../../../../data/services/master_data_rules.dart';
import '../../../../routes/routes.dart';
import 'admin_tab_viewmodel.dart';

/// How urgent an attention item is; urgent items sort first.
enum AttentionLevel { urgent, warning }

/// Something the admin should look at, linking to where it is fixed.
class AdminAttention {
  const AdminAttention(
    this.title,
    this.detail, {
    this.userId,
    this.path,
    this.level = AttentionLevel.warning,
  });

  final String title;
  final String detail;

  /// Opens this user's details when set.
  final int? userId;

  /// Opens this route when set (and [userId] is not).
  final String? path;
  final AttentionLevel level;
}

/// The System tab: account health, roles, open issues and recent activity.
class AdminSystemViewModel extends AdminTabViewModel {
  AdminSystemViewModel({
    required UserRepository users,
    required ClientRepository clients,
    required ProjectRepository projects,
    required AuditLogRepository auditLog,
    required CompanyRepository company,
    super.now,
  }) : _users = users,
       _clients = clients,
       _projects = projects,
       _auditLog = auditLog,
       _company = company;

  final UserRepository _users;
  final ClientRepository _clients;
  final ProjectRepository _projects;
  final AuditLogRepository _auditLog;
  final CompanyRepository _company;

  List<User> _allUsers = const [];
  Map<int, List<AppRole>> _rolesByUser = const {};
  List<Client> _clientList = const [];
  List<AuditLog> _log = const [];
  List<AdminAttention> _attention = const [];

  @override
  String get subject => 'the system overview';

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

  /// Accounts created in the last 30 days.
  int get newUsersThisMonth {
    final since = now().subtract(const Duration(days: 30));
    return _allUsers
        .where((u) => u.createdAt != null && u.createdAt!.isAfter(since))
        .length;
  }

  /// Audit entries in the last seven days.
  int get activityThisWeek {
    final since = now().subtract(const Duration(days: 7));
    return _log.where((l) => l.createdAt.isAfter(since)).length;
  }

  List<AuditLog> get recentActivity => _log.take(6).toList();

  List<AdminAttention> get attention => _attention;

  String userName(int id) {
    for (final u in _allUsers) {
      if (u.id == id) return u.fullName;
    }
    return 'User #$id';
  }

  @override
  Future<void> fetch() async {
    final (users, roles, clients, log, company) = await (
      _users.getUsers(),
      _users.getAllUserRoles(),
      _clients.getClients(),
      _auditLog.getAll(),
      _company.getCompany(),
    ).wait;
    _allUsers = users;
    _rolesByUser = {
      for (final u in users)
        u.id: [
          for (final r in roles)
            if (r.userId == u.id) r.role,
        ],
    };
    _clientList = clients;
    _log = [...log]..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    final items = <AdminAttention>[];
    final pcab = MasterDataRules.pcabReminder(company.pcabLicenseExpiry, now());
    if (pcab != null) {
      items.add(
        AdminAttention(
          'PCAB license',
          pcab,
          path: AppRoutes.adminLicenses,
          level: AttentionLevel.urgent,
        ),
      );
    }

    for (final c in clientsWithoutLogin) {
      items.add(
        AdminAttention(
          '${c.name} has no portal login',
          'The client cannot accept project requests or view progress '
              'until you create a login for them.',
          path: AppRoutes.adminUserNewForClient(c.id),
        ),
      );
    }

    final active = _allUsers.where((u) => u.isActive).toList();
    for (final u in active) {
      if ((_rolesByUser[u.id] ?? const []).isEmpty) {
        items.add(
          AdminAttention(
            '${u.fullName} has no role',
            'They cannot sign in until they are given a role.',
            userId: u.id,
            level: AttentionLevel.urgent,
          ),
        );
      }
    }

    // Site engineers with no site: look their assignments up together.
    final engineers = [
      for (final u in active)
        if ((_rolesByUser[u.id] ?? const []).contains(AppRole.siteEngineer)) u,
    ];
    final assignments = await Future.wait([
      for (final u in engineers) _projects.getAssignmentsForUser(u.id),
    ]);
    for (final (i, u) in engineers.indexed) {
      final onSite = assignments[i].any(
        (a) =>
            a.roleOnProject == AppRole.siteEngineer &&
            a.response != RequestResponse.declined,
      );
      if (!onSite) {
        items.add(
          AdminAttention(
            '${u.fullName} is not on any site',
            'Assign them to a project so they can file daily reports and '
                'attendance.',
            userId: u.id,
          ),
        );
      }
    }
    items.sort((a, b) => a.level.index.compareTo(b.level.index));
    _attention = items;
  }
}

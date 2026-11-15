import 'package:flutter/foundation.dart' show ChangeNotifier;

import '../../../core/utils/action_runner.dart';
import '../../../data/models/app_role.dart';
import '../../../data/models/audit_log.dart';
import '../../../data/models/client.dart';
import '../../../data/models/project.dart';
import '../../../data/models/project_assignment.dart';
import '../../../data/models/user.dart';
import '../../../data/repositories/audit_log_repository.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/client_repository.dart';
import '../../../data/repositories/project_repository.dart';
import '../../../data/repositories/user_repository.dart';
import '../../../data/services/business_rule_exception.dart';
import '../../../data/services/session_service.dart';
import 'admin_audit.dart';

/// One user's account as the admin sees it: roles, project assignments,
/// client link and activity, with activate/deactivate and password reset.
class UserDetailViewModel extends ChangeNotifier with ActionRunner {
  UserDetailViewModel({
    required this.userId,
    required UserRepository users,
    required ProjectRepository projects,
    required ClientRepository clients,
    required AuditLogRepository auditLog,
    required AuthRepository auth,
    required SessionService session,
    AdminAudit? audit,
  }) : _users = users,
       _projects = projects,
       _clients = clients,
       _auditLog = auditLog,
       _auth = auth,
       _session = session,
       _audit = audit;

  final int userId;
  final UserRepository _users;
  final ProjectRepository _projects;
  final ClientRepository _clients;
  final AuditLogRepository _auditLog;
  final AuthRepository _auth;
  final SessionService _session;
  final AdminAudit? _audit;

  bool _loading = true;
  String? _error;
  User? _user;
  List<AppRole> _roles = const [];
  List<(ProjectAssignment, Project?)> _assignments = const [];
  Client? _client;
  List<AuditLog> _activity = const [];
  Map<int, String> _names = const {};

  bool get isLoading => _loading;
  String? get error => _error;
  User? get user => _user;
  List<AppRole> get roles => _roles;
  List<(ProjectAssignment, Project?)> get assignments => _assignments;

  /// The client record this login belongs to, for client users.
  Client? get client => _client;

  /// What this user did, and what was done to their account, newest first.
  List<AuditLog> get activity => _activity;

  bool get isSelf => userId == _session.user?.id;

  String nameOf(int id) => _names[id] ?? 'User #$id';

  Future<void> load() async {
    _loading = true;
    notifyListeners();
    try {
      _user = await _users.getUser(userId);
      if (_user == null) {
        _error = 'User not found.';
        return;
      }
      _roles = await _users.getRoles(userId);
      _names = {for (final u in await _users.getUsers()) u.id: u.fullName};

      final projects = {for (final p in await _projects.getProjects()) p.id: p};
      _assignments = [
        for (final a in await _projects.getAssignmentsForUser(userId))
          (a, projects[a.projectId]),
      ];

      _client = null;
      for (final c in await _clients.getClients()) {
        if (c.userId == userId) _client = c;
      }

      _activity = [
        for (final l in await _auditLog.getAll())
          if (l.userId == userId ||
              (l.entity == 'user' && l.entityId == userId))
            l,
      ];
    } catch (e) {
      _error = 'Could not load this user. $e';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<String?> setActive(bool active) => runAction(() async {
    if (isSelf && !active) {
      throw const BusinessRuleException('You cannot deactivate yourself.');
    }
    final saved = await _users.setActive(userId, active);
    await _audit?.record(
      active ? 'user_reactivated' : 'user_deactivated',
      entity: 'user',
      entityId: userId,
      details: {'name': saved.fullName},
    );
    await load();
  });

  String? _temporaryPassword;

  /// Set after a successful [resetPassword].
  String? get temporaryPassword => _temporaryPassword;

  Future<String?> resetPassword() => runAction(() async {
    _temporaryPassword = await _auth.resetPassword(userId);
    await _audit?.record(
      'password_reset',
      entity: 'user',
      entityId: userId,
      details: {'name': _user?.fullName ?? ''},
    );
    await load();
  });
}

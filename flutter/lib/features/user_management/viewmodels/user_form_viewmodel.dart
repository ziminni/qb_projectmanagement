import 'package:flutter/foundation.dart' show ChangeNotifier;

import '../../../core/network/api_config.dart';
import '../../../core/utils/action_runner.dart';
import '../../../data/models/app_role.dart';
import '../../../data/models/client.dart';
import '../../../data/models/project.dart';
import '../../../data/models/user.dart';
import '../../../data/repositories/client_repository.dart';
import '../../../data/repositories/mock_data.dart';
import '../../../data/repositories/project_repository.dart';
import '../../../data/repositories/user_repository.dart';
import '../../../data/services/business_rule_exception.dart';
import '../../../data/services/session_service.dart';
import 'admin_audit.dart';

typedef AssignmentDraft = ({int projectId, AppRole role});

/// Create or edit a user with their roles, project assignments and, for
/// client users, the client record their portal login belongs to.
class UserFormViewModel extends ChangeNotifier with ActionRunner {
  UserFormViewModel({
    required this.userId,
    this.prefillClientId,
    required UserRepository users,
    required ProjectRepository projects,
    required ClientRepository clients,
    required SessionService session,
    AdminAudit? audit,
    bool? usesApi,
  }) : _users = users,
       _projects = projects,
       _clients = clients,
       _session = session,
       _audit = audit,
       _usesApi = usesApi ?? useApi;

  /// Null when creating a user.
  final int? userId;

  /// Creating a portal login for this client: starts with the client role
  /// and the client chosen. Ignored when editing.
  final int? prefillClientId;
  final UserRepository _users;
  final ProjectRepository _projects;
  final ClientRepository _clients;
  final SessionService _session;
  final AdminAudit? _audit;
  final bool _usesApi;

  bool _loading = true;
  String? _error;
  User? _user;
  List<Project> _allProjects = const [];
  List<Client> _allClients = const [];

  // Editable state.
  Set<AppRole> roles = {};
  List<AssignmentDraft> assignments = [];
  AssignmentDraft? _pendingAssignment;
  int? clientId;
  bool isActive = true;

  bool get isLoading => _loading;
  String? get error => _error;
  bool get isNew => userId == null;
  User? get user => _user;
  List<Project> get projects => _allProjects;
  List<Client> get clients => _allClients;
  bool get isSelf => userId != null && userId == _session.user?.id;
  String? get temporaryPassword => _users.lastTemporaryPassword;

  /// Company a user is created under. The API scopes every row to the
  /// signed-in user's company, so the mock id must never be sent there.
  int get _companyId {
    final known = _user?.companyId;
    if (known != null) return known;
    if (!_usesApi) return MockData.companyId;
    final sessionCompanyId = _session.user?.companyId;
    if (sessionCompanyId == null) {
      throw const BusinessRuleException('Sign in again to save a user.');
    }
    return sessionCompanyId;
  }

  /// Roles that can be assigned to projects, limited to those selected.
  List<AppRole> get assignableRoles => [
    for (final r in const [AppRole.owner, AppRole.siteEngineer, AppRole.client])
      if (roles.contains(r)) r,
  ];

  Client? clientById(int id) {
    for (final c in _allClients) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// The client this new login was opened for, when it still has none.
  Client? get prefillClient {
    if (!isNew || prefillClientId == null) return null;
    final c = clientById(prefillClientId!);
    return c != null && c.userId == null ? c : null;
  }

  Project? projectById(int id) {
    for (final p in _allProjects) {
      if (p.id == id) return p;
    }
    return null;
  }

  Future<void> load() async {
    _loading = true;
    notifyListeners();
    try {
      _allProjects = await _projects.getProjects();
      _allClients = await _clients.getClients();
      if (userId != null) {
        _user = await _users.getUser(userId!);
        if (_user == null) {
          _error = 'User not found.';
          return;
        }
        isActive = _user!.isActive;
        roles = (await _users.getRoles(userId!)).toSet();
        assignments = [
          for (final a in await _projects.getAssignmentsForUser(userId!))
            (projectId: a.projectId, role: a.roleOnProject),
        ];
        clientId = (await _clients.getClientForUser(userId!))?.id;
      } else if (prefillClientId != null) {
        final client = clientById(prefillClientId!);
        if (client != null && client.userId == null) {
          roles = {AppRole.client};
          clientId = client.id;
        }
      }
    } catch (e) {
      _error = 'Could not load the user. $e';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  void toggleRole(AppRole role, bool selected) {
    if (selected) {
      roles.add(role);
    } else {
      roles.remove(role);
      assignments.removeWhere((a) => a.role == role);
      if (_pendingAssignment?.role == role) _pendingAssignment = null;
      if (role == AppRole.client) clientId = null;
    }
    notifyListeners();
  }

  void setActive(bool value) {
    isActive = value;
    notifyListeners();
  }

  void setClient(int? id) {
    clientId = id;
    assignments.removeWhere(
      (a) =>
          a.role == AppRole.client && projectById(a.projectId)?.clientId != id,
    );
    if (_pendingAssignment?.role == AppRole.client &&
        projectById(_pendingAssignment!.projectId)?.clientId != id) {
      _pendingAssignment = null;
    }
    notifyListeners();
  }

  /// Tracks the dropdown selection in [UserManagementAssignmentEditor] so
  /// clicking "Create user" / "Save changes" without clicking "Assign" first
  /// still saves the selected project.
  void setPendingAssignment(AssignmentDraft? draft) {
    _pendingAssignment = draft;
  }

  /// Projects a new assignment in [role] may use. Client users only see
  /// their own client's projects.
  List<Project> projectsFor(AppRole role) => _allProjects.where((p) {
    if (assignments.any((a) => a.projectId == p.id && a.role == role)) {
      return false;
    }
    return role != AppRole.client || p.clientId == clientId;
  }).toList();

  void addAssignment(int projectId, AppRole role) {
    assignments.add((projectId: projectId, role: role));
    _pendingAssignment = null;
    notifyListeners();
  }

  void removeAssignment(AssignmentDraft a) {
    assignments.remove(a);
    notifyListeners();
  }

  /// Saves and returns null, or an error message.
  Future<String?> save({
    required String fullName,
    required String email,
    required String phone,
  }) => runAction(() async {
    if (roles.isEmpty) {
      throw const BusinessRuleException('Give the user at least one role.');
    }
    if (isSelf && !roles.contains(AppRole.admin)) {
      throw const BusinessRuleException(
        'You cannot remove your own admin role.',
      );
    }
    if (isSelf && !isActive) {
      throw const BusinessRuleException('You cannot deactivate yourself.');
    }
    final saved = await _users.saveUser(
      User(
        id: userId ?? 0,
        companyId: _companyId,
        fullName: fullName,
        email: email,
        phone: phone.trim().isEmpty ? null : phone.trim(),
        isActive: isActive,
        createdAt: _user?.createdAt,
      ),
      roles.toList(),
    );
    int? targetClientId;
    if (roles.contains(AppRole.client)) {
      targetClientId = clientId;
      if (targetClientId == null) {
        final normalizedEmail = email.trim().toLowerCase();
        final match = clients.where(
          (c) =>
              c.userId == null &&
              (c.email?.trim().toLowerCase() == normalizedEmail),
        );
        if (match.isNotEmpty) {
          targetClientId = match.first.id;
        } else {
          final createdClient = await _clients.saveClient(
            Client(
              id: 0,
              name: fullName.trim(),
              contactPerson: fullName.trim(),
              email: email.trim(),
              phone: phone.trim().isEmpty ? null : phone.trim(),
            ),
          );
          targetClientId = createdClient.id;
          clientId = targetClientId;
        }
      }
    }
    await _clients.linkUser(saved.id, targetClientId);
    if (isSelf) _session.updateUser(saved);
    final wasActive = _user?.isActive;
    await _audit?.record(
      isNew ? 'user_created' : 'user_updated',
      entity: 'user',
      entityId: saved.id,
      details: {
        'name': saved.fullName,
        'roles': roles.map((r) => r.label).join(', '),
        if (wasActive != null && wasActive != saved.isActive)
          'status': saved.isActive ? 'reactivated' : 'deactivated',
      },
    );
    _user = saved;
  });
}

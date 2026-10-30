import 'package:flutter/foundation.dart' show ChangeNotifier;

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

typedef AssignmentDraft = ({int projectId, AppRole role});

/// Create or edit a user with their roles, project assignments and, for
/// client users, the client record their portal login belongs to.
class UserFormViewModel extends ChangeNotifier with ActionRunner {
  UserFormViewModel({
    required this.userId,
    required UserRepository users,
    required ProjectRepository projects,
    required ClientRepository clients,
    required SessionService session,
  }) : _users = users,
       _projects = projects,
       _clients = clients,
       _session = session;

  /// Null when creating a user.
  final int? userId;
  final UserRepository _users;
  final ProjectRepository _projects;
  final ClientRepository _clients;
  final SessionService _session;

  bool _loading = true;
  String? _error;
  User? _user;
  List<Project> _allProjects = const [];
  List<Client> _allClients = const [];

  // Editable state.
  Set<AppRole> roles = {};
  List<AssignmentDraft> assignments = [];
  int? clientId;
  bool isActive = true;

  bool get isLoading => _loading;
  String? get error => _error;
  bool get isNew => userId == null;
  User? get user => _user;
  List<Project> get projects => _allProjects;
  List<Client> get clients => _allClients;
  bool get isSelf => userId != null && userId == _session.user?.id;

  /// Roles that can be assigned to projects, limited to those selected.
  List<AppRole> get assignableRoles => [
    for (final r in const [AppRole.owner, AppRole.siteEngineer, AppRole.client])
      if (roles.contains(r)) r,
  ];

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
    notifyListeners();
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
    if (roles.contains(AppRole.client) && clientId == null) {
      throw const BusinessRuleException(
        'Choose which client this portal login belongs to.',
      );
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
        companyId: _user?.companyId ?? MockData.companyId,
        fullName: fullName,
        email: email,
        phone: phone.trim().isEmpty ? null : phone.trim(),
        isActive: isActive,
        createdAt: _user?.createdAt,
      ),
      roles.toList(),
    );
    await _projects.setUserAssignments(saved.id, assignments);
    await _clients.linkUser(
      saved.id,
      roles.contains(AppRole.client) ? clientId : null,
    );
    if (isSelf) _session.updateUser(saved);
    _user = saved;
  });
}

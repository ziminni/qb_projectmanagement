import 'package:flutter/foundation.dart' show ChangeNotifier;

import '../../../core/utils/action_runner.dart';
import '../../../data/models/app_role.dart';
import '../../../data/models/client.dart';
import '../../../data/models/project.dart';
import '../../../data/models/project_assignment.dart';
import '../../../data/models/user.dart';
import '../../../data/repositories/client_repository.dart';
import '../../../data/repositories/company_repository.dart';
import '../../../data/repositories/project_repository.dart';
import '../../../data/repositories/schedule_repository.dart';
import '../../../data/repositories/user_repository.dart';
import '../../../data/services/progress_calculator.dart';
import '../../../data/services/project_rules.dart';
import '../../../data/services/session_service.dart';

class TeamMember {
  const TeamMember(this.assignment, this.user);

  final ProjectAssignment assignment;
  final User? user;
}

/// The Overview project tab: progress, contract, key dates, status, team.
class ProjectOverviewViewModel extends ChangeNotifier with ActionRunner {
  ProjectOverviewViewModel({
    required this.projectId,
    required SessionService session,
    required ProjectRepository projects,
    required ScheduleRepository schedule,
    required ClientRepository clients,
    required UserRepository users,
    required CompanyRepository company,
  }) : _session = session,
       _projects = projects,
       _schedule = schedule,
       _clients = clients,
       _users = users,
       _company = company;

  final int projectId;
  final SessionService _session;
  final ProjectRepository _projects;
  final ScheduleRepository _schedule;
  final ClientRepository _clients;
  final UserRepository _users;
  final CompanyRepository _company;

  bool _loading = true;
  String? _error;
  Project? _project;
  Client? _client;
  ProjectProgress? _progress;
  List<SCurvePoint> _sCurve = const [];
  List<TeamMember> _team = const [];
  double _behindThreshold = 0.05;
  bool _isAssignedPm = false;

  bool get isLoading => _loading;
  String? get error => _error;
  Project? get project => _project;
  Client? get client => _client;
  ProjectProgress? get progress => _progress;
  List<SCurvePoint> get sCurve => _sCurve;
  List<TeamMember> get team => _team;
  double get behindThreshold => _behindThreshold;
  AppRole get role => _session.activeRole!;

  bool get isBehind =>
      _project?.status == ProjectStatus.ongoing &&
      (_progress?.scheduleVariance ?? 0) > _behindThreshold;

  bool get canEdit => role == AppRole.owner || _isAssignedPm;
  bool get canManageTeam => canEdit;

  List<ProjectStatus> get statusOptions => _project == null
      ? const []
      : ProjectRules.nextStatuses(
          _project!.status,
        ).where((s) => ProjectRules.canChangeStatus(role, s)).toList();

  Future<void> load() async {
    try {
      await _refresh();
      _behindThreshold =
          (await _company.getSettings()).behindScheduleThresholdPct / 100;
      _isAssignedPm =
          role == AppRole.pm &&
          await _projects.isAssigned(projectId, _session.user!.id, AppRole.pm);
    } catch (e) {
      _error = 'Could not load the project. $e';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> _refresh() async {
    _project = await _projects.getProject(projectId);
    if (_project == null) {
      _error = 'Project not found.';
      return;
    }
    _client = await _clients.getClient(_project!.clientId);
    final categories = await _schedule.getCategories(projectId);
    final todos = await _schedule.getTodos(projectId);
    _progress = computeProjectProgress(
      project: _project!,
      categories: categories,
      todos: todos,
    );
    _sCurve = computeSCurve(
      project: _project!,
      categories: categories,
      todos: todos,
    );
    _team =
        [
          for (final a in await _projects.getAssignments(projectId))
            TeamMember(a, await _users.getUser(a.userId)),
        ]..sort(
          (a, b) => a.assignment.roleOnProject.index.compareTo(
            b.assignment.roleOnProject.index,
          ),
        );
  }

  /// Users holding [role] who are not yet on the team in that role.
  Future<List<User>> candidatesFor(AppRole role) async {
    final users = await _users.getUsersWithRole(role);
    return users
        .where(
          (u) => !_team.any(
            (m) => m.user?.id == u.id && m.assignment.roleOnProject == role,
          ),
        )
        .toList();
  }

  Future<String?> changeStatus(ProjectStatus status) => runAction(() async {
    await _projects.changeStatus(
      projectId,
      status,
      userId: _session.user!.id,
      role: role,
    );
    await _refresh();
  });

  Future<String?> addMember(int userId, AppRole role) => runAction(() async {
    await _projects.assign(projectId, userId, role);
    await _refresh();
  });

  Future<String?> removeMember(TeamMember member) => runAction(() async {
    await _projects.unassign(member.assignment.id);
    await _refresh();
  });
}

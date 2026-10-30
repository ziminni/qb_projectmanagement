import '../models/app_role.dart';
import '../models/project.dart';
import '../models/project_assignment.dart';
import '../services/business_rule_exception.dart';
import '../services/notification_service.dart';
import '../services/project_rules.dart';
import 'audit_log_repository.dart';
import 'mock_data.dart';
import 'project_repository.dart';
import 'user_repository.dart';

class MockProjectRepository implements ProjectRepository {
  MockProjectRepository({
    required UserRepository users,
    required AuditLogRepository auditLog,
    NotificationService? notifications,
  }) : _users = users,
       _auditLog = auditLog,
       _notifications = notifications;

  final UserRepository _users;
  final AuditLogRepository _auditLog;
  final NotificationService? _notifications;
  final _projects = [...MockData.projects];
  final _assignments = [...MockData.assignments];

  @override
  Future<Project?> getProject(int id) async {
    for (final p in _projects) {
      if (p.id == id) return p;
    }
    return null;
  }

  @override
  Future<List<Project>> getProjects() async => List.unmodifiable(_projects);

  @override
  Future<List<Project>> getProjectsFor(int userId, AppRole role) async {
    if (const [AppRole.admin, AppRole.accountant].contains(role)) {
      return List.unmodifiable(_projects);
    }
    final ids = {
      for (final a in _assignments)
        if (a.userId == userId && a.roleOnProject == role) a.projectId,
    };
    return _projects.where((p) => ids.contains(p.id)).toList();
  }

  @override
  Future<bool> isAssigned(int projectId, int userId, AppRole role) async =>
      _assignments.any(
        (a) =>
            a.projectId == projectId &&
            a.userId == userId &&
            a.roleOnProject == role,
      );

  @override
  Future<List<ProjectAssignment>> getAssignments(int projectId) async =>
      _assignments.where((a) => a.projectId == projectId).toList();

  @override
  Future<List<ProjectAssignment>> getAssignmentsForUser(int userId) async =>
      _assignments.where((a) => a.userId == userId).toList();

  @override
  Future<void> setUserAssignments(
    int userId,
    List<({int projectId, AppRole role})> assignments,
  ) async {
    final roles = await _users.getRoles(userId);
    for (final a in assignments) {
      if (!roles.contains(a.role)) {
        throw BusinessRuleException(
          'The user does not hold the ${a.role.label} role.',
        );
      }
    }
    _assignments.removeWhere((a) => a.userId == userId);
    var next = _nextAssignmentId;
    for (final a in assignments.toSet()) {
      _assignments.add(
        ProjectAssignment(
          id: next++,
          projectId: a.projectId,
          userId: userId,
          roleOnProject: a.role,
          createdAt: DateTime.now(),
        ),
      );
    }
  }

  @override
  Future<ProjectAssignment> assign(
    int projectId,
    int userId,
    AppRole role,
  ) async {
    if (!(await _users.getRoles(userId)).contains(role)) {
      throw BusinessRuleException(
        'The user does not hold the ${role.label} role.',
      );
    }
    if (await isAssigned(projectId, userId, role)) {
      throw const BusinessRuleException('Already assigned to this project.');
    }
    final created = ProjectAssignment(
      id: _nextAssignmentId,
      projectId: projectId,
      userId: userId,
      roleOnProject: role,
      createdAt: DateTime.now(),
    );
    _assignments.add(created);
    return created;
  }

  @override
  Future<void> unassign(int assignmentId) async =>
      _assignments.removeWhere((a) => a.id == assignmentId);

  int get _nextAssignmentId =>
      _assignments.fold(0, (m, a) => a.id > m ? a.id : m) + 1;

  @override
  Future<Project> saveProject(Project project) async {
    ProjectRules.enforce(
      project.code.trim().isEmpty ? 'Enter the project code.' : null,
    );
    ProjectRules.enforce(
      project.name.trim().isEmpty ? 'Enter the project name.' : null,
    );
    ProjectRules.enforce(
      ProjectRules.validateContractAmount(project.contractAmount),
    );
    ProjectRules.enforce(
      ProjectRules.validateDates(project.startDate, project.targetEndDate),
    );
    ProjectRules.enforce(
      ProjectRules.validatePercent(project.downPaymentPct, 'down payment'),
    );
    ProjectRules.enforce(
      ProjectRules.validatePercent(project.retentionPct, 'retention'),
    );
    final code = project.code.trim().toUpperCase();
    if (_projects.any((p) => p.id != project.id && p.code == code)) {
      throw const BusinessRuleException(
        'Another project already uses this code.',
      );
    }

    final now = DateTime.now();
    if (project.id == 0) {
      final created = _copy(
        project,
        id: _projects.fold(0, (m, p) => p.id > m ? p.id : m) + 1,
        code: code,
        status: ProjectStatus.draft,
        createdAt: now,
      );
      _projects.add(created);
      return created;
    }
    final i = _indexOf(project.id);
    final updated = _copy(
      project,
      code: code,
      status: _projects[i].status,
      createdAt: _projects[i].createdAt,
    );
    _projects[i] = updated;
    return updated;
  }

  @override
  Future<Project> changeStatus(
    int projectId,
    ProjectStatus status, {
    required int userId,
    required AppRole role,
  }) async {
    final i = _indexOf(projectId);
    final current = _projects[i];
    ProjectRules.enforce(
      ProjectRules.validateTransition(current.status, status, role),
    );
    final updated = _copy(
      current,
      status: status,
      actualEndDate: status == ProjectStatus.completed
          ? DateTime.now()
          : current.actualEndDate,
    );
    _projects[i] = updated;
    await _auditLog.record(
      userId: userId,
      action: 'project_status_changed',
      entity: 'project',
      entityId: projectId,
      details: {'from': current.status.apiValue, 'to': status.apiValue},
    );
    await _notifications?.notify(
      [
        for (final a in _assignments)
          if (a.projectId == projectId && a.userId != userId) a.userId,
      ],
      type: 'project_status',
      message: '${current.code} ${current.name} is now ${status.label}.',
    );
    return updated;
  }

  @override
  Future<Project> applyVariation(
    int projectId, {
    required double amountDelta,
    required int daysImpact,
  }) async {
    final i = _indexOf(projectId);
    final p = _projects[i];
    final updated = _copy(
      p,
      contractAmount: p.contractAmount + amountDelta,
      targetEndDate: p.targetEndDate.add(Duration(days: daysImpact)),
    );
    _projects[i] = updated;
    return updated;
  }

  int _indexOf(int id) {
    final i = _projects.indexWhere((p) => p.id == id);
    if (i < 0) throw const BusinessRuleException('Project not found.');
    return i;
  }

  Project _copy(
    Project p, {
    int? id,
    String? code,
    ProjectStatus? status,
    double? contractAmount,
    DateTime? targetEndDate,
    DateTime? actualEndDate,
    DateTime? createdAt,
  }) => Project(
    id: id ?? p.id,
    code: code ?? p.code,
    name: p.name.trim(),
    location: p.location.trim(),
    clientId: p.clientId,
    contractAmount: contractAmount ?? p.contractAmount,
    downPaymentPct: p.downPaymentPct,
    retentionPct: p.retentionPct,
    startDate: p.startDate,
    targetEndDate: targetEndDate ?? p.targetEndDate,
    actualEndDate: actualEndDate ?? p.actualEndDate,
    status: status ?? p.status,
    createdAt: createdAt ?? p.createdAt,
    updatedAt: DateTime.now(),
  );
}

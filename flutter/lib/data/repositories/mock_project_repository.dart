import '../models/app_role.dart';
import '../models/project.dart';
import '../models/project_assignment.dart';
import '../services/business_rule_exception.dart';
import '../services/notification_service.dart';
import '../services/project_rules.dart';
import '../../core/layout/project_tabs.dart';
import '../../routes/routes.dart';
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
        if (a.userId == userId && a.roleOnProject == role && a.isActive)
          a.projectId,
    };
    return _projects.where((p) => ids.contains(p.id)).toList();
  }

  @override
  Future<bool> isAssigned(int projectId, int userId, AppRole role) async =>
      _assignments.any(
        (a) =>
            a.projectId == projectId &&
            a.userId == userId &&
            a.roleOnProject == role &&
            a.isActive,
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
    final previous = [..._assignments.where((a) => a.userId == userId)];
    _assignments.removeWhere((a) => a.userId == userId);
    var next = _nextAssignmentId;
    for (final a in assignments.toSet()) {
      final kept = previous
          .where((p) => p.projectId == a.projectId && p.roleOnProject == a.role)
          .firstOrNull;
      if (kept != null) {
        _assignments.add(kept);
        continue;
      }
      final created = ProjectAssignment(
        id: next++,
        projectId: a.projectId,
        userId: userId,
        roleOnProject: a.role,
        response: await _firstResponse(a.projectId, a.role),
        createdAt: DateTime.now(),
      );
      _assignments.add(created);
      await _sendRequest(created);
    }
  }

  static bool _needsAcceptance(AppRole role) =>
      role == AppRole.siteEngineer || role == AppRole.client;

  /// Clients get the request at once; a site engineer's waits until the
  /// client has accepted.
  Future<RequestResponse> _firstResponse(int projectId, AppRole role) async {
    if (!_needsAcceptance(role)) return RequestResponse.accepted;
    final status = (await getProject(projectId))?.status;
    final clientDeciding =
        status == ProjectStatus.requested ||
        status == ProjectStatus.changesRequested;
    return role == AppRole.siteEngineer && clientDeciding
        ? RequestResponse.notSent
        : RequestResponse.pending;
  }

  Future<void> _sendRequest(ProjectAssignment a) async {
    if (a.response != RequestResponse.pending) return;
    final p = await getProject(a.projectId);
    if (p == null) return;
    await _notifications?.notify(
      [a.userId],
      type: 'project_request',
      message: a.roleOnProject == AppRole.client
          ? 'New project request: ${p.code} ${p.name}. Accept it, ask for '
                'changes or decline it.'
          : 'New project request: ${p.code} ${p.name}. Accept or decline it.',
      link: a.roleOnProject == AppRole.client
          ? AppRoutes.clientProjects
          : AppRoutes.projects,
    );
  }

  Future<void> _notifyOwners(
    int projectId,
    String message, {
    String? link,
  }) async => _notifications?.notify(
    [
      for (final a in _assignments)
        if (a.projectId == projectId &&
            a.roleOnProject == AppRole.owner &&
            a.isActive)
          a.userId,
    ],
    type: 'project_request',
    message: message,
    link: link ?? AppRoutes.projectTab(projectId, ProjectTab.overview),
  );

  @override
  Future<List<ProjectRequest>> getRequestsFor(int userId, AppRole role) async =>
      [
        for (final a in _assignments)
          if (a.userId == userId &&
              a.roleOnProject == role &&
              a.response == RequestResponse.pending)
            ProjectRequest(_projects[_indexOf(a.projectId)], a),
      ];

  @override
  Future<ProjectAssignment> respondToRequest(
    int assignmentId, {
    required int userId,
    required RequestResponse answer,
    String? note,
  }) async {
    final i = _assignments.indexWhere((a) => a.id == assignmentId);
    if (i < 0) throw const BusinessRuleException('Request not found.');
    final a = _assignments[i];
    if (a.userId != userId) {
      throw const BusinessRuleException('This request is not yours.');
    }
    if (a.response != RequestResponse.pending) {
      throw const BusinessRuleException('You already answered this request.');
    }
    final isClient = a.roleOnProject == AppRole.client;
    switch (answer) {
      case RequestResponse.accepted:
        break;
      case RequestResponse.declined:
        ProjectRules.enforce(ProjectRules.validateNote(note));
      case RequestResponse.changesRequested:
        if (!isClient) {
          throw const BusinessRuleException(
            'Only the client can ask for changes.',
          );
        }
        ProjectRules.enforce(ProjectRules.validateNote(note));
      case RequestResponse.pending || RequestResponse.notSent:
        throw const BusinessRuleException(
          'Accept, decline or ask for changes.',
        );
    }
    final trimmed = answer == RequestResponse.accepted ? null : note!.trim();
    final updated = a.copyWith(
      response: answer,
      note: () => trimmed,
      respondedAt: () => DateTime.now(),
    );
    _assignments[i] = updated;
    final pi = _indexOf(a.projectId);
    final project = _projects[pi];
    final who = (await _users.getUser(userId))?.fullName ?? 'Someone';
    await _auditLog.record(
      userId: userId,
      action: 'project_request_${answer.apiValue}',
      entity: 'project',
      entityId: project.id,
      details: {'role': a.roleOnProject.apiValue, 'note': ?trimmed},
    );

    if (isClient) {
      switch (answer) {
        case RequestResponse.declined:
          // Declining deletes the project; the owner keeps the reason in
          // the notification.
          await _notifyOwners(
            project.id,
            '$who declined ${project.code} ${project.name}, so it was '
            'deleted. Reason: $trimmed',
            link: AppRoutes.projects,
          );
          _projects.removeAt(pi);
          _assignments.removeWhere((x) => x.projectId == project.id);
        case RequestResponse.changesRequested:
          _projects[pi] = _copy(
            project,
            status: ProjectStatus.changesRequested,
          );
          await _notifyOwners(
            project.id,
            '$who asked for changes on ${project.code}: $trimmed',
          );
        default:
          _projects[pi] = _copy(
            project,
            status: ProjectStatus.siteEngineerPending,
          );
          await _notifyOwners(
            project.id,
            '$who accepted ${project.code}. The site engineer has been '
            'sent the request.',
          );
          for (var j = 0; j < _assignments.length; j++) {
            final x = _assignments[j];
            if (x.projectId == project.id &&
                x.response == RequestResponse.notSent) {
              _assignments[j] = x.copyWith(response: RequestResponse.pending);
              await _sendRequest(_assignments[j]);
            }
          }
          await _acceptIfReady(pi);
      }
      return updated;
    }

    if (answer == RequestResponse.declined) {
      await _notifyOwners(
        project.id,
        '$who declined ${project.code}: $trimmed Choose another site engineer.',
      );
      return updated;
    }
    await _notifyOwners(project.id, '$who accepted ${project.code}.');
    await _acceptIfReady(pi);
    return updated;
  }

  /// Moves a project waiting for its site engineer to Accepted once one has
  /// joined and nobody is still deciding.
  Future<void> _acceptIfReady(int pi) async {
    final project = _projects[pi];
    if (project.status != ProjectStatus.siteEngineerPending) return;
    final team = _assignments.where(
      (a) => a.projectId == project.id && _needsAcceptance(a.roleOnProject),
    );
    final ready =
        team.any(
          (a) => a.roleOnProject == AppRole.siteEngineer && a.isActive,
        ) &&
        !team.any((a) => a.response == RequestResponse.pending);
    if (!ready) return;
    _projects[pi] = _copy(project, status: ProjectStatus.accepted);
    await _notifyOwners(
      project.id,
      '${project.code} is accepted by the client and the site engineer. '
      'Start it when work begins.',
    );
  }

  @override
  Future<Project> resendRequest(int projectId, {required int userId}) async {
    final pi = _indexOf(projectId);
    final project = _projects[pi];
    if (project.status != ProjectStatus.changesRequested) {
      throw const BusinessRuleException(
        'Only a project the client asked to change is sent again.',
      );
    }
    if (!await isAssigned(projectId, userId, AppRole.owner)) {
      throw const BusinessRuleException(
        'Only the owner running this project can send it again.',
      );
    }
    _projects[pi] = _copy(project, status: ProjectStatus.requested);
    for (var i = 0; i < _assignments.length; i++) {
      final a = _assignments[i];
      if (a.projectId == projectId &&
          a.roleOnProject == AppRole.client &&
          a.response == RequestResponse.changesRequested) {
        _assignments[i] = a.copyWith(
          response: RequestResponse.pending,
          respondedAt: () => null,
        );
        await _sendRequest(_assignments[i]);
      }
    }
    await _auditLog.record(
      userId: userId,
      action: 'project_request_resent',
      entity: 'project',
      entityId: projectId,
    );
    return _projects[pi];
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
    // A declined request can be sent again; a live one cannot be doubled.
    _assignments.removeWhere(
      (a) =>
          a.projectId == projectId &&
          a.userId == userId &&
          a.roleOnProject == role &&
          a.response == RequestResponse.declined,
    );
    if (_assignments.any(
      (a) =>
          a.projectId == projectId &&
          a.userId == userId &&
          a.roleOnProject == role,
    )) {
      throw const BusinessRuleException('Already on this project.');
    }
    final created = ProjectAssignment(
      id: _nextAssignmentId,
      projectId: projectId,
      userId: userId,
      roleOnProject: role,
      response: await _firstResponse(projectId, role),
      createdAt: DateTime.now(),
    );
    _assignments.add(created);
    await _sendRequest(created);
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
        status: ProjectStatus.requested,
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
          if (a.projectId == projectId && a.userId != userId && a.isActive)
            a.userId,
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
    latitude: p.latitude,
    longitude: p.longitude,
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

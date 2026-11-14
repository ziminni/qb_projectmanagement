import '../../core/network/api_client.dart';
import '../models/app_role.dart';
import '../models/json_utils.dart';
import '../models/project.dart';
import '../models/project_assignment.dart';
import 'project_repository.dart';

/// Projects, their team and their requests, against the CPMS backend.
///
/// Scope and redaction are the server's: the active role (sent as
/// `X-Active-Role`) decides which projects and which peso keys come back, so
/// the `userId`s in the interface are never sent as a claim — the server
/// always answers for the caller. Rule refusals arrive as the server's own
/// `detail` text and surface as `BusinessRuleException` unchanged.
class HttpProjectRepository implements ProjectRepository {
  HttpProjectRepository(this._client);

  final ApiClient _client;

  @override
  Future<List<Project>> getProjects() async => [
    for (final row in await _client.getRows('projects/')) Project.fromJson(row),
  ];

  /// The server scopes by caller and active role and ignores these ids
  /// (contract: Project scoping).
  @override
  Future<List<Project>> getProjectsFor(int userId, AppRole role) =>
      getProjects();

  @override
  Future<Project?> getProject(int id) async {
    final data = await _client.get('projects/$id/', notFoundAsNull: true);
    return data == null ? null : Project.fromJson(jsonObject(data));
  }

  @override
  Future<bool> isAssigned(int projectId, int userId, AppRole role) async {
    final rows = await _client.getRows(
      'project-assignments/',
      query: {
        'user': userId,
        'role_on_project': role.apiValue,
        'response': RequestResponse.accepted.apiValue,
      },
    );
    return rows.any((row) => row['project_id'] == projectId);
  }

  @override
  Future<List<ProjectAssignment>> getAssignments(int projectId) async => [
    for (final row in await _client.getRows('projects/$projectId/assignments/'))
      ProjectAssignment.fromJson(row),
  ];

  @override
  Future<List<ProjectAssignment>> getAssignmentsForUser(int userId) async => [
    for (final row in await _client.getRows(
      'project-assignments/',
      query: {'user': userId},
    ))
      ProjectAssignment.fromJson(row),
  ];

  @override
  Future<void> setUserAssignments(
    int userId,
    List<({int projectId, AppRole role})> assignments,
  ) async {
    await _client.put(
      'users/$userId/assignments/',
      body: {
        'assignments': [
          for (final a in assignments)
            {'project_id': a.projectId, 'role': a.role.apiValue},
        ],
      },
    );
  }

  @override
  Future<ProjectAssignment> assign(
    int projectId,
    int userId,
    AppRole role,
  ) async => ProjectAssignment.fromJson(
    jsonObject(
      await _client.post(
        'projects/$projectId/assignments/',
        body: {'user_id': userId, 'role_on_project': role.apiValue},
      ),
    ),
  );

  @override
  Future<List<ProjectRequest>> getRequestsFor(int userId, AppRole role) async =>
      [
        for (final row in await _client.getRows('project-requests/'))
          ProjectRequest(
            Project.fromJson(jsonObject(row['project'])),
            ProjectAssignment.fromJson(jsonObject(row['assignment'])),
          ),
      ];

  @override
  Future<ProjectAssignment> respondToRequest(
    int assignmentId, {
    required int userId,
    required RequestResponse answer,
    String? note,
  }) async => ProjectAssignment.fromJson(
    jsonObject(
      await _client.post(
        'project-assignments/$assignmentId/respond/',
        body: {
          'response': answer.apiValue,
          'note': answer == RequestResponse.accepted ? null : note?.trim(),
        },
      ),
    ),
  );

  @override
  Future<Project> resendRequest(int projectId, {required int userId}) async =>
      Project.fromJson(
        jsonObject(await _client.post('projects/$projectId/resend/')),
      );

  @override
  Future<void> unassign(int assignmentId) =>
      _client.delete('project-assignments/$assignmentId/');

  /// `POST projects/` creates the caller's owner assignment itself (decision
  /// 06, ruling 6), sets the status to `requested` and refuses on the same
  /// rules the mock checked, so only the editable fields are sent.
  @override
  Future<Project> saveProject(Project project) async {
    final body = {
      'code': project.code.trim(),
      'name': project.name.trim(),
      'location': project.location.trim(),
      'latitude': project.latitude,
      'longitude': project.longitude,
      'client_id': project.clientId,
      'contract_amount': project.contractAmount,
      'down_payment_pct': project.downPaymentPct,
      'retention_pct': project.retentionPct,
      'start_date': JsonUtils.fromDate(project.startDate),
      'target_end_date': JsonUtils.fromDate(project.targetEndDate),
    };
    final data = await (project.id == 0
        ? _client.post('projects/', body: body)
        : _client.patch('projects/${project.id}/', body: body));
    return Project.fromJson(jsonObject(data));
  }

  @override
  Future<Project> changeStatus(
    int projectId,
    ProjectStatus status, {
    required int userId,
    required AppRole role,
  }) async => Project.fromJson(
    jsonObject(
      await _client.post(
        'projects/$projectId/status/',
        body: {'status': status.toJson()},
      ),
    ),
  );

  /// No public route: an approved variation order adjusts the contract amount
  /// and target end on the server (Phase 4, `applyVariation` is called from
  /// the billing repository there).
  @override
  Future<Project> applyVariation(
    int projectId, {
    required double amountDelta,
    required int daysImpact,
  }) async => throw UnsupportedError(
    'A variation order is applied by the server when it is approved.',
  );
}

import '../../core/layout/project_tabs.dart';
import '../../routes/routes.dart';
import '../models/app_role.dart';
import '../models/project_worker_request.dart';
import '../repositories/labor_repository.dart';
import '../repositories/project_repository.dart';
import 'approval_inbox.dart';

/// Pending foreman requests to add laborers to a project, waiting for the PM.
class LaborerRequestApprovalSource implements ApprovalSource {
  LaborerRequestApprovalSource({
    required ProjectRepository projects,
    required LaborRepository labor,
  }) : _projects = projects,
       _labor = labor;

  final ProjectRepository _projects;
  final LaborRepository _labor;

  @override
  Future<List<ApprovalItem>> pendingFor(int userId, AppRole role) async {
    if (role != AppRole.owner) return const [];
    final projects = await _projects.getProjectsFor(userId, role);
    if (projects.isEmpty) return const [];
    final byId = {for (final p in projects) p.id: p};
    final List<ProjectWorkerRequest> requests;
    try {
      requests = await _labor.getWorkerRequests(
        projectIds: byId.keys.toList(),
        status: ProjectWorkerRequestStatus.pending,
      );
    } catch (_) {
      return const [];
    }
    return [
      for (final r in requests)
        ApprovalItem(
          kind: ApprovalKind.laborerRequest,
          title: '${r.fullName} · ${byId[r.projectId]?.code ?? 'Project'}',
          subtitle: [
            if (r.requestedByName != null) 'Requested by ${r.requestedByName}',
            if (r.phone.isNotEmpty) r.phone,
            if (r.address.isNotEmpty) r.address,
          ].join(' · '),
          route: AppRoutes.projectTab(r.projectId, ProjectTab.laborers),
          date: r.createdAt,
        ),
    ];
  }
}

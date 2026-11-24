import '../../core/layout/project_tabs.dart';
import '../../routes/routes.dart';
import '../models/app_role.dart';
import '../models/project_worker_request.dart';
import '../repositories/labor_repository.dart';
import '../repositories/project_repository.dart';
import 'approval_inbox.dart';

/// Pending foreman requests to add laborers to a project, waiting for the PM.
///
/// Multiple pending laborer requests on the same project are grouped into a
/// single bulk [ApprovalItem] so bulk crew requests never flood the Approvals
/// page or push other project approvals to the bottom.
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
    if (requests.isEmpty) return const [];

    final byProject = <int, List<ProjectWorkerRequest>>{};
    for (final r in requests) {
      byProject.putIfAbsent(r.projectId, () => []).add(r);
    }

    final items = <ApprovalItem>[];
    for (final entry in byProject.entries) {
      final projectId = entry.key;
      final group = entry.value;
      final project = byId[projectId];
      final code = project?.code ?? 'Project';
      final name = project?.name;

      if (group.length == 1) {
        final r = group.first;
        items.add(
          ApprovalItem(
            kind: ApprovalKind.laborerRequest,
            title: '${r.fullName} · $code',
            subtitle: [
              if (r.requestedByName != null)
                'Requested by ${r.requestedByName}',
              if (r.phone.isNotEmpty) r.phone,
              if (r.address.isNotEmpty) r.address,
            ].join(' · '),
            route: AppRoutes.projectTab(projectId, ProjectTab.laborers),
            entityId: r.id,
            entityIds: [r.id],
            projectId: projectId,
            projectCode: project?.code,
            projectName: name,
            requesterName: r.requestedByName,
            badgeText: r.workerId != null ? 'Existing crew' : 'New laborer',
            date: r.createdAt,
          ),
        );
        continue;
      }

      // Bulk crew request for this project
      final previewNames = group.take(3).map((r) => r.fullName).join(', ');
      final remaining = group.length - 3;
      final namesSummary = remaining > 0
          ? '$previewNames +$remaining more'
          : previewNames;
      final requesters = {
        for (final r in group)
          if (r.requestedByName != null && r.requestedByName!.trim().isNotEmpty)
            r.requestedByName!.trim(),
      };
      final latestDate = group
          .map((r) => r.createdAt)
          .whereType<DateTime>()
          .fold<DateTime?>(
            null,
            (latest, d) => latest == null || d.isAfter(latest) ? d : latest,
          );

      items.add(
        ApprovalItem(
          kind: ApprovalKind.laborerRequest,
          title: '${group.length} laborers requested · $code',
          subtitle: [
            if (requesters.isNotEmpty) 'Requested by ${requesters.join(', ')}',
            namesSummary,
          ].join(' · '),
          route: AppRoutes.projectTab(projectId, ProjectTab.laborers),
          entityId: group.first.id,
          entityIds: [for (final r in group) r.id],
          projectId: projectId,
          projectCode: project?.code,
          projectName: name,
          requesterName: requesters.isEmpty ? null : requesters.first,
          badgeText: '${group.length} laborers',
          date: latestDate,
        ),
      );
    }

    return items;
  }
}

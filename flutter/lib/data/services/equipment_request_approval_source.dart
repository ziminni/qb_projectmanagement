import '../../core/layout/project_tabs.dart';
import '../../routes/routes.dart';
import '../models/app_role.dart';
import '../models/equipment_borrow.dart';
import '../repositories/equipment_repository.dart';
import '../repositories/project_repository.dart';
import 'approval_inbox.dart';

/// Pending foreman requests to borrow Queen Builders equipment or rent
/// external equipment on a project, grouped per project so bulk equipment
/// requests stay compact in the Approvals page.
class EquipmentRequestApprovalSource implements ApprovalSource {
  EquipmentRequestApprovalSource({
    required ProjectRepository projects,
    required EquipmentRepository equipment,
  }) : _projects = projects,
       _equipment = equipment;

  final ProjectRepository _projects;
  final EquipmentRepository _equipment;

  @override
  Future<List<ApprovalItem>> pendingFor(int userId, AppRole role) async {
    if (role != AppRole.owner) return const [];
    final projects = await _projects.getProjectsFor(userId, role);
    if (projects.isEmpty) return const [];
    final byId = {for (final p in projects) p.id: p};
    final List<EquipmentBorrow> requests;
    try {
      requests = await _equipment.getBorrows(
        projectIds: byId.keys.toList(),
        status: EquipmentBorrowStatus.pending,
      );
    } catch (_) {
      return const [];
    }
    if (requests.isEmpty) return const [];

    final byProject = <int, List<EquipmentBorrow>>{};
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
            kind: ApprovalKind.equipmentRequest,
            title: '${r.equipmentName} × ${r.quantity} · $code',
            subtitle: [
              if (r.hasBorrower) 'Borrower: ${r.borrowerName}',
              if (r.requestedByName != null)
                'Requested by ${r.requestedByName}',
            ].join(' · '),
            route: AppRoutes.projectTab(projectId, ProjectTab.equipment),
            entityId: r.id,
            entityIds: [r.id],
            projectId: projectId,
            projectCode: project?.code,
            projectName: name,
            requesterName: r.requestedByName,
            badgeText: r.source == EquipmentBorrowSource.owned
                ? 'QB owned'
                : 'External rental',
            date: r.createdAt ?? r.neededDate,
          ),
        );
        continue;
      }

      final preview = group
          .take(3)
          .map((r) => '${r.equipmentName} ×${r.quantity}')
          .join(', ');
      final extra = group.length - 3;
      final summary = extra > 0 ? '$preview +$extra more' : preview;

      items.add(
        ApprovalItem(
          kind: ApprovalKind.equipmentRequest,
          title: '${group.length} equipment requests · $code',
          subtitle: summary,
          route: AppRoutes.projectTab(projectId, ProjectTab.equipment),
          entityId: group.first.id,
          entityIds: [for (final r in group) r.id],
          projectId: projectId,
          projectCode: project?.code,
          projectName: name,
          badgeText: '${group.length} items',
          date: group.first.createdAt ?? group.first.neededDate,
        ),
      );
    }
    return items;
  }
}

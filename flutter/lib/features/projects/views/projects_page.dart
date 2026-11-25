import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_radii.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/layout/project_tabs.dart';
import '../../../core/utils/app_messages.dart';
import '../../../core/utils/page_padding.dart';
import '../../../data/models/project.dart';
import '../../../data/models/project_assignment.dart';
import '../../../routes/routes.dart';
import '../../../shared/widgets/app_empty_state.dart';
import '../../../shared/widgets/app_project_request_card.dart';
import '../../../shared/widgets/app_reason_dialog.dart';
import '../../dashboard/widgets/dashboard_stat_tile.dart';
import '../viewmodels/projects_viewmodel.dart';
import '../widgets/projects_project_card.dart';
import '../widgets/projects_site_actions.dart';

/// Projects list: portfolio KPIs + unified filter/action bar for Project
/// Managers, and "My sites" (with shortcuts) for site engineers.
class ProjectsPage extends StatelessWidget {
  const ProjectsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => ProjectsViewModel(
        session: getIt(),
        projects: getIt(),
        schedule: getIt(),
        company: getIt(),
      )..load(),
      builder: (context, _) {
        final vm = context.watch<ProjectsViewModel>();
        if (vm.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        if (vm.error != null) return AppEmptyState(message: vm.error!);
        final items = vm.items;

        return RefreshIndicator(
          onRefresh: vm.load,
          child: ListView(
            padding: pagePadding(context),
            children: [
              if (!vm.isSiteEngineer && vm.allItems.isNotEmpty) ...[
                _ProjectsKpiStrip(vm: vm),
                const SizedBox(height: AppSpacing.lg),
              ],
              for (final r in vm.requests) ...[
                AppProjectRequestCard(
                  project: r.project,
                  showAmount: false,
                  busy: vm.isBusy,
                  onAccept: () => reportAction(
                    context,
                    vm.respond(r, answer: RequestResponse.accepted),
                    success: 'Request accepted.',
                  ),
                  onDecline: () => _decline(
                    context,
                    (reason) => vm.respond(
                      r,
                      answer: RequestResponse.declined,
                      note: reason,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
              ],
              _ProjectsControlBar(vm: vm, visibleCount: items.length),
              const SizedBox(height: AppSpacing.lg),
              if (items.isEmpty)
                AppEmptyState(
                  icon: Icons.apartment_rounded,
                  message: vm.isSiteEngineer
                      ? 'No sites are assigned to you yet.'
                      : 'No projects match.',
                )
              else
                LayoutBuilder(
                  builder: (context, constraints) {
                    final columns = constraints.maxWidth >= 860 ? 2 : 1;
                    final width =
                        (constraints.maxWidth - AppSpacing.lg * (columns - 1)) /
                        columns;
                    return Wrap(
                      spacing: AppSpacing.lg,
                      runSpacing: AppSpacing.lg,
                      children: [
                        for (final s in items)
                          SizedBox(
                            width: width,
                            child: ProjectsProjectCard(
                              project: s.project,
                              progress: s.progress,
                              isBehind: s.isBehind,
                              onTap: () => context.go(
                                AppRoutes.projectTab(
                                  s.project.id,
                                  ProjectTab.overview,
                                ),
                              ),
                              actions:
                                  vm.isSiteEngineer &&
                                      s.project.status == ProjectStatus.ongoing
                                  ? ProjectsSiteActions(projectId: s.project.id)
                                  : null,
                            ),
                          ),
                      ],
                    );
                  },
                ),
            ],
          ),
        );
      },
    );
  }
}

class _ProjectsKpiStrip extends StatelessWidget {
  const _ProjectsKpiStrip({required this.vm});

  final ProjectsViewModel vm;

  @override
  Widget build(BuildContext context) {
    final all = vm.allItems;
    final ongoingCount = all
        .where((s) => s.project.status == ProjectStatus.ongoing)
        .length;
    final pendingCount = all
        .where(
          (s) =>
              s.project.status == ProjectStatus.requested ||
              s.project.status == ProjectStatus.changesRequested ||
              s.project.status == ProjectStatus.siteEngineerPending ||
              s.project.status == ProjectStatus.accepted,
        )
        .length;
    final behindCount = all.where((s) => s.isBehind).length;

    final tiles = [
      DashboardStatTile(
        label: 'Total projects',
        value: '${all.length}',
        detail: '$ongoingCount active on site',
        icon: Icons.apartment_rounded,
        onTap: () => vm.setStatus(null),
      ),
      DashboardStatTile(
        label: 'Ongoing',
        value: '$ongoingCount',
        detail: ongoingCount == 0
            ? 'No active construction'
            : 'Construction in progress',
        icon: Icons.construction_rounded,
        color: AppColors.brandGold,
        onTap: () => vm.setStatus(
          vm.statusFilter == ProjectStatus.ongoing
              ? null
              : ProjectStatus.ongoing,
        ),
      ),
      DashboardStatTile(
        label: 'Pre-construction',
        value: '$pendingCount',
        detail: pendingCount == 0
            ? 'None awaiting start'
            : 'Awaiting acceptance or start',
        icon: Icons.pending_actions_rounded,
      ),
      DashboardStatTile(
        label: 'Schedule status',
        value: behindCount == 0 ? 'On track' : '$behindCount behind',
        detail: behindCount == 0
            ? 'All active sites within plan'
            : 'Past schedule threshold',
        icon: behindCount == 0
            ? Icons.verified_outlined
            : Icons.warning_amber_rounded,
        color: behindCount == 0 ? AppColors.success : AppColors.warning,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = constraints.maxWidth >= 980
            ? 4
            : constraints.maxWidth >= 560
            ? 2
            : 1;
        final w = (constraints.maxWidth - AppSpacing.md * (cols - 1)) / cols;
        return Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.md,
          children: [
            for (final t in tiles) SizedBox(width: w, child: t),
          ],
        );
      },
    );
  }
}

class _ProjectsControlBar extends StatelessWidget {
  const _ProjectsControlBar({
    required this.vm,
    required this.visibleCount,
  });

  final ProjectsViewModel vm;
  final int visibleCount;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final searchField = TextField(
      decoration: const InputDecoration(
        isDense: true,
        prefixIcon: Icon(Icons.search, size: 20),
        hintText: 'Search name, code or location',
      ),
      onChanged: vm.setQuery,
    );

    final statusPicker = DropdownButtonFormField<ProjectStatus?>(
      key: ValueKey('projects-status-${vm.statusFilter}'),
      initialValue: vm.statusFilter,
      isExpanded: true,
      decoration: const InputDecoration(
        isDense: true,
        labelText: 'Status',
        prefixIcon: Icon(Icons.filter_list_rounded, size: 18),
      ),
      items: [
        const DropdownMenuItem(
          value: null,
          child: Text('All statuses'),
        ),
        for (final s in ProjectStatus.values)
          DropdownMenuItem(value: s, child: Text(s.label)),
      ],
      onChanged: vm.setStatus,
    );

    final countBadge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? cs.surfaceContainer : AppColors.surfaceSunken,
        borderRadius: AppRadii.mdAll,
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Text(
        '$visibleCount project${visibleCount == 1 ? '' : 's'}',
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          color: cs.onSurfaceVariant,
        ),
      ),
    );

    final newButton = vm.canCreate
        ? FilledButton.icon(
            onPressed: () => context.go(AppRoutes.projectNew),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('New project'),
          )
        : null;

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 760) {
          return Row(
            children: [
              Expanded(child: searchField),
              const SizedBox(width: AppSpacing.md),
              SizedBox(width: 215, child: statusPicker),
              const SizedBox(width: AppSpacing.sm),
              countBadge,
              if (newButton != null) ...[
                const SizedBox(width: AppSpacing.md),
                newButton,
              ],
            ],
          );
        }
        return Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(width: constraints.maxWidth, child: searchField),
            SizedBox(
              width: (constraints.maxWidth - AppSpacing.sm).clamp(180, 260),
              child: statusPicker,
            ),
            countBadge,
            ?newButton,
          ],
        );
      },
    );
  }
}

Future<void> _decline(
  BuildContext context,
  Future<String?> Function(String reason) respond,
) async {
  final reason = await AppReasonDialog.show(
    context,
    title: 'Decline project request',
    confirmLabel: 'Decline',
    label: 'Reason for declining',
    message: 'The owner sees your reason and picks another site engineer.',
  );
  if (reason != null && context.mounted) {
    await reportAction(context, respond(reason), success: 'Request declined.');
  }
}

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/layout/project_tabs.dart';
import '../../../core/utils/app_messages.dart';
import '../../../core/utils/page_padding.dart';
import '../../../data/models/project.dart';
import '../../../data/models/project_assignment.dart';
import '../../../routes/routes.dart';
import '../../../shared/widgets/app_empty_state.dart';
import '../../../shared/widgets/app_page_header.dart';
import '../../../shared/widgets/app_project_request_card.dart';
import '../../../shared/widgets/app_reason_dialog.dart';
import '../viewmodels/projects_viewmodel.dart';
import '../widgets/projects_project_card.dart';
import '../widgets/projects_site_actions.dart';

/// Projects list: "Projects" for the owner, "My projects" for PMs and
/// "My sites" (with shortcuts) for site engineers.
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
            padding: pagePadding(context).copyWith(top: AppSpacing.xl),
            children: [
              AppPageHeader(
                title: vm.isSiteEngineer ? 'My sites' : 'My projects',
                subtitle:
                    '${items.length} project${items.length == 1 ? '' : 's'}'
                    '${vm.statusFilter == null ? '' : ' · ${vm.statusFilter!.label}'}',
                actions: [
                  if (vm.canCreate)
                    FilledButton.icon(
                      onPressed: () => context.go(AppRoutes.projectNew),
                      icon: const Icon(Icons.add),
                      label: const Text('New project'),
                    ),
                ],
              ),
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
              Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.md,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 340,
                    child: TextField(
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        hintText: 'Search name, code or location',
                      ),
                      onChanged: vm.setQuery,
                    ),
                  ),
                  SizedBox(
                    width: 240,
                    child: DropdownButtonFormField<ProjectStatus?>(
                      initialValue: vm.statusFilter,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Status',
                        prefixIcon: Icon(Icons.filter_list_rounded),
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
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xl),
              if (items.isEmpty)
                AppEmptyState(
                  icon: Icons.apartment_rounded,
                  message: vm.isSiteEngineer
                      ? 'No sites are assigned to you yet.'
                      : 'No projects match.',
                ),
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

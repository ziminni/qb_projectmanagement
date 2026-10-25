import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/layout/project_tabs.dart';
import '../../../core/utils/page_padding.dart';
import '../../../data/models/project.dart';
import '../../../routes/routes.dart';
import '../../../shared/widgets/app_empty_state.dart';
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
            padding: pagePadding(context),
            children: [
              Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.md,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 300,
                    child: TextField(
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        hintText: 'Search name, code or location',
                      ),
                      onChanged: vm.setQuery,
                    ),
                  ),
                  SizedBox(
                    width: 200,
                    child: DropdownButtonFormField<ProjectStatus?>(
                      initialValue: vm.statusFilter,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Status'),
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
                  if (vm.canCreate)
                    FilledButton.icon(
                      onPressed: () => context.go(AppRoutes.projectNew),
                      icon: const Icon(Icons.add),
                      label: const Text('New project'),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              if (items.isEmpty)
                AppEmptyState(
                  message: vm.isSiteEngineer
                      ? 'No sites are assigned to you yet.'
                      : 'No projects match.',
                ),
              for (final s in items) ...[
                ProjectsProjectCard(
                  project: s.project,
                  progress: s.progress,
                  isBehind: s.isBehind,
                  onTap: () => context.go(
                    AppRoutes.projectTab(s.project.id, ProjectTab.overview),
                  ),
                  actions:
                      vm.isSiteEngineer &&
                          s.project.status == ProjectStatus.ongoing
                      ? ProjectsSiteActions(projectId: s.project.id)
                      : null,
                ),
                const SizedBox(height: AppSpacing.md),
              ],
            ],
          ),
        );
      },
    );
  }
}

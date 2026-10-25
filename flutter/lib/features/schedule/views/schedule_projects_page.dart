import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/layout/project_tabs.dart';
import '../../../core/utils/page_padding.dart';
import '../../../routes/routes.dart';
import '../viewmodels/schedule_projects_viewmodel.dart';
import '../widgets/schedule_project_card.dart';

/// Projects the active role can open in the schedule. Entry point for the
/// PM and owner schedule, the site engineer's to-do checklist and the
/// client's progress view.
class ScheduleProjectsPage extends StatelessWidget {
  const ScheduleProjectsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => ScheduleProjectsViewModel(
        session: getIt(),
        projects: getIt(),
        schedule: getIt(),
      )..load(),
      builder: (context, _) {
        final vm = context.watch<ScheduleProjectsViewModel>();
        if (vm.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        if (vm.error != null) {
          return Center(child: Text(vm.error!));
        }
        if (vm.items.isEmpty) {
          return Center(
            child: Text(
              'No projects are assigned to you yet.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: vm.load,
          child: ListView.separated(
            padding: pagePadding(context),
            itemCount: vm.items.length,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
            itemBuilder: (context, i) {
              final item = vm.items[i];
              return ScheduleProjectCard(
                project: item.project,
                progress: item.progress,
                onTap: () => context.go(
                  AppRoutes.projectTab(item.project.id, ProjectTab.schedule),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

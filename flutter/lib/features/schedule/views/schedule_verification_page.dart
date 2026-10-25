import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/layout/project_tabs.dart';
import '../../../data/models/project.dart';
import '../../../routes/routes.dart';
import '../viewmodels/schedule_verification_viewmodel.dart';
import '../widgets/schedule_verification_tile.dart';

/// PM queue of to-dos marked done on site and awaiting verification.
class ScheduleVerificationPage extends StatelessWidget {
  const ScheduleVerificationPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => ScheduleVerificationViewModel(
        session: getIt(),
        projects: getIt(),
        schedule: getIt(),
        users: getIt(),
      )..load(),
      builder: (context, _) {
        final vm = context.watch<ScheduleVerificationViewModel>();
        final textTheme = Theme.of(context).textTheme;
        if (vm.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        if (vm.error != null) {
          return Center(child: Text(vm.error!));
        }
        if (vm.pending.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.task_alt, size: 48),
                const SizedBox(height: AppSpacing.md),
                Text('Nothing to verify.', style: textTheme.titleMedium),
              ],
            ),
          );
        }

        final byProject = <Project, List<PendingTodo>>{};
        for (final p in vm.pending) {
          byProject.putIfAbsent(p.project, () => []).add(p);
        }

        return ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            Text(
              'Only verified to-dos count toward progress and billing.',
              style: textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.md),
            for (final MapEntry(key: project, value: items)
                in byProject.entries) ...[
              Card(
                clipBehavior: Clip.antiAlias,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ListTile(
                      title: Text(project.name, style: textTheme.titleMedium),
                      subtitle: Text(
                        '${project.code} · ${items.length} awaiting verification',
                      ),
                      trailing: TextButton(
                        onPressed: () => context.go(
                          AppRoutes.projectTab(project.id, ProjectTab.schedule),
                        ),
                        child: const Text('Open schedule'),
                      ),
                    ),
                    const Divider(height: 1),
                    for (final item in items)
                      ScheduleVerificationTile(
                        todo: item.todo,
                        categoryName: item.category.name,
                        doneByName: vm.userName(item.todo.doneBy),
                        verifying: vm.isVerifying(item.todo),
                        onVerify: () async {
                          final error = await vm.verify(item.todo);
                          if (error != null && context.mounted) {
                            ScaffoldMessenger.of(
                              context,
                            ).showSnackBar(SnackBar(content: Text(error)));
                          }
                        },
                      ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
          ],
        );
      },
    );
  }
}

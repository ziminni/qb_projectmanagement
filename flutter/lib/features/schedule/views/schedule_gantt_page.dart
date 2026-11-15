import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/utils/page_padding.dart';
import '../../../shared/widgets/app_empty_state.dart';
import '../../../shared/widgets/app_gantt_chart.dart';
import '../viewmodels/schedule_viewmodel.dart';

/// The Gantt project tab: categories as parent bars, to-dos as children.
class ScheduleGanttPage extends StatelessWidget {
  const ScheduleGanttPage({super.key, required this.projectId});

  final int projectId;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      key: ValueKey(projectId),
      create: (_) => ScheduleViewModel(
        projectId: projectId,
        session: getIt(),
        projects: getIt(),
        schedule: getIt(),
        users: getIt(),
        company: getIt(),
      )..load(),
      builder: (context, _) {
        final vm = context.watch<ScheduleViewModel>();
        if (vm.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        if (vm.error != null) return AppEmptyState(message: vm.error!);
        final project = vm.project!;
        return ListView(
          padding: pagePadding(context),
          children: [
            AppGanttChart(
              progress: vm.progress!,
              projectStart: project.startDate,
              projectEnd: project.targetEndDate,
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
        );
      },
    );
  }
}

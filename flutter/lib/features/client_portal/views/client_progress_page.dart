import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/page_padding.dart';
import '../../../routes/routes.dart';
import '../../../shared/widgets/app_empty_state.dart';
import '../../../shared/widgets/app_gantt_chart.dart';
import '../../../shared/widgets/app_progress_bar.dart';
import '../../../shared/widgets/app_s_curve_chart.dart';
import '../../../shared/widgets/app_section_card.dart';
import '../viewmodels/client_progress_viewmodel.dart';

/// Client progress view: progress bar, S-curve and read-only Gantt.
class ClientProgressPage extends StatelessWidget {
  const ClientProgressPage({super.key, this.projectId});

  final int? projectId;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      key: ValueKey(projectId),
      create: (_) => ClientProgressViewModel(
        projectId: projectId,
        session: getIt(),
        projects: getIt(),
        schedule: getIt(),
      )..load(),
      builder: (context, _) {
        final vm = context.watch<ClientProgressViewModel>();
        if (vm.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        if (vm.error != null) return AppEmptyState(message: vm.error!);
        final p = vm.project!;
        final progress = vm.progress!;
        final textTheme = Theme.of(context).textTheme;
        const gap = SizedBox(height: AppSpacing.lg);
        return ListView(
          padding: pagePadding(context),
          children: [
            if (vm.projects.length > 1) ...[
              Wrap(
                spacing: AppSpacing.sm,
                children: [
                  for (final other in vm.projects)
                    ChoiceChip(
                      label: Text(other.name),
                      selected: other.id == p.id,
                      onSelected: (_) =>
                          context.go(AppRoutes.clientProgressFor(other.id)),
                    ),
                ],
              ),
              gap,
            ],
            Text(p.name, style: textTheme.headlineSmall),
            Text(
              '${p.location} · ${Formatters.dateRange(p.startDate, p.targetEndDate)}',
              style: textTheme.bodySmall,
            ),
            gap,
            AppSectionCard(
              title: 'Progress',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${Formatters.percent(progress.progress)} complete',
                    style: textTheme.headlineSmall?.merge(
                      AppTextStyles.numeric,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  AppProgressBar(
                    value: progress.progress,
                    planned: progress.plannedProgress,
                    height: 12,
                    semanticsLabel: 'Project progress',
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Planned by today: ${Formatters.percent(progress.plannedProgress)}. '
                    'Progress counts only work verified by the project manager.',
                    style: textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            gap,
            AppSectionCard(
              title: 'S-curve',
              child: AppSCurveChart(points: vm.sCurve),
            ),
            gap,
            Text('Schedule', style: textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            AppGanttChart(
              progress: progress,
              projectStart: p.startDate,
              projectEnd: p.targetEndDate,
            ),
          ],
        );
      },
    );
  }
}

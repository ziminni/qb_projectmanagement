import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/models/project.dart';
import '../../../data/services/progress_calculator.dart';
import '../../../shared/widgets/app_progress_bar.dart';
import '../../../shared/widgets/app_project_status_chip.dart';
import '../../../shared/widgets/app_status_chip.dart';

class ProjectsProjectCard extends StatelessWidget {
  const ProjectsProjectCard({
    super.key,
    required this.project,
    required this.progress,
    required this.isBehind,
    required this.onTap,
    this.actions,
  });

  final Project project;
  final ProjectProgress progress;
  final bool isBehind;
  final VoidCallback onTap;

  /// Optional row under the card, e.g. site engineer shortcuts.
  final Widget? actions;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(project.code, style: textTheme.labelMedium),
                  AppProjectStatusChip(status: project.status),
                  if (isBehind)
                    const AppStatusChip(
                      label: 'Behind schedule',
                      icon: Icons.warning_amber_rounded,
                      foreground: AppColors.warning,
                      background: AppColors.warningContainer,
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(project.name, style: textTheme.titleMedium),
                        Text(project.location, style: textTheme.bodySmall),
                      ],
                    ),
                  ),
                  Text(
                    Formatters.percent(progress.progress),
                    style: textTheme.titleLarge?.merge(AppTextStyles.numeric),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              AppProgressBar(
                value: progress.progress,
                planned: progress.plannedProgress,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                Formatters.dateRange(project.startDate, project.targetEndDate),
                style: textTheme.bodySmall,
              ),
              if (actions != null) ...[
                const SizedBox(height: AppSpacing.sm),
                actions!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

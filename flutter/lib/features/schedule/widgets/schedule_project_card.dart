import 'package:flutter/material.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/models/project.dart';
import '../../../data/services/progress_calculator.dart';
import '../../../shared/widgets/app_progress_bar.dart';

class ScheduleProjectCard extends StatelessWidget {
  const ScheduleProjectCard({
    super.key,
    required this.project,
    required this.progress,
    required this.onTap,
  });

  final Project project;
  final ProjectProgress progress;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final awaiting = progress.categories.fold<int>(
      0,
      (s, c) => s + c.awaitingVerification,
    );
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${project.code} · ${project.status.label}',
                          style: textTheme.labelMedium,
                        ),
                        const SizedBox(height: AppSpacing.xxs),
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
                [
                  Formatters.dateRange(
                    project.startDate,
                    project.targetEndDate,
                  ),
                  '${progress.categories.length} categories',
                  if (awaiting > 0) '$awaiting awaiting verification',
                ].join(' · '),
                style: textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

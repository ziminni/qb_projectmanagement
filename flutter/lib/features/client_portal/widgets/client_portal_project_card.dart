import 'package:flutter/material.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/models/project.dart';
import '../../../data/services/progress_calculator.dart';
import '../../../shared/widgets/app_progress_bar.dart';
import '../../../shared/widgets/app_project_status_chip.dart';

/// Client-facing project summary: no budgets or internal costs.
class ClientPortalProjectCard extends StatelessWidget {
  const ClientPortalProjectCard({
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
                    child: Text(project.name, style: textTheme.titleMedium),
                  ),
                  AppProjectStatusChip(status: project.status),
                ],
              ),
              Text(project.location, style: textTheme.bodySmall),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Text(
                    Formatters.percent(progress.progress),
                    style: textTheme.headlineSmall?.merge(
                      AppTextStyles.numeric,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  const Text('complete'),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              AppProgressBar(
                value: progress.progress,
                planned: progress.plannedProgress,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Target completion ${Formatters.date(project.targetEndDate)}',
                style: textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

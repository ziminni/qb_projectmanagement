import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_radii.dart';
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
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: const BoxDecoration(
                      color: AppColors.primaryContainer,
                      borderRadius: AppRadii.mdAll,
                    ),
                    child: const Icon(
                      Icons.apartment_rounded,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(project.code, style: textTheme.labelSmall),
                        const SizedBox(height: 2),
                        Text(
                          project.name,
                          style: textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            const Icon(
                              Icons.place_outlined,
                              size: 14,
                              color: AppColors.textSecondary,
                            ),
                            const SizedBox(width: 3),
                            Flexible(
                              child: Text(
                                project.location,
                                style: textTheme.bodySmall,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Flexible(child: AppProjectStatusChip(status: project.status)),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    Formatters.percent(progress.progress),
                    style: textTheme.headlineSmall?.merge(
                      AppTextStyles.numeric,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text('complete', style: textTheme.bodySmall),
                  ),
                  const Spacer(),
                  if (isBehind)
                    const Flexible(
                      flex: 3,
                      child: AppStatusChip(
                        label: 'Behind schedule',
                        icon: Icons.warning_amber_rounded,
                        foreground: AppColors.warning,
                        background: AppColors.warningContainer,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              AppProgressBar(
                value: progress.progress,
                planned: progress.plannedProgress,
                color: isBehind ? AppColors.warning : AppColors.progressFill,
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  const Icon(
                    Icons.event_outlined,
                    size: 15,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      Formatters.dateRange(
                        project.startDate,
                        project.targetEndDate,
                      ),
                      style: textTheme.bodySmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    'Planned ${Formatters.percent(progress.plannedProgress)}',
                    style: textTheme.bodySmall,
                  ),
                ],
              ),
              if (actions != null) ...[
                const SizedBox(height: AppSpacing.md),
                const Divider(),
                const SizedBox(height: AppSpacing.md),
                actions!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/services/progress_calculator.dart';
import '../../../shared/widgets/app_progress_bar.dart';
import '../../../shared/widgets/app_status_chip.dart';
import '../../../shared/widgets/app_figure.dart';

/// Project progress bar with planned vs. actual and, for internal roles,
/// contract amount and earned value.
class ScheduleProgressSummary extends StatelessWidget {
  const ScheduleProgressSummary({
    super.key,
    required this.progress,
    required this.showCosts,
    required this.behindThreshold,
  });

  /// Points behind plan (0–1) before the project is flagged.
  final double behindThreshold;

  final ProjectProgress progress;
  final bool showCosts;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final variance = progress.scheduleVariance;
    final behind = variance > behindThreshold;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.sm,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      Formatters.percent(progress.progress),
                      style: textTheme.displaySmall?.merge(
                        AppTextStyles.numeric,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                      child: Text('complete', style: textTheme.bodyMedium),
                    ),
                  ],
                ),
                AppStatusChip(
                  label: behind
                      ? '${Formatters.percent(variance)} behind plan'
                      : 'On schedule',
                  icon: behind ? Icons.warning_amber_rounded : Icons.check,
                  foreground: behind ? AppColors.warning : AppColors.success,
                  background: behind
                      ? AppColors.warningContainer
                      : AppColors.successContainer,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            AppProgressBar(
              value: progress.progress,
              planned: progress.plannedProgress,
              height: 12,
              semanticsLabel: 'Project progress',
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Planned by ${Formatters.date(progress.asOf)}: '
              '${Formatters.percent(progress.plannedProgress)} (amber marker)',
              style: textTheme.bodySmall,
            ),
            if (showCosts) ...[
              const SizedBox(height: AppSpacing.lg),
              Wrap(
                spacing: AppSpacing.xl,
                runSpacing: AppSpacing.md,
                children: [
                  AppFigure(
                    label: 'Contract amount',
                    value: Formatters.peso(progress.contractAmount),
                  ),
                  AppFigure(
                    label: 'Earned value',
                    value: Formatters.peso(progress.earnedValue),
                  ),
                ],
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            Text(
              progress.usesBudgetWeights
                  ? 'Categories are weighted by budget.'
                  : 'Categories are weighted equally because '
                        '${progress.categories.isEmpty ? 'none have been added' : 'not every category has a budget'}.',
              style: textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

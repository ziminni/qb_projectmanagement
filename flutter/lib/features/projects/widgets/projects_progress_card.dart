import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/services/progress_calculator.dart';
import '../../../shared/widgets/app_progress_bar.dart';
import '../../../shared/widgets/app_s_curve_chart.dart';
import '../../../shared/widgets/app_section_card.dart';
import '../../../shared/widgets/app_status_chip.dart';

/// Progress bar, planned vs. actual, and the S-curve.
class ProjectsProgressCard extends StatelessWidget {
  const ProjectsProgressCard({
    super.key,
    required this.progress,
    required this.sCurve,
    required this.isBehind,
  });

  final ProjectProgress progress;
  final List<SCurvePoint> sCurve;
  final bool isBehind;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return AppSectionCard(
      title: 'Progress',
      trailing: Padding(
        padding: const EdgeInsets.only(right: AppSpacing.sm),
        child: AppStatusChip(
          label: isBehind
              ? '${Formatters.percent(progress.scheduleVariance)} behind plan'
              : 'On schedule',
          icon: isBehind ? Icons.warning_amber_rounded : Icons.check,
          foreground: isBehind ? AppColors.warning : AppColors.success,
          background: isBehind
              ? AppColors.warningContainer
              : AppColors.successContainer,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${Formatters.percent(progress.progress)} complete',
            style: textTheme.headlineSmall?.merge(AppTextStyles.numeric),
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
            'Planned by today: ${Formatters.percent(progress.plannedProgress)}',
            style: textTheme.bodySmall,
          ),
          const SizedBox(height: AppSpacing.lg),
          Text('S-curve', style: textTheme.titleSmall),
          const SizedBox(height: AppSpacing.sm),
          AppSCurveChart(points: sCurve),
        ],
      ),
    );
  }
}

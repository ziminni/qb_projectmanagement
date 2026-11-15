import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/utils/finance_access.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/app_progress_bar.dart';
import '../../../shared/widgets/app_project_status_chip.dart';
import '../viewmodels/dashboard_viewmodel.dart';

/// Compact project line: name, status, progress vs. plan.
class DashboardProjectRow extends StatelessWidget {
  const DashboardProjectRow({
    super.key,
    required this.item,
    required this.onTap,
  });

  final DashboardProject item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final p = item.project;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p.code, style: textTheme.labelSmall),
                      Text(
                        p.name,
                        style: textTheme.titleSmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Flexible(child: AppProjectStatusChip(status: p.status)),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            AppProgressBar(
              value: item.progress.progress,
              planned: item.progress.plannedProgress,
              color: item.isBehind ? AppColors.warning : AppColors.progressFill,
            ),
            const SizedBox(height: AppSpacing.xs),
            SizedBox(
              width: double.infinity,
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xxs,
                children: [
                  Text(
                    '${Formatters.percent(item.progress.progress)} done · '
                    'planned ${Formatters.percent(item.progress.plannedProgress)}'
                    '${item.isBehind ? ' · behind schedule' : ''}',
                    style: textTheme.bodySmall?.copyWith(
                      color: item.isBehind ? AppColors.warning : null,
                    ),
                  ),
                  if (canSeeFinance())
                    Text(
                      '${Formatters.pesoWhole(item.progress.earnedValue)} of '
                      '${Formatters.pesoWhole(p.contractAmount)}',
                      style: textTheme.bodySmall?.merge(AppTextStyles.numeric),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

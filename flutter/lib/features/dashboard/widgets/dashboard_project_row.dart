import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
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
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${p.code} · ${p.name}',
                    style: textTheme.titleSmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                AppProjectStatusChip(status: p.status),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            AppProgressBar(
              value: item.progress.progress,
              planned: item.progress.plannedProgress,
              color: item.isBehind ? AppColors.warning : AppColors.progressFill,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '${Formatters.percent(item.progress.progress)} done · '
              'planned ${Formatters.percent(item.progress.plannedProgress)}'
              '${item.isBehind ? ' · behind schedule' : ''}',
              style: textTheme.bodySmall?.copyWith(
                color: item.isBehind ? AppColors.warning : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

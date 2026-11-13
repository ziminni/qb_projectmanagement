import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/project.dart';
import 'app_info_row.dart';

/// A project request sent to a site engineer or client, with Accept and
/// Decline, and Request changes when [onRequestChanges] is set (clients).
/// [showAmount] is set for the client, who agrees to the price; site
/// engineers never see it.
class AppProjectRequestCard extends StatelessWidget {
  const AppProjectRequestCard({
    super.key,
    required this.project,
    required this.showAmount,
    required this.busy,
    required this.onAccept,
    required this.onDecline,
    this.onRequestChanges,
  });

  final Project project;
  final bool showAmount;
  final bool busy;
  final VoidCallback onAccept;
  final VoidCallback onDecline;
  final VoidCallback? onRequestChanges;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.warning),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.mark_email_unread_outlined),
                const SizedBox(width: AppSpacing.sm),
                Text('New project request', style: textTheme.labelLarge),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(project.name, style: textTheme.titleMedium),
            Text(
              '${project.code} · ${project.location}',
              style: textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.md),
            AppInfoRow(
              label: 'Schedule',
              value: Formatters.dateRange(
                project.startDate,
                project.targetEndDate,
              ),
            ),
            if (showAmount)
              AppInfoRow(
                label: 'Contract amount',
                value: Formatters.peso(project.contractAmount),
              ),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                FilledButton.icon(
                  onPressed: busy ? null : onAccept,
                  icon: const Icon(Icons.check),
                  label: const Text('Accept'),
                ),
                if (onRequestChanges != null)
                  OutlinedButton.icon(
                    onPressed: busy ? null : onRequestChanges,
                    icon: const Icon(Icons.edit_note),
                    label: const Text('Request changes'),
                  ),
                TextButton.icon(
                  onPressed: busy ? null : onDecline,
                  style: TextButton.styleFrom(foregroundColor: AppColors.error),
                  icon: const Icon(Icons.close),
                  label: const Text('Decline'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

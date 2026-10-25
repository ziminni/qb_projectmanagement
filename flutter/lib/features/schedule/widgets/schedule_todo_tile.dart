import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/models/todo.dart';
import '../../../shared/widgets/app_status_chip.dart';

enum _TodoAction { edit, delete, unverify }

/// One to-do with its completion and verification state. Controls appear only
/// for the actions the current role is allowed.
class ScheduleTodoTile extends StatelessWidget {
  const ScheduleTodoTile({
    super.key,
    required this.todo,
    required this.userName,
    required this.enabled,
    this.onSetDone,
    this.onVerify,
    this.onUnverify,
    this.onEdit,
    this.onDelete,
  });

  final Todo todo;
  final String? Function(int? id) userName;
  final bool enabled;
  final ValueChanged<bool>? onSetDone;
  final VoidCallback? onVerify;
  final VoidCallback? onUnverify;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final canToggle = onSetDone != null && !todo.isVerified && enabled;
    final hasMenu = onEdit != null || onDelete != null || onUnverify != null;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      child: Row(
        children: [
          if (onSetDone != null)
            Checkbox(
              value: todo.isDone,
              onChanged: canToggle ? (v) => onSetDone!(v ?? false) : null,
            )
          else
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Icon(
                todo.isVerified
                    ? Icons.check_circle
                    : todo.isDone
                    ? Icons.check_circle_outline
                    : Icons.radio_button_unchecked,
                size: 20,
                color: todo.isVerified
                    ? AppColors.success
                    : AppColors.textSecondary,
              ),
            ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(todo.title, style: textTheme.bodyMedium),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  Formatters.dateRange(todo.startDate, todo.endDate),
                  style: textTheme.bodySmall,
                ),
                if (_statusLine() case final line?) ...[
                  const SizedBox(height: AppSpacing.xxs),
                  Text(line, style: textTheme.bodySmall),
                ],
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          if (todo.isVerified)
            const AppStatusChip(
              label: 'Verified',
              icon: Icons.verified_outlined,
              foreground: AppColors.success,
              background: AppColors.successContainer,
            )
          else if (todo.isAwaitingVerification)
            onVerify != null
                ? FilledButton.tonal(
                    onPressed: enabled ? onVerify : null,
                    child: const Text('Verify'),
                  )
                : const AppStatusChip(
                    label: 'Awaiting verification',
                    foreground: AppColors.warning,
                    background: AppColors.warningContainer,
                  ),
          if (hasMenu)
            PopupMenuButton<_TodoAction>(
              tooltip: 'To-do actions',
              enabled: enabled,
              onSelected: (action) => switch (action) {
                _TodoAction.edit => onEdit?.call(),
                _TodoAction.delete => onDelete?.call(),
                _TodoAction.unverify => onUnverify?.call(),
              },
              itemBuilder: (context) => [
                if (onEdit != null)
                  const PopupMenuItem(
                    value: _TodoAction.edit,
                    child: Text('Edit'),
                  ),
                if (onUnverify != null && todo.isVerified)
                  const PopupMenuItem(
                    value: _TodoAction.unverify,
                    child: Text('Un-verify…'),
                  ),
                if (onDelete != null && !todo.isVerified)
                  const PopupMenuItem(
                    value: _TodoAction.delete,
                    child: Text('Delete'),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  String? _statusLine() {
    if (todo.isVerified && todo.verifiedAt != null) {
      final by = userName(todo.verifiedBy);
      return 'Verified ${by != null ? 'by $by ' : ''}'
          'on ${Formatters.date(todo.verifiedAt!.toLocal())}';
    }
    if (todo.isDone && todo.doneAt != null) {
      final by = userName(todo.doneBy);
      return 'Marked done ${by != null ? 'by $by ' : ''}'
          'on ${Formatters.date(todo.doneAt!.toLocal())}';
    }
    return null;
  }
}

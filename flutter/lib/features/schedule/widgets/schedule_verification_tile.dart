import 'package:flutter/material.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/models/todo.dart';

class ScheduleVerificationTile extends StatelessWidget {
  const ScheduleVerificationTile({
    super.key,
    required this.todo,
    required this.categoryName,
    required this.doneByName,
    required this.verifying,
    required this.onVerify,
  });

  final Todo todo;
  final String categoryName;
  final String? doneByName;
  final bool verifying;
  final VoidCallback onVerify;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final done = todo.doneAt == null
        ? 'Marked done'
        : 'Marked done on ${Formatters.date(todo.doneAt!.toLocal())}';
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(categoryName, style: textTheme.labelMedium),
                Text(todo.title, style: textTheme.bodyLarge),
                Text(
                  doneByName == null ? done : '$done by $doneByName',
                  style: textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          verifying
              ? const SizedBox.square(
                  dimension: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : FilledButton(onPressed: onVerify, child: const Text('Verify')),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';

/// One stage of an approval workflow.
class AppStep {
  const AppStep(this.label, {this.who});

  final String label;

  /// Who acts at this stage, e.g. "Owner".
  final String? who;
}

/// Horizontal step indicator: done, current and upcoming stages of a
/// workflow, plus a stopped state for rejected or returned items.
class AppStatusSteps extends StatelessWidget {
  const AppStatusSteps({
    super.key,
    required this.steps,
    required this.current,
    this.stoppedLabel,
    this.allDone = false,
  });

  final List<AppStep> steps;

  /// Index of the stage in progress.
  final int current;

  /// Set when the workflow stopped at [current], e.g. "Rejected".
  final String? stoppedLabel;

  /// Every stage is finished.
  final bool allDone;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final items = <Widget>[];
    for (var i = 0; i < steps.length; i++) {
      final done = allDone || i < current;
      final active = !allDone && i == current;
      final stopped = active && stoppedLabel != null;
      final color = stopped
          ? AppColors.error
          : done
          ? AppColors.success
          : active
          ? AppColors.primary
          : AppColors.textDisabled;
      items.add(
        SizedBox(
          width: 132,
          child: Column(
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: done || active
                    ? color
                    : AppColors.surfaceMuted,
                child: Icon(
                  stopped
                      ? Icons.close
                      : done
                      ? Icons.check
                      : Icons.circle,
                  size: done || stopped ? 16 : 8,
                  color: done || active ? Colors.white : AppColors.textDisabled,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                stopped ? stoppedLabel! : steps[i].label,
                textAlign: TextAlign.center,
                style: textTheme.labelMedium?.copyWith(
                  color: active || done ? AppColors.textPrimary : null,
                  fontWeight: active ? FontWeight.w700 : null,
                ),
              ),
              if (steps[i].who != null)
                Text(
                  steps[i].who!,
                  textAlign: TextAlign.center,
                  style: textTheme.labelSmall,
                ),
            ],
          ),
        ),
      );
      if (i < steps.length - 1) {
        items.add(
          Padding(
            padding: const EdgeInsets.only(top: 13),
            child: Container(
              width: 24,
              height: 2,
              color: done ? AppColors.success : AppColors.border,
            ),
          ),
        );
      }
    }
    return Card(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: items,
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';

/// Bar pinned below a long form so its main buttons stay in reach while
/// scrolling. Put it after an `Expanded` scrolling body in a `Column`.
class AppActionBar extends StatelessWidget {
  const AppActionBar({super.key, required this.children, this.hint});

  final List<Widget> children;

  /// Short note shown before the buttons, e.g. what submitting does.
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          child: Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            alignment: WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (hint != null)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Text(
                    hint!,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

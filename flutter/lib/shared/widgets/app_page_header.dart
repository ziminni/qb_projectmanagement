import 'package:flutter/material.dart';

import '../../core/constants/app_spacing.dart';
import '../../core/layout/app_top_bar.dart';

/// Title block at the top of a page: a heading, a line of context and the
/// page's main actions.
///
/// When [AppTopBar] is already displaying the same section title & subtitle,
/// repeating an orphaned subtitle line creates an empty horizontal gap across
/// the top of the page — so repeated headers with no actions collapse cleanly,
/// and repeated headers with actions render a compact right-aligned action row.
class AppPageHeader extends StatelessWidget {
  const AppPageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final repeated =
        AppShellTitle.of(context)?.toLowerCase() == title.toLowerCase();

    if (repeated) {
      if (actions.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.md),
        child: Align(
          alignment: Alignment.centerRight,
          child: Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            alignment: WrapAlignment.end,
            children: actions,
          ),
        ),
      );
    }

    final heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: textTheme.headlineSmall),
        if (subtitle != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            subtitle!,
            style: textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: AppSpacing.lg,
        runSpacing: AppSpacing.md,
        children: [
          heading,
          if (actions.isNotEmpty)
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: actions,
            ),
        ],
      ),
    );
  }
}

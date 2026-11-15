import 'package:flutter/material.dart';

import '../../core/constants/app_spacing.dart';
import '../../core/layout/app_top_bar.dart';

/// Title block at the top of a page: a heading, a line of context and the
/// page's main actions, which wrap below on narrow screens.
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
    // The shell's header already shows this title; don't say it twice.
    final repeated =
        AppShellTitle.of(context)?.toLowerCase() == title.toLowerCase();
    final heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!repeated) Text(title, style: textTheme.headlineSmall),
        if (subtitle != null) ...[
          if (!repeated) const SizedBox(height: AppSpacing.xs),
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
      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.end,
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

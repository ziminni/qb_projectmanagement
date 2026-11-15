import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';

/// A settings section in the GitHub style: a title, a line of description,
/// a rule, then the section's fields and its own save button.
class SettingsSectionFrame extends StatelessWidget {
  const SettingsSectionFrame({
    super.key,
    required this.title,
    required this.description,
    required this.children,
    this.banner,
  });

  final String title;
  final String description;
  final List<Widget> children;

  /// Shown above the title, e.g. an expiry warning.
  final Widget? banner;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (banner != null) ...[banner!, const SizedBox(height: AppSpacing.lg)],
        Text(title, style: textTheme.titleLarge),
        const SizedBox(height: AppSpacing.xs),
        Text(
          description,
          style: textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.md),
        const Divider(height: 1),
        const SizedBox(height: AppSpacing.xl),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ],
    );
  }
}

/// The section's save button, left-aligned under its fields.
class SettingsSaveButton extends StatelessWidget {
  const SettingsSaveButton({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xl),
      child: Align(
        alignment: Alignment.centerLeft,
        child: FilledButton(onPressed: onPressed, child: Text(label)),
      ),
    );
  }
}

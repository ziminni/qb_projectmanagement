import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../shared/widgets/app_brand_mark.dart';
import 'auth_brand_panel.dart';

/// Layout for the signed-out screens: the brand panel beside the form on
/// wide screens, the form alone (under the logo) on phones.
class AuthCard extends StatelessWidget {
  const AuthCard({
    super.key,
    required this.title,
    this.subtitle,
    required this.child,
    this.below,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? below;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final wide = MediaQuery.sizeOf(context).width >= 960;
    final form = Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!wide) ...[
                const Center(child: AppBrandMark(size: 40)),
                const SizedBox(height: 40),
              ],
              Text(title, style: theme.textTheme.displaySmall),
              if (subtitle != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  subtitle!,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.xxl),
              child,
              if (below != null) ...[
                const SizedBox(height: AppSpacing.xl),
                below!,
              ],
            ],
          ),
        ),
      ),
    );
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        top: !wide,
        bottom: !wide,
        child: wide
            ? Row(
                children: [
                  const Expanded(flex: 5, child: AuthBrandPanel()),
                  Expanded(flex: 6, child: form),
                ],
              )
            : form,
      ),
    );
  }
}

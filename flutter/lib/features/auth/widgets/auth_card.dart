import 'package:flutter/material.dart';

import '../../../core/constants/app_spacing.dart';

/// Centered, width-limited card used by the signed-out screens.
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
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    Icons.construction,
                    size: 40,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'BuildPro',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleLarge,
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.xl),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(title, style: theme.textTheme.headlineSmall),
                          if (subtitle != null) ...[
                            const SizedBox(height: AppSpacing.xs),
                            Text(subtitle!, style: theme.textTheme.bodySmall),
                          ],
                          const SizedBox(height: AppSpacing.lg),
                          child,
                        ],
                      ),
                    ),
                  ),
                  if (below != null) ...[
                    const SizedBox(height: AppSpacing.lg),
                    below!,
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

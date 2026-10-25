import 'package:flutter/material.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_text_styles.dart';

/// One headline figure, optionally tappable.
class DashboardStatTile extends StatelessWidget {
  const DashboardStatTile({
    super.key,
    required this.label,
    required this.value,
    this.detail,
    this.icon,
    this.color,
    this.onTap,
  });

  final String label;
  final String value;
  final String? detail;
  final IconData? icon;
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return SizedBox(
      width: 240,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (icon != null) ...[
                      Icon(icon, size: 18, color: color),
                      const SizedBox(width: AppSpacing.xs),
                    ],
                    Expanded(child: Text(label, style: textTheme.labelMedium)),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  value,
                  style: textTheme.headlineSmall
                      ?.merge(AppTextStyles.numeric)
                      .copyWith(color: color),
                ),
                if (detail != null) ...[
                  const SizedBox(height: AppSpacing.xxs),
                  Text(detail!, style: textTheme.bodySmall),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_radii.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../shared/widgets/app_progress_bar.dart';

/// One headline figure with a tinted icon, optional progress bar, and
/// optionally tappable. It fills the width it is given, so the dashboard lays
/// tiles out in a grid.
class DashboardStatTile extends StatelessWidget {
  const DashboardStatTile({
    super.key,
    required this.label,
    required this.value,
    this.detail,
    this.icon,
    this.color,
    this.progress,
    this.onTap,
  });

  final String label;
  final String value;
  final String? detail;
  final IconData? icon;
  final Color? color;
  final double? progress;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final tint = color ?? AppColors.primary;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodyMedium?.copyWith(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  if (icon != null) ...[
                    const SizedBox(width: AppSpacing.sm),
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: tint.withValues(alpha: 0.1),
                        borderRadius: AppRadii.mdAll,
                      ),
                      child: Icon(icon, size: 19, color: tint),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  style: textTheme.headlineSmall
                      ?.merge(AppTextStyles.numeric)
                      .copyWith(
                        fontSize: 28,
                        color: color ?? AppColors.textPrimary,
                      ),
                ),
              ),
              if (progress != null) ...[
                const SizedBox(height: AppSpacing.xs),
                AppProgressBar(value: progress!, height: 6, color: tint),
              ],
              if (detail != null) ...[
                const SizedBox(height: AppSpacing.xs),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        detail!,
                        style: textTheme.bodySmall,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (onTap != null)
                      const Icon(
                        Icons.arrow_forward_rounded,
                        size: 16,
                        color: AppColors.textDisabled,
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

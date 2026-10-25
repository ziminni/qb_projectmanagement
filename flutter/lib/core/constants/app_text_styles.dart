import 'package:flutter/material.dart';

import 'app_colors.dart';

abstract final class AppTextStyles {
  static const displaySmall = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.w600,
    height: 1.25,
    color: AppColors.textPrimary,
  );
  static const headlineSmall = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w600,
    height: 1.3,
    color: AppColors.textPrimary,
  );
  static const titleLarge = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    height: 1.3,
    color: AppColors.textPrimary,
  );
  static const titleMedium = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    height: 1.35,
    color: AppColors.textPrimary,
  );
  static const titleSmall = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    height: 1.4,
    color: AppColors.textPrimary,
  );
  static const bodyLarge = TextStyle(
    fontSize: 16,
    height: 1.5,
    color: AppColors.textPrimary,
  );
  static const bodyMedium = TextStyle(
    fontSize: 14,
    height: 1.45,
    color: AppColors.textPrimary,
  );
  static const bodySmall = TextStyle(
    fontSize: 12,
    height: 1.4,
    color: AppColors.textSecondary,
  );
  static const labelLarge = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.1,
  );
  static const labelMedium = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.2,
    color: AppColors.textSecondary,
  );
  static const labelSmall = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.3,
    color: AppColors.textSecondary,
  );

  /// Tabular figures keep percentages and amounts aligned in lists.
  static const numeric = TextStyle(
    fontFeatures: [FontFeature.tabularFigures()],
  );
}

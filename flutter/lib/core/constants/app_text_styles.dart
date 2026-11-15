import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_fonts.dart';

abstract final class AppTextStyles {
  static const displaySmall = TextStyle(
    fontFamily: AppFonts.display,
    fontSize: 30,
    fontWeight: FontWeight.w700,
    height: 1.2,
    letterSpacing: 0.2,
    color: AppColors.textPrimary,
  );
  static const headlineSmall = TextStyle(
    fontFamily: AppFonts.display,
    fontSize: 24,
    fontWeight: FontWeight.w700,
    height: 1.25,
    letterSpacing: 0.2,
    color: AppColors.textPrimary,
  );
  static const titleLarge = TextStyle(
    fontFamily: AppFonts.display,
    fontSize: 18,
    fontWeight: FontWeight.w700,
    height: 1.3,
    letterSpacing: 0.2,
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
    letterSpacing: 0,
  );
  static const labelMedium = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.2,
    color: AppColors.textSecondary,
  );
  static const labelSmall = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.4,
    color: AppColors.textSecondary,
  );

  /// Small upper-case section labels ("OVERVIEW", "TEAM").
  static const overline = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.8,
    color: AppColors.textSecondary,
  );

  /// Tabular figures keep percentages and amounts aligned in lists.
  static const numeric = TextStyle(
    // Figures stay in the body face: Cinzel numerals are hard to scan.
    fontFamily: AppFonts.body,
    fontFamilyFallback: AppFonts.fallback,
    fontFeatures: [FontFeature.tabularFigures()],
  );
}

import 'package:flutter/material.dart';

import '../constants/app_colors.dart';

/// ColorScheme generated from BRAND GOLD, never blue.
abstract final class AppColorScheme {
  AppColorScheme._();

  static ColorScheme light() {
    return ColorScheme.fromSeed(
      seedColor: AppColors.brandGold,
      brightness: Brightness.light,
    ).copyWith(
      primary: AppColors.brandGold,
      onPrimary: AppColors.brandBlack,
      primaryContainer: AppColors.brandGoldLight,
      onPrimaryContainer: AppColors.brandBlack,

      secondary: AppColors.brandBlack,
      onSecondary: AppColors.brandWhite,
      secondaryContainer: AppColors.selected,
      onSecondaryContainer: AppColors.brandBlack,

      tertiary: AppColors.brandGoldText,
      onTertiary: AppColors.brandWhite,
      tertiaryContainer: AppColors.selected,
      onTertiaryContainer: AppColors.brandBlack,

      surface: AppColors.cardBackground,
      onSurface: AppColors.textPrimary,
      onSurfaceVariant: AppColors.textSecondary,

      surfaceContainerLowest: AppColors.background,
      surfaceContainerLow: AppColors.surfaceSunken,
      surfaceContainer: AppColors.surfaceSunken,
      surfaceContainerHigh: AppColors.surfaceMuted,
      surfaceContainerHighest: AppColors.surfaceMuted,

      outline: AppColors.border,
      outlineVariant: AppColors.border,

      error: AppColors.errorText,
      onError: AppColors.brandWhite,
      errorContainer: AppColors.errorTint,
      onErrorContainer: AppColors.errorText,

      inverseSurface: AppColors.brandBlack,
      onInverseSurface: AppColors.brandGoldLight,
      inversePrimary: AppColors.brandGoldLight,

      surfaceTint: Colors.transparent,
      shadow: AppColors.brandBlack,
      scrim: AppColors.brandBlack,
    );
  }
}

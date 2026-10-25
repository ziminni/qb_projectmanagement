import 'package:flutter/material.dart';

import '../constants/app_colors.dart';

abstract final class AppColorScheme {
  static const light = ColorScheme(
    brightness: Brightness.light,
    primary: AppColors.primary,
    onPrimary: AppColors.onPrimary,
    primaryContainer: AppColors.primaryContainer,
    onPrimaryContainer: AppColors.onPrimaryContainer,
    secondary: AppColors.accent,
    onSecondary: AppColors.onAccent,
    secondaryContainer: AppColors.accentContainer,
    onSecondaryContainer: AppColors.onAccent,
    error: AppColors.error,
    onError: Colors.white,
    errorContainer: AppColors.errorContainer,
    onErrorContainer: AppColors.error,
    surface: AppColors.surface,
    onSurface: AppColors.textPrimary,
    onSurfaceVariant: AppColors.textSecondary,
    surfaceContainerLowest: AppColors.surface,
    surfaceContainerLow: AppColors.background,
    surfaceContainer: AppColors.surfaceMuted,
    surfaceContainerHigh: AppColors.surfaceMuted,
    surfaceContainerHighest: AppColors.border,
    outline: AppColors.border,
    outlineVariant: AppColors.border,
  );
}

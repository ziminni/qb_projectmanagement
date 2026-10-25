import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import 'app_button_theme.dart';
import 'app_card_theme.dart';
import 'app_color_scheme.dart';
import 'app_input_theme.dart';
import 'app_text_theme.dart';

abstract final class AppTheme {
  static final light = ThemeData(
    useMaterial3: true,
    colorScheme: AppColorScheme.light,
    textTheme: AppTextTheme.light,
    scaffoldBackgroundColor: AppColors.background,
    dividerColor: AppColors.border,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.surface,
      foregroundColor: AppColors.textPrimary,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 1,
    ),
    cardTheme: AppCardTheme.light,
    inputDecorationTheme: AppInputTheme.light,
    filledButtonTheme: AppButtonTheme.filled,
    elevatedButtonTheme: AppButtonTheme.elevated,
    outlinedButtonTheme: AppButtonTheme.outlined,
    textButtonTheme: AppButtonTheme.text,
    navigationRailTheme: const NavigationRailThemeData(
      backgroundColor: AppColors.surface,
      indicatorColor: AppColors.primaryContainer,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.progressFill,
      linearTrackColor: AppColors.progressTrack,
    ),
  );
}

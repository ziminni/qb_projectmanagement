import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_radii.dart';
import '../constants/app_spacing.dart';

abstract final class AppInputTheme {
  static const _border = OutlineInputBorder(
    borderRadius: AppRadii.smAll,
    borderSide: BorderSide(color: AppColors.border),
  );

  static final light = InputDecorationTheme(
    filled: true,
    fillColor: AppColors.surface,
    contentPadding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.md,
      vertical: AppSpacing.md,
    ),
    border: _border,
    enabledBorder: _border,
    focusedBorder: _border.copyWith(
      borderSide: const BorderSide(color: AppColors.primary, width: 2),
    ),
    errorBorder: _border.copyWith(
      borderSide: const BorderSide(color: AppColors.error),
    ),
    focusedErrorBorder: _border.copyWith(
      borderSide: const BorderSide(color: AppColors.error, width: 2),
    ),
  );
}

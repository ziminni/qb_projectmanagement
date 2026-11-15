import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_radii.dart';
import '../constants/app_spacing.dart';

abstract final class AppInputTheme {
  static const _border = OutlineInputBorder(
    borderRadius: AppRadii.mdAll,
    borderSide: BorderSide(color: AppColors.border),
  );

  static final light = InputDecorationTheme(
    filled: true,
    fillColor: AppColors.cardBackground,
    isDense: false,
    contentPadding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.lg,
      vertical: 14,
    ),
    labelStyle: const TextStyle(color: AppColors.textSecondary),
    floatingLabelStyle: WidgetStateTextStyle.resolveWith(
      (states) => TextStyle(
        color: states.contains(WidgetState.error)
            ? AppColors.errorText
            : states.contains(WidgetState.focused)
            ? AppColors.brandGoldText
            : AppColors.textSecondary,
        fontWeight: FontWeight.w600,
      ),
    ),
    hintStyle: const TextStyle(color: AppColors.disabled),
    prefixIconColor: AppColors.textSecondary,
    suffixIconColor: AppColors.textSecondary,
    helperStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
    border: _border,
    enabledBorder: _border,
    disabledBorder: _border.copyWith(
      borderSide: const BorderSide(color: AppColors.surfaceMuted),
    ),
    focusedBorder: _border.copyWith(
      borderSide: const BorderSide(color: AppColors.brandGold, width: 1.6),
    ),
    errorBorder: _border.copyWith(
      borderSide: const BorderSide(color: AppColors.errorText),
    ),
    focusedErrorBorder: _border.copyWith(
      borderSide: const BorderSide(color: AppColors.errorText, width: 1.6),
    ),
  );
}

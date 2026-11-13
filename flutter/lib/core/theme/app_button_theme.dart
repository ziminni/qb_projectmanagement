import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_radii.dart';
import '../constants/app_spacing.dart';

/// Button shapes and padding for the black/gold/cream/white theme.
abstract final class AppButtonTheme {
  static const _padding = EdgeInsets.symmetric(
    horizontal: AppSpacing.xl,
    vertical: 14,
  );
  static const _shape = RoundedRectangleBorder(borderRadius: AppRadii.mdAll);
  static const _minimumSize = Size(64, 44);

  /// Primary filled button: gold background, black text.
  static final filled = FilledButtonThemeData(
    style: FilledButton.styleFrom(
      backgroundColor: AppColors.brandGold,
      foregroundColor: AppColors.brandBlack,
      padding: _padding,
      shape: _shape,
      minimumSize: _minimumSize,
    ),
  );

  /// Secondary dark button: black background, light gold text.
  static final elevated = ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: AppColors.brandBlack,
      foregroundColor: AppColors.brandGoldLight,
      padding: _padding,
      shape: _shape,
      minimumSize: _minimumSize,
      elevation: 0,
    ),
  );

  /// Outlined button: white background, black text, cream border,
  /// gold hover/focus border.
  static final outlined = OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      backgroundColor: AppColors.cardBackground,
      foregroundColor: AppColors.textPrimary,
      side: const BorderSide(color: AppColors.border),
      padding: _padding,
      shape: _shape,
      minimumSize: _minimumSize,
    ),
  );

  /// Text button: black text, gold-cream background on hover/focus.
  static final text = TextButtonThemeData(
    style: ButtonStyle(
      foregroundColor: WidgetStateProperty.resolveWith<Color>(
        (Set<WidgetState> states) => AppColors.textPrimary,
      ),
      backgroundColor: WidgetStateProperty.resolveWith<Color>((
        Set<WidgetState> states,
      ) {
        if (states.contains(WidgetState.hovered) ||
            states.contains(WidgetState.focused)) {
          return AppColors.selected;
        }
        return AppColors.cardBackground;
      }),
      padding: WidgetStateProperty.resolveWith<EdgeInsetsGeometry>(
        (Set<WidgetState> states) => const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
      ),
      shape: WidgetStateProperty.resolveWith<OutlinedBorder>(
        (Set<WidgetState> states) =>
            RoundedRectangleBorder(borderRadius: AppRadii.mdAll),
      ),
      side: WidgetStateProperty.resolveWith<BorderSide>(
        (Set<WidgetState> states) =>
            states.contains(WidgetState.hovered) ||
                states.contains(WidgetState.focused)
            ? const BorderSide(color: AppColors.brandGold)
            : const BorderSide(color: AppColors.border),
      ),
    ),
  );
}

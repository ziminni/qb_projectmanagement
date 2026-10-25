import 'package:flutter/material.dart';

import '../constants/app_radii.dart';
import '../constants/app_spacing.dart';

/// Button shapes and padding. Text styles come from the theme's
/// `labelLarge`, so buttons share the app font.
abstract final class AppButtonTheme {
  static const _padding = EdgeInsets.symmetric(
    horizontal: AppSpacing.lg,
    vertical: AppSpacing.md,
  );
  static const _shape = RoundedRectangleBorder(borderRadius: AppRadii.smAll);

  static final filled = FilledButtonThemeData(
    style: FilledButton.styleFrom(padding: _padding, shape: _shape),
  );

  static final elevated = ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      padding: _padding,
      shape: _shape,
      elevation: 0,
    ),
  );

  static final outlined = OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(padding: _padding, shape: _shape),
  );

  static final text = TextButtonThemeData(
    style: TextButton.styleFrom(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      shape: _shape,
    ),
  );
}

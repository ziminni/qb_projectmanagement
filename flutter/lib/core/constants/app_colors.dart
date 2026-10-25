import 'package:flutter/material.dart';

/// Raw color palette. Widgets should prefer `Theme.of(context).colorScheme`;
/// use these directly only for status colors the scheme has no slot for.
abstract final class AppColors {
  static const primary = Color(0xFF1F3A5F);
  static const onPrimary = Color(0xFFFFFFFF);
  static const primaryContainer = Color(0xFFD6E2F0);
  static const onPrimaryContainer = Color(0xFF0B1F36);

  static const accent = Color(0xFFF2A900);
  static const onAccent = Color(0xFF1F1A10);
  static const accentContainer = Color(0xFFFFE8B3);

  static const background = Color(0xFFF6F7F9);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceMuted = Color(0xFFEEF1F5);
  static const border = Color(0xFFD9DEE5);

  static const textPrimary = Color(0xFF1B2430);
  static const textSecondary = Color(0xFF5A6675);
  static const textDisabled = Color(0xFF9AA4B1);

  static const success = Color(0xFF2E7D4F);
  static const successContainer = Color(0xFFDDF1E4);
  static const warning = Color(0xFFB26A00);
  static const warningContainer = Color(0xFFFFF0D6);
  static const error = Color(0xFFC0392B);
  static const errorContainer = Color(0xFFFBE2DF);
  static const info = Color(0xFF2F6FB2);
  static const infoContainer = Color(0xFFDCEAF8);

  /// Progress fill colors used by progress bars and the Gantt chart.
  static const progressTrack = Color(0xFFE3E8EE);
  static const progressFill = primary;
  static const progressPending = Color(0xFF9DB7D5);
  static const plannedMarker = accent;
}

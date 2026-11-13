import 'package:flutter/material.dart';

/// Raw color palette for the Queen Builders Construction Project Management
/// System. The interface is black, gold, cream, and white — no blue.
///
/// Widgets should prefer `Theme.of(context).colorScheme`; use these directly
/// only for status colors the scheme has no slot for.
abstract final class AppColors {
  AppColors._();

  static const Color brandBlack = Color(0xFF050505);
  static const Color brandGold = Color(0xFFAC934F);
  static const Color brandGoldLight = Color(0xFFE1C684);
  static const Color brandGoldText = Color(0xFF6E5A22);
  static const Color brandWhite = Color(0xFFFFFFFF);

  static const Color background = Color(0xFFF8F6F0);
  static const Color cardBackground = Color(0xFFFFFFFF);
  static const Color textPrimary = Color(0xFF050505);
  static const Color textSecondary = Color(0xFF686257);
  static const Color disabled = Color(0xFFAAA394);
  static const Color selected = Color(0xFFF1E6C9);

  static const Color border = Color(0xFFDED5C0);

  static const Color surfaceSunken = Color(0xFFF3EFE5);
  static const Color surfaceMuted = Color(0xFFEDE7D9);
  static const Color tableHeader = Color(0xFFF6F2E8);

  static const Color chrome = Color(0xFF050505);
  static const Color chromeRaised = Color(0xFF141311);
  static const Color chromeBorder = Color(0xFF262420);
  static const Color chromeText = Color(0xFFBDB6A6);

  static const Color successText = Color(0xFF065F46);
  static const Color successTint = Color(0xFFE7F6EF);
  static const Color warningText = Color(0xFF7C2D12);
  static const Color warningTint = Color(0xFFFEF3C7);
  static const Color errorText = Color(0xFF991B1B);
  static const Color errorTint = Color(0xFFFEE2E2);

  // Backward-compatible aliases mapped to the new palette so existing
  // references keep compiling while being repointed away from blue.
  static const Color primary = brandGold;
  static const Color primaryDark = brandBlack;
  static const Color onPrimary = brandBlack;
  static const Color primaryContainer = brandGoldLight;
  static const Color onPrimaryContainer = brandBlack;

  static const Color accent = brandGold;
  static const Color onAccent = brandBlack;
  static const Color accentContainer = selected;

  static const Color sidebar = chrome;
  static const Color sidebarRaised = chromeRaised;
  static const Color sidebarActive = selected;
  static const Color sidebarText = chromeText;
  static const Color sidebarTextActive = brandGoldLight;
  static const Color sidebarDivider = chromeBorder;

  static const Color success = successText;
  static const Color successContainer = successTint;
  static const Color warning = warningText;
  static const Color warningContainer = warningTint;
  static const Color error = errorText;
  static const Color errorContainer = errorTint;

  static const Color info = brandGoldText;
  static const Color infoContainer = selected;

  static const Color surface = cardBackground;
  static const Color textDisabled = disabled;
  static const Color borderStrong = border;

  static const Color progressTrack = surfaceMuted;
  static const Color progressFill = brandGold;
  static const Color progressPending = surfaceMuted;
  static const Color plannedMarker = brandGold;

  /// Brand gradient for the logo mark and hero panels.
  static const brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFAC934F), Color(0xFF050505)],
    tileMode: TileMode.clamp,
  );
}

import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_fonts.dart';
import '../constants/app_radii.dart';
import '../constants/app_text_styles.dart';
import 'app_button_theme.dart';
import 'app_card_theme.dart';
import 'app_color_scheme.dart';
import 'app_input_theme.dart';
import 'app_motion.dart';
import 'app_text_theme.dart';

abstract final class AppTheme {
  static final light = ThemeData(
    useMaterial3: true,
    fontFamily: AppFonts.body,
    fontFamilyFallback: AppFonts.fallback,
    colorScheme: AppColorScheme.light(),
    textTheme: AppTextTheme.light,
    scaffoldBackgroundColor: AppColors.background,
    dividerColor: AppColors.border,
    dividerTheme: const DividerThemeData(
      color: AppColors.border,
      thickness: 1,
      space: 1,
    ),
    visualDensity: VisualDensity.standard,
    pageTransitionsTheme: PageTransitionsTheme(
      builders: {
        for (final p in TargetPlatform.values)
          p: const AppPageTransitionsBuilder(),
      },
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.surface,
      foregroundColor: AppColors.textPrimary,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      toolbarHeight: 64,
      titleSpacing: 24,
      titleTextStyle: TextStyle(
        fontFamily: AppFonts.display,
        fontSize: 20,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.3,
        color: AppColors.textPrimary,
      ),
      shape: Border(bottom: BorderSide(color: AppColors.border)),
    ),
    cardTheme: AppCardTheme.light,
    inputDecorationTheme: AppInputTheme.light,
    filledButtonTheme: AppButtonTheme.filled,
    elevatedButtonTheme: AppButtonTheme.elevated,
    outlinedButtonTheme: AppButtonTheme.outlined,
    textButtonTheme: AppButtonTheme.text,
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: AppColors.textSecondary,
        shape: const RoundedRectangleBorder(borderRadius: AppRadii.mdAll),
      ),
    ),
    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 2),
      iconColor: AppColors.textSecondary,
      titleTextStyle: TextStyle(
        fontFamily: AppFonts.body,
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
      ),
      subtitleTextStyle: TextStyle(
        fontFamily: AppFonts.body,
        fontSize: 13,
        height: 1.4,
        color: AppColors.textSecondary,
      ),
    ),
    tabBarTheme: const TabBarThemeData(
      labelColor: AppColors.brandBlack,
      unselectedLabelColor: AppColors.textSecondary,
      indicatorColor: AppColors.brandGold,
      indicatorSize: TabBarIndicatorSize.label,
      dividerColor: AppColors.border,
      labelStyle: TextStyle(
        fontFamily: AppFonts.body,
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
      unselectedLabelStyle: TextStyle(
        fontFamily: AppFonts.body,
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
      tabAlignment: TabAlignment.start,
    ),
    chipTheme: ChipThemeData(
      backgroundColor: AppColors.surface,
      selectedColor: AppColors.primaryContainer,
      side: const BorderSide(color: AppColors.border),
      shape: const RoundedRectangleBorder(borderRadius: AppRadii.pillAll),
      labelStyle: AppTextStyles.labelLarge.copyWith(
        fontFamily: AppFonts.body,
        color: AppColors.textPrimary,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        selectedBackgroundColor: AppColors.primaryContainer,
        selectedForegroundColor: AppColors.onPrimaryContainer,
        side: const BorderSide(color: AppColors.border),
        shape: const RoundedRectangleBorder(borderRadius: AppRadii.mdAll),
      ),
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: AppRadii.xlAll),
      titleTextStyle: TextStyle(
        fontFamily: AppFonts.body,
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
      ),
    ),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.brandBlack,
      contentTextStyle: TextStyle(
        fontFamily: AppFonts.body,
        color: Colors.white,
        fontWeight: FontWeight.w500,
      ),
      shape: RoundedRectangleBorder(borderRadius: AppRadii.mdAll),
      width: 440,
    ),
    tooltipTheme: const TooltipThemeData(
      decoration: BoxDecoration(
        color: AppColors.brandBlack,
        borderRadius: AppRadii.smAll,
      ),
      textStyle: TextStyle(
        fontFamily: AppFonts.body,
        color: AppColors.brandGoldLight,
        fontSize: 12,
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected)
            ? AppColors.brandGoldLight
            : AppColors.textSecondary,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected)
            ? AppColors.brandBlack
            : AppColors.surfaceMuted,
      ),
      trackOutlineColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected)
            ? AppColors.brandBlack
            : AppColors.borderStrong,
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(5)),
      ),
      side: const BorderSide(color: AppColors.borderStrong, width: 1.5),
      checkColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? AppColors.brandBlack
            : AppColors.textSecondary,
      ),
    ),
    popupMenuTheme: const PopupMenuThemeData(
      color: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadii.mdAll,
        side: BorderSide(color: AppColors.border),
      ),
    ),
    navigationRailTheme: const NavigationRailThemeData(
      backgroundColor: AppColors.surface,
      indicatorColor: AppColors.brandGoldLight,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.progressFill,
      linearTrackColor: AppColors.progressTrack,
    ),
  );
}

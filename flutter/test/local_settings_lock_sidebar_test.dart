import 'dart:math' as math;

import 'package:buildpro_frontend/core/di/service_locator.dart';
import 'package:buildpro_frontend/core/layout/app_sidebar.dart';
import 'package:buildpro_frontend/core/theme/app_theme.dart';
import 'package:buildpro_frontend/data/services/local_settings_service.dart';
import 'package:buildpro_frontend/data/services/local_settings_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

void main() {
  setUp(resetServices);

  group('LocalSettingsService persistence', () {
    test('persists system and sidebar preferences locally', () async {
      final store = MemoryLocalSettingsStore();
      final first = LocalSettingsService(store: store);
      expect(first.sidebarCollapsed, isTrue);
      expect(first.appearance, AppAppearanceMode.warm);
      expect(first.displayComfort, DisplayComfort.standard);

      await first.setAppearance(AppAppearanceMode.dark);
      await first.setAccent(AppAccentPalette.emerald);
      await first.setSidebarFinish(SidebarFinish.charcoal);
      await first.setDisplayComfort(DisplayComfort.compact);
      await first.setSidebarCollapsed(false);

      final reloaded = LocalSettingsService(store: store);
      await reloaded.load();
      expect(reloaded.appearance, AppAppearanceMode.dark);
      expect(reloaded.accent, AppAccentPalette.emerald);
      expect(reloaded.sidebarFinish, SidebarFinish.charcoal);
      expect(reloaded.displayComfort, DisplayComfort.compact);
      expect(reloaded.sidebarCollapsed, isFalse);

      await reloaded.resetSystemDefaults();
      expect(reloaded.appearance, AppAppearanceMode.warm);
      expect(reloaded.accent, AppAccentPalette.gold);
      expect(reloaded.sidebarFinish, SidebarFinish.obsidian);
      expect(reloaded.displayComfort, DisplayComfort.standard);
    });

    test(
      'all appearance, accent, and sidebar combinations maintain readable contrast',
      () async {
        double contrastRatio(Color a, Color b) {
          final la = a.computeLuminance();
          final lb = b.computeLuminance();
          final hi = math.max(la, lb);
          final lo = math.min(la, lb);
          return (hi + 0.05) / (lo + 0.05);
        }

        for (final finish in SidebarFinish.values) {
          expect(
            contrastRatio(finish.text, finish.background),
            greaterThanOrEqualTo(4.5),
            reason: '${finish.label} text on background',
          );
          expect(
            contrastRatio(finish.selectedText, finish.background),
            greaterThanOrEqualTo(7.0),
            reason: '${finish.label} selectedText on background',
          );
          expect(
            contrastRatio(finish.selectedText, finish.raised),
            greaterThanOrEqualTo(7.0),
            reason: '${finish.label} selectedText on raised card',
          );
          for (final accent in AppAccentPalette.values) {
            final activeIcon = finish.isDark
                ? accent.light
                : accent.onLightSurface;
            expect(
              contrastRatio(activeIcon, finish.background),
              greaterThanOrEqualTo(4.5),
              reason: '${accent.label} active icon on ${finish.label} sidebar',
            );
          }
        }

        for (final accent in AppAccentPalette.values) {
          expect(
            contrastRatio(accent.onPrimary, accent.primary),
            greaterThanOrEqualTo(4.0),
            reason: '${accent.label} onPrimary on primary',
          );
          expect(
            contrastRatio(accent.onLightSurface, Colors.white),
            greaterThanOrEqualTo(4.5),
            reason: '${accent.label} onLightSurface on white',
          );
          expect(
            contrastRatio(accent.light, const Color(0xFF1A1917)),
            greaterThanOrEqualTo(4.5),
            reason: '${accent.label} light on dark surface',
          );
        }

        final service = LocalSettingsService(store: MemoryLocalSettingsStore());
        for (final mode in AppAppearanceMode.values) {
          for (final accent in AppAccentPalette.values) {
            await service.applySystemSettings(
              appearance: mode,
              accent: accent,
              sidebarFinish: SidebarFinish.obsidian,
              displayComfort: DisplayComfort.standard,
            );
            final theme = AppTheme.forSettings(service);
            expect(
              contrastRatio(
                theme.colorScheme.onSurface,
                theme.colorScheme.surface,
              ),
              greaterThanOrEqualTo(7.0),
              reason: '${mode.label} + ${accent.label} onSurface/surface',
            );
            expect(
              contrastRatio(
                theme.colorScheme.onSurface,
                theme.scaffoldBackgroundColor,
              ),
              greaterThanOrEqualTo(7.0),
              reason: '${mode.label} + ${accent.label} onSurface/scaffold',
            );
          }
        }
      },
    );
  });

  testWidgets('sidebar defaults to collapsed rail and expands/collapses smoothly', (
    tester,
  ) async {
    await pumpApp(tester, size: const Size(1400, 900));
    await signInAs(tester, 'maria@example.ph');

    // Header has no Account profile menu or Lock screen button; sidebar footer has Settings + Log out.
    expect(find.byTooltip('Account'), findsNothing);
    expect(find.byTooltip('Lock screen'), findsNothing);
    expect(find.byKey(const ValueKey('sidebar-pinned-settings')), findsOneWidget);
    expect(find.byTooltip('Log out'), findsOneWidget);

    // Default collapsed: icon-only rail (no item labels, no collapse button, no edge arrow).
    expect(
      tester.getSize(find.byType(AppSidebar)).width,
      AppSidebar.compactWidth,
    );
    expect(find.byKey(const ValueKey('sidebar-collapse-btn')), findsNothing);
    expect(find.byKey(const ValueKey('sidebar-edge-toggle')), findsNothing);
    expect(find.byType(CircleAvatar), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AppSidebar),
        matching: find.text('Dashboard'),
      ),
      findsNothing,
    );

    // Expand by clicking logo: labels, hexagon badge, user name/role, and collapse button appear.
    await tester.tap(find.byKey(const ValueKey('sidebar-logo-expand')));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(AppSidebar)).width, AppSidebar.fullWidth);
    expect(find.byKey(const ValueKey('sidebar-collapse-btn')), findsOneWidget);
    expect(find.byType(ClipPath), findsWidgets);
    expect(find.byTooltip('Log out'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AppSidebar),
        matching: find.text('Dashboard'),
      ),
      findsOneWidget,
    );

    // Collapse via collapse button.
    await tester.tap(find.byKey(const ValueKey('sidebar-collapse-btn')));
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byType(AppSidebar)).width,
      AppSidebar.compactWidth,
    );
    expect(find.byKey(const ValueKey('sidebar-collapse-btn')), findsNothing);
    expect(
      find.descendant(
        of: find.byType(AppSidebar),
        matching: find.text('Dashboard'),
      ),
      findsNothing,
    );

    // Expand via clicking free space in sidebar.
    final freeSpace = find.byKey(const ValueKey('sidebar-free-space'));
    final bottomCenter =
        tester.getBottomLeft(freeSpace) + const Offset(30, -10);
    await tester.tapAt(bottomCenter);
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(AppSidebar)).width, AppSidebar.fullWidth);
  });

  testWidgets('System settings previews draft changes and saves/cancels via floating bar', (
    tester,
  ) async {
    await pumpApp(tester, size: const Size(1400, 900));
    await signInAs(tester, 'maria@example.ph');

    await goTo(tester, '/admin/settings?section=system');
    expect(find.text('Display & startup'), findsNothing);
    expect(find.text('Security & lock'), findsNothing);
    expect(find.byKey(const ValueKey('system-settings-preview')), findsOneWidget);
    expect(find.text('LIVE PREVIEW'), findsOneWidget);
    expect(find.text('WORKSPACE APPEARANCE'), findsOneWidget);
    expect(find.text('ACCENT PALETTE'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('system-settings-floating-bar')),
      findsNothing,
    );

    // Selecting a theme updates the live preview only (does NOT apply yet) and
    // reveals the floating Cancel / Save changes bar.
    await tester.tap(find.text('Obsidian Dark'));
    await tester.pumpAndSettle();
    expect(getIt<LocalSettingsService>().appearance, AppAppearanceMode.warm);
    expect(find.text('OBSIDIAN DARK · QUEEN BRASS'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('system-settings-floating-bar')),
      findsOneWidget,
    );

    // Cancel reverts preview and dismisses floating bar.
    await tester.tap(find.byKey(const ValueKey('system-settings-cancel')));
    await tester.pumpAndSettle();
    expect(getIt<LocalSettingsService>().appearance, AppAppearanceMode.warm);
    expect(find.text('WARM CREAM · QUEEN BRASS'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('system-settings-floating-bar')),
      findsNothing,
    );

    // Select again and Save changes -> applies live theme.
    await tester.tap(find.text('Obsidian Dark'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('system-settings-save')));
    await tester.pumpAndSettle();
    expect(getIt<LocalSettingsService>().appearance, AppAppearanceMode.dark);
    expect(
      find.byKey(const ValueKey('system-settings-floating-bar')),
      findsNothing,
    );

    // Reset default stages defaults in preview, then Save changes applies them.
    await tester.tap(find.byKey(const ValueKey('system-settings-reset')));
    await tester.pumpAndSettle();
    expect(getIt<LocalSettingsService>().appearance, AppAppearanceMode.dark);
    expect(
      find.byKey(const ValueKey('system-settings-floating-bar')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('system-settings-save')));
    await tester.pumpAndSettle();
    expect(getIt<LocalSettingsService>().appearance, AppAppearanceMode.warm);
  });

  testWidgets('clicking an approval row shows Back button and returns to Approvals', (
    tester,
  ) async {
    await pumpApp(tester, size: const Size(1400, 900));
    await signInAs(tester, 'ramon@example.ph');

    await goTo(tester, '/approvals');
    expect(find.text('Back'), findsNothing);

    // Tap the first approval row (e.g. a linked destination like To-do verification or Daily report).
    await tester.tap(find.byType(ListTile).first);
    await tester.pumpAndSettle();

    expect(find.text('Back'), findsOneWidget);
    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Approvals'), findsOneWidget);
    expect(
      find.text('Everything waiting for your decision, grouped by type.'),
      findsNothing,
    );
  });
}

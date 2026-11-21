import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_fonts.dart';
import '../../../core/constants/app_radii.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/utils/app_messages.dart';
import '../../../data/services/local_settings_service.dart';
import 'settings_section_frame.dart';

class SettingsSystemAppearanceSection extends StatefulWidget {
  const SettingsSystemAppearanceSection({super.key});

  @override
  State<SettingsSystemAppearanceSection> createState() =>
      _SettingsSystemAppearanceSectionState();
}

class _SettingsSystemAppearanceSectionState
    extends State<SettingsSystemAppearanceSection> {
  late AppAppearanceMode _appearance;
  late AppAccentPalette _accent;
  late SidebarFinish _sidebarFinish;
  late DisplayComfort _displayComfort;
  bool _saving = false;
  OverlayEntry? _floatingBarEntry;

  @override
  void initState() {
    super.initState();
    final saved = context.read<LocalSettingsService>();
    _appearance = saved.appearance;
    _accent = saved.accent;
    _sidebarFinish = saved.sidebarFinish;
    _displayComfort = saved.displayComfort;
  }

  @override
  void dispose() {
    _removeFloatingBar();
    super.dispose();
  }

  bool _hasChanges(LocalSettingsService saved) =>
      _appearance != saved.appearance ||
      _accent != saved.accent ||
      _sidebarFinish != saved.sidebarFinish ||
      _displayComfort != saved.displayComfort;

  void _updateDraft(VoidCallback mutate) {
    setState(mutate);
    _syncFloatingBar();
  }

  void _cancelChanges() {
    final saved = context.read<LocalSettingsService>();
    setState(() {
      _appearance = saved.appearance;
      _accent = saved.accent;
      _sidebarFinish = saved.sidebarFinish;
      _displayComfort = saved.displayComfort;
    });
    _removeFloatingBar();
  }

  Future<void> _saveChanges() async {
    if (_saving) return;
    setState(() => _saving = true);
    _floatingBarEntry?.markNeedsBuild();
    final saved = context.read<LocalSettingsService>();
    await saved.applySystemSettings(
      appearance: _appearance,
      accent: _accent,
      sidebarFinish: _sidebarFinish,
      displayComfort: _displayComfort,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    _removeFloatingBar();
    showAppMessage(context, 'System settings saved.');
  }

  void _resetToDefaults() {
    _updateDraft(() {
      _appearance = AppAppearanceMode.warm;
      _accent = AppAccentPalette.gold;
      _sidebarFinish = SidebarFinish.obsidian;
      _displayComfort = DisplayComfort.standard;
    });
  }

  void _syncFloatingBar() {
    if (!mounted) return;
    final saved = context.read<LocalSettingsService>();
    if (!_hasChanges(saved)) {
      _removeFloatingBar();
      return;
    }
    if (_floatingBarEntry != null) {
      _floatingBarEntry!.markNeedsBuild();
      return;
    }
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;
    _floatingBarEntry = OverlayEntry(
      builder: (overlayContext) => _FloatingSaveBar(
        accent: _accent,
        saving: _saving,
        onCancel: _cancelChanges,
        onSave: _saveChanges,
      ),
    );
    overlay.insert(_floatingBarEntry!);
  }

  void _removeFloatingBar() {
    _floatingBarEntry?.remove();
    _floatingBarEntry = null;
  }

  @override
  Widget build(BuildContext context) {
    final saved = context.watch<LocalSettingsService>();
    final hasChanges = _hasChanges(saved);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = _accent.primary;
    final cardBg = isDark ? const Color(0xFF1A1917) : AppColors.cardBackground;
    final softBg = isDark ? const Color(0xFF23211E) : const Color(0xFFF3EFE5);
    final borderColor = isDark ? const Color(0xFF33302B) : AppColors.border;
    final fg = isDark ? Colors.white : AppColors.textPrimary;
    final muted = isDark ? const Color(0xFFB5AFA3) : AppColors.textSecondary;

    return SettingsSectionFrame(
      title: 'System settings',
      description:
          'Customize the theme, accent palette, sidebar finish, and display comfort for this computer.',
      children: [
        // Local-device info banner.
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          decoration: BoxDecoration(
            color: softBg,
            borderRadius: AppRadii.lgAll,
            border: Border.all(color: borderColor),
          ),
          child: Row(
            children: [
              Icon(Icons.desktop_windows_outlined, size: 18, color: muted),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  'Saved on this device only. Preview your theme changes below, then click Save changes to apply them without changing company settings or other devices.',
                  style: TextStyle(fontSize: 13, height: 1.4, color: muted),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),

        // 1. Live Preview card (reflects draft state immediately).
        _SystemCard(
          title: 'LIVE PREVIEW',
          cardBg: cardBg,
          borderColor: borderColor,
          fg: fg,
          muted: muted,
          trailing: OutlinedButton.icon(
            key: const ValueKey('system-settings-reset'),
            onPressed: _resetToDefaults,
            style: OutlinedButton.styleFrom(
              foregroundColor: fg,
              backgroundColor: cardBg,
              side: BorderSide(color: borderColor),
              shape: const StadiumBorder(),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              visualDensity: VisualDensity.compact,
            ),
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: const Text(
              'Reset default',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
            ),
          ),
          child: _LivePreviewWorkspace(
            appearance: _appearance,
            accent: _accent,
            sidebarFinish: _sidebarFinish,
            displayComfort: _displayComfort,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),

        // 2. Workspace Appearance card.
        _SystemCard(
          title: 'WORKSPACE APPEARANCE',
          subtitle: 'Choose the background and surface contrast for this device.',
          cardBg: cardBg,
          borderColor: borderColor,
          fg: fg,
          muted: muted,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final cards = [
                for (final mode in AppAppearanceMode.values)
                  _AppearanceOptionCard(
                    mode: mode,
                    accent: accent,
                    selected: _appearance == mode,
                    softBg: softBg,
                    borderColor: borderColor,
                    fg: fg,
                    muted: muted,
                    onTap: () => _updateDraft(() => _appearance = mode),
                  ),
              ];
              if (constraints.maxWidth >= 560) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < cards.length; i++) ...[
                      if (i > 0) const SizedBox(width: AppSpacing.md),
                      Expanded(child: cards[i]),
                    ],
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < cards.length; i++) ...[
                    if (i > 0) const SizedBox(height: AppSpacing.md),
                    cards[i],
                  ],
                ],
              );
            },
          ),
        ),
        const SizedBox(height: AppSpacing.lg),

        // 3. Accent Palette card.
        _SystemCard(
          title: 'ACCENT PALETTE',
          subtitle:
              'Customize highlights, active navigation markers, buttons, and focus rings.',
          cardBg: cardBg,
          borderColor: borderColor,
          fg: fg,
          muted: muted,
          child: Wrap(
            spacing: AppSpacing.sm + 2,
            runSpacing: AppSpacing.sm + 2,
            children: [
              for (final palette in AppAccentPalette.values)
                _AccentPill(
                  palette: palette,
                  selected: _accent == palette,
                  softBg: softBg,
                  borderColor: borderColor,
                  fg: fg,
                  onTap: () => _updateDraft(() => _accent = palette),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),

        // 4. Navigation Sidebar card.
        _SystemCard(
          title: 'NAVIGATION SIDEBAR',
          subtitle:
              'Pick the chrome finish for the left navigation bar on this screen.',
          cardBg: cardBg,
          borderColor: borderColor,
          fg: fg,
          muted: muted,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final cards = [
                for (final finish in SidebarFinish.values)
                  _SidebarFinishCard(
                    finish: finish,
                    accent: accent,
                    selected: _sidebarFinish == finish,
                    softBg: softBg,
                    borderColor: borderColor,
                    fg: fg,
                    muted: muted,
                    onTap: () => _updateDraft(() => _sidebarFinish = finish),
                  ),
              ];
              if (constraints.maxWidth >= 560) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < cards.length; i++) ...[
                      if (i > 0) const SizedBox(width: AppSpacing.md),
                      Expanded(child: cards[i]),
                    ],
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < cards.length; i++) ...[
                    if (i > 0) const SizedBox(height: AppSpacing.md),
                    cards[i],
                  ],
                ],
              );
            },
          ),
        ),
        const SizedBox(height: AppSpacing.lg),

        // 5. Display Comfort card.
        _SystemCard(
          title: 'DISPLAY COMFORT',
          subtitle: 'Adjust interface text sizing for this monitor or screen.',
          cardBg: cardBg,
          borderColor: borderColor,
          fg: fg,
          muted: muted,
          child: Wrap(
            spacing: AppSpacing.sm + 2,
            runSpacing: AppSpacing.sm + 2,
            children: [
              for (final comfort in DisplayComfort.values)
                _DisplayComfortChip(
                  comfort: comfort,
                  accent: accent,
                  isGoldAccent: _accent == AppAccentPalette.gold,
                  selected: _displayComfort == comfort,
                  softBg: softBg,
                  borderColor: borderColor,
                  fg: fg,
                  muted: muted,
                  onTap: () => _updateDraft(() => _displayComfort = comfort),
                ),
            ],
          ),
        ),

        // Reserve bottom space when floating bar is visible so last card isn't covered.
        if (hasChanges) const SizedBox(height: 84),
      ],
    );
  }
}

class _FloatingSaveBar extends StatelessWidget {
  const _FloatingSaveBar({
    required this.accent,
    required this.saving,
    required this.onCancel,
    required this.onSave,
  });

  final AppAccentPalette accent;
  final bool saving;
  final VoidCallback onCancel;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final onAccent = accent.onPrimary;

    return Positioned(
      left: AppSpacing.lg,
      right: AppSpacing.lg,
      bottom: AppSpacing.xl,
      child: Center(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          builder: (context, t, child) => Opacity(
            opacity: t,
            child: Transform.translate(
              offset: Offset(0, (1 - t) * 20),
              child: child,
            ),
          ),
          child: Material(
            key: const ValueKey('system-settings-floating-bar'),
            color: const Color(0xFF141311),
            elevation: 12,
            shadowColor: Colors.black.withValues(alpha: 0.35),
            borderRadius: AppRadii.xlAll,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 560),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              decoration: BoxDecoration(
                borderRadius: AppRadii.xlAll,
                border: Border.all(
                  color: accent.primary.withValues(alpha: 0.45),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: accent.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Flexible(
                    child: Text(
                      'Unsaved theme changes',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 20),
                  TextButton(
                    key: const ValueKey('system-settings-cancel'),
                    onPressed: saving ? null : onCancel,
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFFD6D3D1),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                    ),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    key: const ValueKey('system-settings-save'),
                    onPressed: saving ? null : onSave,
                    style: FilledButton.styleFrom(
                      backgroundColor: accent.primary,
                      foregroundColor: onAccent,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                    ),
                    child: saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text(
                            'Save changes',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SystemCard extends StatelessWidget {
  const _SystemCard({
    required this.title,
    this.subtitle,
    this.trailing,
    required this.cardBg,
    required this.borderColor,
    required this.fg,
    required this.muted,
    required this.child,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Color cardBg;
  final Color borderColor;
  final Color fg;
  final Color muted;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: AppRadii.xlAll,
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontFamily: AppFonts.display,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                    color: fg,
                  ),
                ),
              ),
              ?trailing,
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              subtitle!,
              style: TextStyle(fontSize: 13, height: 1.4, color: muted),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          child,
        ],
      ),
    );
  }
}

class _LivePreviewWorkspace extends StatelessWidget {
  const _LivePreviewWorkspace({
    required this.appearance,
    required this.accent,
    required this.sidebarFinish,
    required this.displayComfort,
  });

  final AppAppearanceMode appearance;
  final AppAccentPalette accent;
  final SidebarFinish sidebarFinish;
  final DisplayComfort displayComfort;

  @override
  Widget build(BuildContext context) {
    final isDarkPreview = appearance == AppAppearanceMode.dark;
    final canvasBg = switch (appearance) {
      AppAppearanceMode.warm => const Color(0xFFF8F6F0),
      AppAppearanceMode.light => const Color(0xFFF6F7F9),
      AppAppearanceMode.dark => const Color(0xFF121110),
    };
    final innerCardBg =
        isDarkPreview ? const Color(0xFF1C1B19) : Colors.white;
    final previewBorder =
        isDarkPreview ? const Color(0xFF32302B) : const Color(0xFFDED5C0);
    final previewFg = isDarkPreview ? Colors.white : AppColors.textPrimary;
    final previewMuted =
        isDarkPreview ? const Color(0xFFB5AFA3) : AppColors.textSecondary;
    final accentColor = accent.primary;
    final finish = sidebarFinish;
    final btnFg = accent.onPrimary;

    return Container(
      key: const ValueKey('system-settings-preview'),
      decoration: BoxDecoration(
        color: canvasBg,
        borderRadius: AppRadii.lgAll,
        border: Border.all(color: previewBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Miniature sidebar.
            Container(
              width: 104,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: finish.background,
                border: Border(right: BorderSide(color: finish.divider)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(5),
                          border: Border.all(
                            color: finish.text.withValues(alpha: 0.45),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Container(
                          height: 6,
                          decoration: BoxDecoration(
                            color: finish.selectedText.withValues(alpha: 0.7),
                            borderRadius: AppRadii.pillAll,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: accentColor.withValues(alpha: 0.55),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 3,
                          height: 10,
                          decoration: BoxDecoration(
                            color: accentColor,
                            borderRadius: AppRadii.pillAll,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Container(
                            height: 5,
                            decoration: BoxDecoration(
                              color: finish.isDark
                                  ? Colors.white.withValues(alpha: 0.85)
                                  : const Color(0xFF5D4B1D),
                              borderRadius: AppRadii.pillAll,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Container(
                      width: 52,
                      height: 5,
                      decoration: BoxDecoration(
                        color: finish.text.withValues(alpha: 0.45),
                        borderRadius: AppRadii.pillAll,
                      ),
                    ),
                  ),
                  const SizedBox(height: 7),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Container(
                      width: 40,
                      height: 5,
                      decoration: BoxDecoration(
                        color: finish.text.withValues(alpha: 0.35),
                        borderRadius: AppRadii.pillAll,
                      ),
                    ),
                  ),
                  const Spacer(),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: finish.raised,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: finish.divider),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(radius: 5, backgroundColor: accentColor),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Container(
                            height: 4,
                            decoration: BoxDecoration(
                              color: finish.text.withValues(alpha: 0.55),
                              borderRadius: AppRadii.pillAll,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Miniature workspace area.
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(height: 2.5, color: accentColor),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 3,
                          height: 14,
                          decoration: BoxDecoration(
                            color: accentColor,
                            borderRadius: AppRadii.pillAll,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${appearance.label.toUpperCase()} · ${accent.label.toUpperCase()}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: AppFonts.display,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                              color: previewFg,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: isDarkPreview
                                ? const Color(0xFF282622)
                                : const Color(0xFFEDE7D9),
                            borderRadius: AppRadii.pillAll,
                            border: Border.all(color: previewBorder),
                          ),
                          child: Text(
                            displayComfort.percentLabel,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: previewMuted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Divider(height: 1, color: previewBorder),
                  Padding(
                    padding: const EdgeInsets.all(14),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 16,
                      ),
                      decoration: BoxDecoration(
                        color: innerCardBg,
                        borderRadius: AppRadii.mdAll,
                        border: Border.all(color: previewBorder),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Queen Builders Workspace',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: previewFg,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Cards, inputs, headers, and accents update live.',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: previewMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: accentColor,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'Primary',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: btnFg,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AppearanceOptionCard extends StatelessWidget {
  const _AppearanceOptionCard({
    required this.mode,
    required this.accent,
    required this.selected,
    required this.softBg,
    required this.borderColor,
    required this.fg,
    required this.muted,
    required this.onTap,
  });

  final AppAppearanceMode mode;
  final Color accent;
  final bool selected;
  final Color softBg;
  final Color borderColor;
  final Color fg;
  final Color muted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final mockOuter = switch (mode) {
      AppAppearanceMode.warm => const Color(0xFFF6F1E6),
      AppAppearanceMode.light => const Color(0xFFF1F4F8),
      AppAppearanceMode.dark => const Color(0xFF141311),
    };
    final mockInner = switch (mode) {
      AppAppearanceMode.warm => Colors.white,
      AppAppearanceMode.light => Colors.white,
      AppAppearanceMode.dark => const Color(0xFF201E1B),
    };
    final mockBorder = switch (mode) {
      AppAppearanceMode.warm => const Color(0xFFDED5C0),
      AppAppearanceMode.light => const Color(0xFFD6DCE5),
      AppAppearanceMode.dark => const Color(0xFF34312C),
    };

    return Material(
      color: selected ? accent.withValues(alpha: 0.08) : softBg,
      borderRadius: AppRadii.lgAll,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadii.lgAll,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: AppRadii.lgAll,
            border: Border.all(
              color: selected ? accent : borderColor,
              width: selected ? 1.8 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Mini window graphic.
              Container(
                height: 46,
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: mockOuter,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: mockBorder),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 14,
                      decoration: BoxDecoration(
                        color: const Color(0xFF0A0A09),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: mockInner,
                          borderRadius: BorderRadius.circular(5),
                          border: Border.all(color: mockBorder),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 34,
                              height: 4,
                              decoration: BoxDecoration(
                                color: accent,
                                borderRadius: AppRadii.pillAll,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Container(
                              width: 56,
                              height: 4,
                              decoration: BoxDecoration(
                                color: mode == AppAppearanceMode.dark
                                    ? const Color(0xFF5A554C)
                                    : const Color(0xFFBCB6AA),
                                borderRadius: AppRadii.pillAll,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      mode.label,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: fg,
                      ),
                    ),
                  ),
                  if (selected) _CheckBadge(color: accent, onColor: _accentOn(accent)),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                mode.description,
                style: TextStyle(fontSize: 12, height: 1.35, color: muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AccentPill extends StatelessWidget {
  const _AccentPill({
    required this.palette,
    required this.selected,
    required this.softBg,
    required this.borderColor,
    required this.fg,
    required this.onTap,
  });

  final AppAccentPalette palette;
  final bool selected;
  final Color softBg;
  final Color borderColor;
  final Color fg;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? palette.primary.withValues(alpha: 0.12) : softBg,
      shape: const StadiumBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const StadiumBorder(),
        child: Container(
          padding: const EdgeInsets.fromLTRB(8, 7, 14, 7),
          decoration: ShapeDecoration(
            shape: StadiumBorder(
              side: BorderSide(
                color: selected ? palette.primary : borderColor,
                width: selected ? 1.6 : 1,
              ),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: palette.primary,
                  shape: BoxShape.circle,
                ),
                child: selected
                    ? Icon(
                        Icons.check_rounded,
                        size: 13,
                        color: palette.onPrimary,
                      )
                    : null,
              ),
              const SizedBox(width: 8),
              Text(
                palette.label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SidebarFinishCard extends StatelessWidget {
  const _SidebarFinishCard({
    required this.finish,
    required this.accent,
    required this.selected,
    required this.softBg,
    required this.borderColor,
    required this.fg,
    required this.muted,
    required this.onTap,
  });

  final SidebarFinish finish;
  final Color accent;
  final bool selected;
  final Color softBg;
  final Color borderColor;
  final Color fg;
  final Color muted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? accent.withValues(alpha: 0.08) : softBg,
      borderRadius: AppRadii.lgAll,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadii.lgAll,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: AppRadii.lgAll,
            border: Border.all(
              color: selected ? accent : borderColor,
              width: selected ? 1.8 : 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 24,
                height: 38,
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 7),
                decoration: BoxDecoration(
                  color: finish.background,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: finish.divider),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      height: 3,
                      decoration: BoxDecoration(
                        color: accent,
                        borderRadius: AppRadii.pillAll,
                      ),
                    ),
                    Container(
                      height: 3,
                      decoration: BoxDecoration(
                        color: finish.text.withValues(alpha: 0.55),
                        borderRadius: AppRadii.pillAll,
                      ),
                    ),
                    Container(
                      height: 3,
                      decoration: BoxDecoration(
                        color: finish.text.withValues(alpha: 0.4),
                        borderRadius: AppRadii.pillAll,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            finish.label,
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: fg,
                            ),
                          ),
                        ),
                        if (selected) _CheckBadge(color: accent, onColor: _accentOn(accent)),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      finish.description,
                      style: TextStyle(fontSize: 12, height: 1.35, color: muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DisplayComfortChip extends StatelessWidget {
  const _DisplayComfortChip({
    required this.comfort,
    required this.accent,
    required this.isGoldAccent,
    required this.selected,
    required this.softBg,
    required this.borderColor,
    required this.fg,
    required this.muted,
    required this.onTap,
  });

  final DisplayComfort comfort;
  final Color accent;
  final bool isGoldAccent;
  final bool selected;
  final Color softBg;
  final Color borderColor;
  final Color fg;
  final Color muted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final selectedFg = isGoldAccent ? AppColors.brandBlack : Colors.white;
    return Material(
      color: selected ? accent : softBg,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: selected ? accent : borderColor),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                comfort.label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: selected ? selectedFg : fg,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                comfort.percentLabel,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: selected
                      ? selectedFg.withValues(alpha: 0.78)
                      : muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CheckBadge extends StatelessWidget {
  const _CheckBadge({required this.color, required this.onColor});

  final Color color;
  final Color onColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: Icon(Icons.check_rounded, size: 12, color: onColor),
    );
  }
}

Color _accentOn(Color bg) =>
    ThemeData.estimateBrightnessForColor(bg) == Brightness.light
    ? AppColors.brandBlack
    : Colors.white;

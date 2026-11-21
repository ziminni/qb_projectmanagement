import 'package:flutter/material.dart';

import 'local_settings_store.dart';

enum AppAppearanceMode {
  warm(
    'warm',
    'Warm Cream',
    'Signature Queen Builders parchment workspace',
  ),
  light(
    'light',
    'Crisp Daylight',
    'High-contrast bright canvas for sunny rooms',
  ),
  dark(
    'dark',
    'Obsidian Dark',
    'Low-glare dark workspace for dim rooms and night shifts',
  );

  const AppAppearanceMode(this.key, this.label, this.description);
  final String key;
  final String label;
  final String description;

  static AppAppearanceMode fromKey(Object? raw) => values.firstWhere(
    (v) => v.key == raw,
    orElse: () => AppAppearanceMode.warm,
  );
}

enum AppAccentPalette {
  gold(
    'gold',
    'Queen Brass',
    Color(0xFFAC934F),
    Color(0xFFE1C684),
    Color(0xFF050505),
    Color(0xFF6E5A22),
  ),
  amber(
    'amber',
    'Copper Amber',
    Color(0xFFB86B1F),
    Color(0xFFF3C48B),
    Colors.white,
    Color(0xFF8C4C0E),
  ),
  blue(
    'blue',
    'Blueprint Blue',
    Color(0xFF2E6DA8),
    Color(0xFFA8CCE8),
    Colors.white,
    Color(0xFF1F5385),
  ),
  emerald(
    'emerald',
    'Workshop Green',
    Color(0xFF247A5A),
    Color(0xFF9FD9C2),
    Colors.white,
    Color(0xFF196146),
  ),
  crimson(
    'crimson',
    'Crimson Forge',
    Color(0xFFA63A3A),
    Color(0xFFEAB0B0),
    Colors.white,
    Color(0xFF852828),
  );

  const AppAccentPalette(
    this.key,
    this.label,
    this.primary,
    this.light,
    this.onPrimary,
    this.onLightSurface,
  );
  final String key;
  final String label;
  final Color primary;
  final Color light;

  /// High-contrast foreground color for text/icons placed on [primary].
  final Color onPrimary;

  /// High-contrast accent text/icon color for light surfaces.
  final Color onLightSurface;

  static AppAccentPalette fromKey(Object? raw) => values.firstWhere(
    (v) => v.key == raw,
    orElse: () => AppAccentPalette.gold,
  );
}

enum SidebarFinish {
  obsidian(
    'obsidian',
    'Obsidian Chrome',
    'Signature deep-black navigation rail',
    Color(0xFF050505),
    Color(0xFF141311),
    Color(0xFFBDB6A6),
    Colors.white,
    Color(0xFF262420),
  ),
  charcoal(
    'charcoal',
    'Graphite Slate',
    'Softer dark charcoal navigation rail',
    Color(0xFF1C1917),
    Color(0xFF292524),
    Color(0xFFD6D3D1),
    Colors.white,
    Color(0xFF3F3A36),
  ),
  ivory(
    'ivory',
    'Matching Light',
    'Bright navigation surface on light workspaces',
    Color(0xFFFBF9F4),
    Color(0xFFEFEAE0),
    Color(0xFF57534E),
    Color(0xFF050505),
    Color(0xFFDED5C0),
  );

  const SidebarFinish(
    this.key,
    this.label,
    this.description,
    this.background,
    this.raised,
    this.text,
    this.selectedText,
    this.divider,
  );

  final String key;
  final String label;
  final String description;
  final Color background;
  final Color raised;
  final Color text;
  final Color selectedText;
  final Color divider;

  bool get isDark => this != SidebarFinish.ivory;

  static SidebarFinish fromKey(Object? raw) => values.firstWhere(
    (v) => v.key == raw,
    orElse: () => SidebarFinish.obsidian,
  );
}

enum DisplayComfort {
  compact('compact', 'Compact', '94%', 0.94, VisualDensity.compact),
  standard('standard', 'Standard', '100%', 1.0, VisualDensity.standard),
  comfortable(
    'comfortable',
    'Comfortable',
    '108%',
    1.08,
    VisualDensity(horizontal: 0.5, vertical: 0.5),
  );

  const DisplayComfort(
    this.key,
    this.label,
    this.percentLabel,
    this.textScale,
    this.density,
  );

  final String key;
  final String label;
  final String percentLabel;
  final double textScale;
  final VisualDensity density;

  static DisplayComfort fromKey(Object? raw) => values.firstWhere(
    (v) => v.key == raw,
    orElse: () => DisplayComfort.standard,
  );
}

/// Local-device System Settings and Sidebar state.
class LocalSettingsService extends ChangeNotifier {
  LocalSettingsService({LocalSettingsStore? store})
    : _store = store ?? createDefaultLocalSettingsStore();

  final LocalSettingsStore _store;

  AppAppearanceMode _appearance = AppAppearanceMode.warm;
  AppAccentPalette _accent = AppAccentPalette.gold;
  SidebarFinish _sidebarFinish = SidebarFinish.obsidian;
  DisplayComfort _displayComfort = DisplayComfort.standard;

  /// Defaults to collapsed (icon rail) when no saved preference exists.
  bool _sidebarCollapsed = true;

  AppAppearanceMode get appearance => _appearance;
  AppAccentPalette get accent => _accent;
  SidebarFinish get sidebarFinish => _sidebarFinish;
  DisplayComfort get displayComfort => _displayComfort;
  bool get sidebarCollapsed => _sidebarCollapsed;

  Future<void> load() async {
    final data = await _store.read();
    if (data == null) return;
    _appearance = AppAppearanceMode.fromKey(data['appearance']);
    _accent = AppAccentPalette.fromKey(data['accent']);
    _sidebarFinish = SidebarFinish.fromKey(data['sidebar_finish']);
    _displayComfort = DisplayComfort.fromKey(data['display_comfort']);
    _sidebarCollapsed = data['sidebar_collapsed'] as bool? ?? true;
    notifyListeners();
  }

  Future<void> _persist() => _store.write({
    'appearance': _appearance.key,
    'accent': _accent.key,
    'sidebar_finish': _sidebarFinish.key,
    'display_comfort': _displayComfort.key,
    'sidebar_collapsed': _sidebarCollapsed,
  });

  Future<void> setAppearance(AppAppearanceMode value) async {
    if (_appearance == value) return;
    _appearance = value;
    notifyListeners();
    await _persist();
  }

  Future<void> setAccent(AppAccentPalette value) async {
    if (_accent == value) return;
    _accent = value;
    notifyListeners();
    await _persist();
  }

  Future<void> setSidebarFinish(SidebarFinish value) async {
    if (_sidebarFinish == value) return;
    _sidebarFinish = value;
    notifyListeners();
    await _persist();
  }

  Future<void> setDisplayComfort(DisplayComfort value) async {
    if (_displayComfort == value) return;
    _displayComfort = value;
    notifyListeners();
    await _persist();
  }

  Future<void> applySystemSettings({
    required AppAppearanceMode appearance,
    required AppAccentPalette accent,
    required SidebarFinish sidebarFinish,
    required DisplayComfort displayComfort,
  }) async {
    if (_appearance == appearance &&
        _accent == accent &&
        _sidebarFinish == sidebarFinish &&
        _displayComfort == displayComfort) {
      return;
    }
    _appearance = appearance;
    _accent = accent;
    _sidebarFinish = sidebarFinish;
    _displayComfort = displayComfort;
    notifyListeners();
    await _persist();
  }

  Future<void> resetSystemDefaults() async {
    _appearance = AppAppearanceMode.warm;
    _accent = AppAccentPalette.gold;
    _sidebarFinish = SidebarFinish.obsidian;
    _displayComfort = DisplayComfort.standard;
    notifyListeners();
    await _persist();
  }

  Future<void> setSidebarCollapsed(bool value) async {
    if (_sidebarCollapsed == value) return;
    _sidebarCollapsed = value;
    notifyListeners();
    await _persist();
  }

  Future<void> toggleSidebar() => setSidebarCollapsed(!_sidebarCollapsed);
}

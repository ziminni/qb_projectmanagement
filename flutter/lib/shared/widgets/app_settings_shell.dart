import 'package:flutter/material.dart';

import '../../core/constants/app_radii.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/theme/app_motion.dart';
import '../../core/utils/page_padding.dart';
import 'app_page_header.dart';

class AppSettingsTab {
  const AppSettingsTab({
    required this.slug,
    required this.label,
    required this.icon,
    required this.group,
    required this.builder,
  });

  final String slug;
  final String label;
  final IconData icon;
  final String group;
  final WidgetBuilder builder;
}

/// GitHub-style settings shell with grouped side tabs on wide screens and
/// filter chips on narrow screens, matching the admin Settings layout.
class AppSettingsShell extends StatelessWidget {
  const AppSettingsShell({
    super.key,
    required this.title,
    required this.subtitle,
    required this.tabs,
    required this.currentSlug,
    required this.onSelect,
  });

  final String title;
  final String subtitle;
  final List<AppSettingsTab> tabs;
  final String? currentSlug;
  final ValueChanged<AppSettingsTab> onSelect;

  AppSettingsTab get _current => tabs.firstWhere(
    (t) => t.slug == currentSlug,
    orElse: () => tabs.first,
  );

  @override
  Widget build(BuildContext context) {
    final current = _current;
    final wide = MediaQuery.sizeOf(context).width >= AppSpacing.wideBreakpoint;
    final content = AnimatedSwitcher(
      duration: AppMotion.medium,
      switchInCurve: AppMotion.switchIn,
      switchOutCurve: AppMotion.switchOut,
      layoutBuilder: (currentChild, previousChildren) => Stack(
        alignment: Alignment.topLeft,
        children: [...previousChildren, ?currentChild],
      ),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween(
            begin: const Offset(0, 0.01),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
      ),
      child: KeyedSubtree(
        key: ValueKey(current.slug),
        child: current.builder(context),
      ),
    );

    return ListView(
      padding: pagePadding(context),
      children: [
        AppPageHeader(title: title, subtitle: subtitle),
        if (wide)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 248,
                child: _SideTabs(tabs: tabs, current: current, onSelect: onSelect),
              ),
              const SizedBox(width: AppSpacing.xxl),
              Expanded(child: content),
            ],
          )
        else ...[
          _TopTabs(tabs: tabs, current: current, onSelect: onSelect),
          const SizedBox(height: AppSpacing.xl),
          content,
        ],
      ],
    );
  }
}

class _SideTabs extends StatelessWidget {
  const _SideTabs({
    required this.tabs,
    required this.current,
    required this.onSelect,
  });

  final List<AppSettingsTab> tabs;
  final AppSettingsTab current;
  final ValueChanged<AppSettingsTab> onSelect;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final children = <Widget>[];
    String? group;
    for (final s in tabs) {
      if (s.group != group) {
        group = s.group;
        children.add(
          Padding(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.md,
              children.isEmpty ? 0 : AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.xs,
            ),
            child: Text(
              s.group.toUpperCase(),
              style: textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                letterSpacing: 0.8,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        );
      }
      children.add(
        _SideTab(tab: s, selected: s.slug == current.slug, onTap: () => onSelect(s)),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }
}

class _SideTab extends StatelessWidget {
  const _SideTab({
    required this.tab,
    required this.selected,
    required this.onTap,
  });

  final AppSettingsTab tab;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final selectedBg = cs.primary.withValues(alpha: isDark ? 0.18 : 0.14);
    final selectedIconColor = isDark ? cs.secondary : cs.onPrimaryContainer;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Material(
        color: Colors.transparent,
        borderRadius: AppRadii.mdAll,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadii.mdAll,
          hoverColor: cs.surfaceContainerHighest,
          child: AnimatedContainer(
            duration: AppMotion.medium,
            curve: AppMotion.enter,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm + 2,
            ),
            decoration: BoxDecoration(
              color: selected ? selectedBg : selectedBg.withValues(alpha: 0),
              borderRadius: AppRadii.mdAll,
              border: Border(
                left: BorderSide(
                  color: selected
                      ? cs.primary
                      : cs.primary.withValues(alpha: 0),
                  width: 3,
                ),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  tab.icon,
                  size: 18,
                  color: selected ? selectedIconColor : cs.onSurfaceVariant,
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    tab.label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected ? cs.onSurface : cs.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TopTabs extends StatelessWidget {
  const _TopTabs({
    required this.tabs,
    required this.current,
    required this.onSelect,
  });

  final List<AppSettingsTab> tabs;
  final AppSettingsTab current;
  final ValueChanged<AppSettingsTab> onSelect;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final s in tabs)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.sm),
              child: ChoiceChip(
                avatar: Icon(s.icon, size: 16),
                label: Text(s.label),
                selected: s.slug == current.slug,
                onSelected: (_) => onSelect(s),
              ),
            ),
        ],
      ),
    );
  }
}

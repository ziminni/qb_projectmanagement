import 'package:flutter/material.dart';

import '../../data/services/local_settings_service.dart';
import '../constants/app_fonts.dart';
import '../constants/app_radii.dart';
import '../constants/app_spacing.dart';

/// One destination in [AppSidebar], matching the Queen Builders hardware
/// sidebar: a 42px ListTile row when expanded, or a 44px icon-only rail button
/// with tooltip + top-right count badge when [compact], with an animated 3px
/// gradient [_ActiveBar] on the selected item.
class AppSidebarItem extends StatefulWidget {
  const AppSidebarItem({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.compact,
    required this.onTap,
    this.finish = SidebarFinish.obsidian,
    this.accent = AppAccentPalette.gold,
    this.badgeCount = 0,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final bool compact;
  final VoidCallback onTap;
  final SidebarFinish finish;
  final AppAccentPalette accent;
  final int badgeCount;

  @override
  State<AppSidebarItem> createState() => _AppSidebarItemState();
}

class _AppSidebarItemState extends State<AppSidebarItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    final compact = widget.compact;
    final finish = widget.finish;
    final accent = widget.accent;
    final badgeCount = widget.badgeCount;
    final isLight = !finish.isDark;

    final selectedFill = isLight
        ? accent.primary.withValues(alpha: 0.14)
        : accent.primary.withValues(alpha: 0.14);
    final selectedBorder = isLight
        ? accent.primary.withValues(alpha: 0.45)
        : accent.primary.withValues(alpha: 0.32);
    final hoverFill = isLight
        ? accent.primary.withValues(alpha: 0.08)
        : Colors.white.withValues(alpha: 0.05);
    final activeTextColor = isLight ? accent.onLightSurface : accent.light;
    final foreground = selected
        ? activeTextColor
        : _hovered
        ? finish.selectedText
        : finish.text;
    final iconColor = selected
        ? activeTextColor
        : _hovered
        ? (isLight
              ? accent.onLightSurface
              : accent.light.withValues(alpha: 0.9))
        : finish.text.withValues(alpha: 0.88);

    if (compact) {
      return MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Tooltip(
                message: widget.label,
                preferBelow: false,
                child: Material(
                  color: selected ? selectedFill : Colors.transparent,
                  shape: RoundedRectangleBorder(
                    borderRadius: AppRadii.mdAll,
                    side: selected
                        ? BorderSide(color: selectedBorder)
                        : _hovered
                        ? BorderSide(
                            color: finish.divider.withValues(alpha: 0.9),
                          )
                        : BorderSide.none,
                  ),
                  child: InkWell(
                    borderRadius: AppRadii.mdAll,
                    onTap: widget.onTap,
                    hoverColor: hoverFill,
                    child: SizedBox(
                      height: 44,
                      child: Center(
                        child: Icon(widget.icon, size: 20, color: iconColor),
                      ),
                    ),
                  ),
                ),
              ),
              if (selected) _ActiveBar(inset: 9, accent: accent),
              if (badgeCount > 0)
                Positioned(
                  top: -3,
                  right: -2,
                  child: _MarkerCount(
                    count: badgeCount,
                    accent: accent,
                    sidebarBg: finish.background,
                    onRail: true,
                  ),
                ),
            ],
          ),
        ),
      );
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Stack(
          children: [
            Material(
              color: selected ? selectedFill : Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: AppRadii.mdAll,
                side: selected
                    ? BorderSide(color: selectedBorder)
                    : BorderSide.none,
              ),
              child: ListTile(
                dense: true,
                selected: selected,
                selectedColor: activeTextColor,
                selectedTileColor: Colors.transparent,
                hoverColor: hoverFill,
                minTileHeight: 42,
                shape: const RoundedRectangleBorder(
                  borderRadius: AppRadii.mdAll,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                ),
                horizontalTitleGap: 11,
                leading: Icon(widget.icon, size: 18, color: iconColor),
                title: Text(
                  widget.label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: AppFonts.body,
                    fontSize: 13,
                    color: foreground,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
                trailing: badgeCount > 0
                    ? _MarkerCount(
                        count: badgeCount,
                        accent: accent,
                        sidebarBg: finish.background,
                      )
                    : null,
                onTap: widget.onTap,
              ),
            ),
            if (selected) _ActiveBar(inset: 9, accent: accent),
          ],
        ),
      ),
    );
  }
}

/// The 3px vertical gradient accent bar on the left edge of the selected item.
class _ActiveBar extends StatelessWidget {
  const _ActiveBar({required this.inset, required this.accent});

  final double inset;
  final AppAccentPalette accent;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      top: inset,
      bottom: inset,
      child: IgnorePointer(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 3),
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          builder: (context, width, _) => Container(
            width: width,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [accent.light, accent.primary],
              ),
              borderRadius: BorderRadius.circular(2),
              boxShadow: [
                BoxShadow(
                  color: accent.primary.withValues(alpha: 0.4),
                  blurRadius: 6,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MarkerCount extends StatelessWidget {
  const _MarkerCount({
    required this.count,
    required this.accent,
    required this.sidebarBg,
    this.onRail = false,
  });

  final int count;
  final AppAccentPalette accent;
  final Color sidebarBg;
  final bool onRail;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 20),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
      decoration: BoxDecoration(
        color: accent.primary,
        borderRadius: AppRadii.pillAll,
        border: onRail ? Border.all(color: sidebarBg, width: 1.5) : null,
      ),
      child: Text(
        '$count',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontFamily: AppFonts.body,
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: accent.onPrimary,
          height: 1.2,
        ),
      ),
    );
  }
}

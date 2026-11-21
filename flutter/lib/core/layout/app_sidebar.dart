import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data/models/app_role.dart';
import '../../data/models/progress_billing.dart';
import '../../data/models/user.dart';
import '../../data/models/variation_order.dart';
import '../../data/repositories/billing_repository.dart';
import '../../data/repositories/project_repository.dart';
import '../../data/services/approval_inbox.dart';
import '../../data/services/local_settings_service.dart';
import '../../data/services/notification_preferences_service.dart';
import '../../data/services/notification_service.dart';
import '../../features/auth/widgets/profile_dialog.dart';
import '../../routes/routes.dart';
import '../../shared/widgets/qb_logo.dart';
import '../constants/app_fonts.dart';
import '../constants/app_radii.dart';
import '../constants/app_spacing.dart';
import '../di/service_locator.dart';
import 'app_sidebar_item.dart';
import 'app_top_bar.dart';
import 'role_navigation.dart';

/// The navigation sidebar matching the Queen Builders hardware shell:
/// faint blueprint grid + warm top glow, 72px brand header with 38x38 logo
/// tile and 1.5px gradient hairline, accent-dashed section headings, pinned
/// Settings row, and expanded hexagon / collapsed ringed user footer.
class AppSidebar extends StatefulWidget {
  const AppSidebar({
    super.key,
    required this.destinations,
    required this.selected,
    required this.onSelect,
    required this.user,
    required this.role,
    this.compact = false,
    this.finish = SidebarFinish.obsidian,
    this.accent = AppAccentPalette.gold,
    this.onExpand,
    this.onCollapse,
    this.onSignOut,
  });

  final List<RoleDestination> destinations;
  final int selected;
  final ValueChanged<int> onSelect;
  final User user;
  final AppRole role;
  final bool compact;
  final SidebarFinish finish;
  final AppAccentPalette accent;
  final VoidCallback? onExpand;
  final VoidCallback? onCollapse;
  final VoidCallback? onSignOut;

  static const fullWidth = 260.0;
  static const compactWidth = 76.0;

  @override
  State<AppSidebar> createState() => _AppSidebarState();
}

class _AppSidebarState extends State<AppSidebar> {
  final _prefs = getIt<NotificationPreferencesService>();
  final _notifications = getIt<NotificationService>();
  Map<String, int> _badges = const {};

  @override
  void initState() {
    super.initState();
    _prefs.addListener(_onChanged);
    _notifications.addListener(_onChanged);
    _refreshBadges();
  }

  @override
  void didUpdateWidget(AppSidebar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.role != widget.role ||
        oldWidget.user.id != widget.user.id ||
        oldWidget.selected != widget.selected) {
      _refreshBadges();
    }
  }

  @override
  void dispose() {
    _prefs.removeListener(_onChanged);
    _notifications.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() => _refreshBadges();

  Future<void> _refreshBadges() async {
    if (!_prefs.showSidebarRequestBadges) {
      if (_badges.isNotEmpty && mounted) setState(() => _badges = const {});
      return;
    }
    if (widget.role == AppRole.owner) {
      try {
        final items = await getIt<ApprovalInbox>().pendingFor(
          widget.user.id,
          widget.role,
        );
        final materialRequests = items
            .where((i) => i.kind == ApprovalKind.materialRequest)
            .length;
        if (!mounted) return;
        setState(() {
          _badges = {
            AppRoutes.approvals: items.length,
            AppRoutes.requestQueue: materialRequests,
          };
        });
      } catch (_) {
        // Keep existing counts on transient load errors.
      }
      return;
    }
    if (widget.role == AppRole.client) {
      try {
        final projects = await getIt<ProjectRepository>().getProjectsFor(
          widget.user.id,
          AppRole.client,
        );
        final projectIds = projects.map((p) => p.id).toList();
        if (projectIds.isEmpty) {
          if (_badges.isNotEmpty && mounted) setState(() => _badges = const {});
          return;
        }
        final billing = getIt<BillingRepository>();
        final results = await Future.wait([
          billing.getVariationOrders(
            projectIds: projectIds,
            statuses: const [VariationOrderStatus.pendingClient],
          ),
          billing.getBillings(
            projectIds: projectIds,
            statuses: const [BillingStatus.pendingClient],
          ),
        ]);
        final pendingVos = (results[0] as List<VariationOrder>).length;
        final pendingBillings = (results[1] as List<ProgressBilling>).length;
        if (!mounted) return;
        setState(() {
          _badges = {
            AppRoutes.clientVariationOrders: pendingVos,
            AppRoutes.clientBillings: pendingBillings,
          };
        });
      } catch (_) {
        // Keep existing counts on transient load errors.
      }
      return;
    }
    if (_badges.isNotEmpty && mounted) setState(() => _badges = const {});
  }

  @override
  Widget build(BuildContext context) {
    final compact = widget.compact;
    final destinations = widget.destinations;
    final selected = widget.selected;
    final user = widget.user;
    final role = widget.role;
    final onSelect = widget.onSelect;
    final finish = widget.finish;
    final accent = widget.accent;
    final settingsIndex = destinations.indexWhere(
      (d) => d.path == AppRoutes.settings || d.path == AppRoutes.adminSettings,
    );
    final mainIndices = [
      for (var i = 0; i < destinations.length; i++)
        if (i != settingsIndex) i,
    ];
    final headingAccent = finish.isDark
        ? accent.primary.withValues(alpha: 0.85)
        : accent.onLightSurface;

    return ClipRect(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeInOutCubic,
        width: compact ? AppSidebar.compactWidth : AppSidebar.fullWidth,
        decoration: BoxDecoration(
          color: finish.background,
          border: Border(right: BorderSide(color: finish.divider)),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final showCompact = compact || constraints.maxWidth < 180;
            return Material(
              color: finish.background,
              child: SafeArea(
                right: false,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Faint architectural blueprint grid + warm glow.
                    IgnorePointer(
                      child: RepaintBoundary(
                        child: CustomPaint(
                          painter: _SidebarGridPainter(
                            accent: accent.primary,
                            isLight: !finish.isDark,
                          ),
                        ),
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _SidebarBrandHeader(
                          collapsed: showCompact,
                          roleLabel: role.label,
                          finish: finish,
                          accent: accent,
                          onExpand: widget.onExpand,
                          onCollapse: widget.onCollapse,
                        ),
                        Expanded(
                          child: GestureDetector(
                            key: const ValueKey('sidebar-free-space'),
                            behavior: HitTestBehavior.translucent,
                            onTap: compact ? widget.onExpand : null,
                            child: ScrollConfiguration(
                              behavior: ScrollConfiguration.of(
                                context,
                              ).copyWith(scrollbars: false),
                              child: ListView(
                                padding: showCompact
                                    ? const EdgeInsets.symmetric(
                                        horizontal: AppSpacing.md,
                                        vertical: AppSpacing.md,
                                      )
                                    : const EdgeInsets.symmetric(
                                        horizontal: AppSpacing.md,
                                        vertical: AppSpacing.lg,
                                      ),
                                children: [
                                  for (
                                    var pos = 0;
                                    pos < mainIndices.length;
                                    pos++
                                  ) ...[
                                    if (destinations[mainIndices[pos]].group !=
                                            null &&
                                        (pos == 0 ||
                                            destinations[mainIndices[pos - 1]]
                                                    .group !=
                                                destinations[mainIndices[pos]]
                                                    .group))
                                      showCompact
                                          ? (pos == 0
                                                ? const SizedBox.shrink()
                                                : Padding(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          vertical:
                                                              AppSpacing.sm,
                                                        ),
                                                    child: Divider(
                                                      height: 1,
                                                      color: finish.divider,
                                                    ),
                                                  ))
                                          : _GroupHeading(
                                              destinations[mainIndices[pos]]
                                                  .group!,
                                              first: pos == 0,
                                              color: headingAccent,
                                            ),
                                    AppSidebarItem(
                                      icon: destinations[mainIndices[pos]].icon,
                                      label:
                                          destinations[mainIndices[pos]].label,
                                      selected: mainIndices[pos] == selected,
                                      compact: showCompact,
                                      finish: finish,
                                      accent: accent,
                                      badgeCount:
                                          _prefs.showSidebarRequestBadges
                                          ? (_badges[destinations[mainIndices[pos]]
                                                    .path] ??
                                                0)
                                          : 0,
                                      onTap: () => onSelect(mainIndices[pos]),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                        if (settingsIndex != -1) ...[
                          Divider(color: finish.divider, height: 1),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(
                              AppSpacing.md,
                              AppSpacing.sm,
                              AppSpacing.md,
                              AppSpacing.xs,
                            ),
                            child: AppSidebarItem(
                              key: const ValueKey('sidebar-pinned-settings'),
                              icon: destinations[settingsIndex].icon,
                              label: destinations[settingsIndex].label,
                              selected: settingsIndex == selected,
                              compact: showCompact,
                              finish: finish,
                              accent: accent,
                              onTap: () => onSelect(settingsIndex),
                            ),
                          ),
                        ],
                        Divider(color: finish.divider, height: 1),
                        _SidebarUserFooter(
                          user: user,
                          role: role,
                          compact: showCompact,
                          finish: finish,
                          accent: accent,
                          onSignOut: widget.onSignOut,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _SidebarBrandHeader extends StatelessWidget {
  const _SidebarBrandHeader({
    required this.collapsed,
    required this.roleLabel,
    required this.finish,
    required this.accent,
    this.onExpand,
    this.onCollapse,
  });

  final bool collapsed;
  final String roleLabel;
  final SidebarFinish finish;
  final AppAccentPalette accent;
  final VoidCallback? onExpand;
  final VoidCallback? onCollapse;

  @override
  Widget build(BuildContext context) {
    final logoTile = Container(
      width: 38,
      height: 38,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: AppRadii.smAll,
        border: Border.all(color: accent.primary.withValues(alpha: 0.48)),
      ),
      child: Image.asset(
        QbLogo.asset,
        width: 30,
        height: 30,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
        semanticLabel: 'Queen Builders logo',
      ),
    );

    final brandContent = Padding(
      padding: EdgeInsets.symmetric(
        horizontal: collapsed ? 4 : 6,
        vertical: 4,
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: collapsed ? Alignment.center : Alignment.centerLeft,
        child: collapsed
            ? logoTile
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  logoTile,
                  const SizedBox(width: 10),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'QUEEN BUILDERS',
                        style: TextStyle(
                          fontFamily: AppFonts.display,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: finish.selectedText,
                          letterSpacing: 0.75,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        roleLabel.toUpperCase(),
                        style: TextStyle(
                          fontFamily: AppFonts.body,
                          color: finish.text,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.65,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
      ),
    );

    final Widget interactiveBrand = collapsed
        ? Tooltip(
            message: 'Expand sidebar',
            child: Material(
              color: Colors.transparent,
              borderRadius: AppRadii.mdAll,
              child: InkWell(
                key: const ValueKey('sidebar-logo-expand'),
                onTap: onExpand,
                borderRadius: AppRadii.mdAll,
                hoverColor: accent.primary.withValues(alpha: 0.14),
                child: brandContent,
              ),
            ),
          )
        : brandContent;

    return Container(
      height: AppTopBar.height,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            finish.raised.withValues(alpha: 0.95),
            finish.background,
          ],
        ),
      ),
      child: Column(
        children: [
          Expanded(
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: collapsed ? 8 : AppSpacing.sm + 2,
              ),
              child: collapsed
                  ? Align(alignment: Alignment.center, child: interactiveBrand)
                  : Row(
                      children: [
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: interactiveBrand,
                          ),
                        ),
                        if (onCollapse != null) ...[
                          const SizedBox(width: 6),
                          _ChromeIconButton(
                            key: const ValueKey('sidebar-collapse-btn'),
                            tooltip: 'Collapse sidebar',
                            icon: Icons.chevron_left_rounded,
                            finish: finish,
                            accent: accent,
                            onPressed: onCollapse!,
                          ),
                        ],
                      ],
                    ),
            ),
          ),
          // Architectural accent hairline anchoring the brand header.
          Container(
            height: 1.5,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  accent.primary.withValues(alpha: 0.65),
                  finish.divider,
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarUserFooter extends StatelessWidget {
  const _SidebarUserFooter({
    required this.user,
    required this.role,
    required this.compact,
    required this.finish,
    required this.accent,
    this.onSignOut,
  });

  final User user;
  final AppRole role;
  final bool compact;
  final SidebarFinish finish;
  final AppAccentPalette accent;
  final VoidCallback? onSignOut;

  @override
  Widget build(BuildContext context) {
    final name = user.fullName.trim().isEmpty ? user.email : user.fullName;
    final initials = _initials(name);
    final onAccent = accent.onPrimary;
    final activeTextColor = finish.isDark ? accent.light : accent.onLightSurface;

    if (compact) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Tooltip(
              message: '$name · ${role.label}',
              child: InkWell(
                onTap: () => showProfileDialog(context),
                customBorder: const CircleBorder(),
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: accent.primary.withValues(alpha: 0.5),
                      width: 1,
                    ),
                  ),
                  child: CircleAvatar(
                    radius: 16,
                    backgroundColor: finish.raised,
                    foregroundColor: activeTextColor,
                    child: Text(
                      initials,
                      style: TextStyle(
                        fontFamily: AppFonts.display,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: activeTextColor,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            if (onSignOut != null)
              _ChromeIconButton(
                icon: Icons.logout_rounded,
                tooltip: 'Log out',
                finish: finish,
                accent: accent,
                onPressed: onSignOut!,
              ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Material(
        color: Colors.transparent,
        child: ListTile(
          tileColor: finish.raised,
          shape: RoundedRectangleBorder(
            borderRadius: AppRadii.mdAll,
            side: BorderSide(color: finish.divider),
          ),
          contentPadding: const EdgeInsets.fromLTRB(10, 2, 6, 2),
          horizontalTitleGap: 10,
          onTap: () => showProfileDialog(context),
          leading: ClipPath(
            clipper: const HexagonClipper(),
            child: Container(
              width: 36,
              height: 36,
              color: accent.primary,
              alignment: Alignment.center,
              child: Text(
                initials,
                style: TextStyle(
                  fontFamily: 'Outfit',
                  fontFamilyFallback: const [
                    AppFonts.body,
                    ...AppFonts.fallback,
                  ],
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: onAccent,
                ),
              ),
            ),
          ),
          title: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: finish.selectedText,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              height: 1.25,
            ),
          ),
          subtitle: Text(
            role.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: finish.text,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              height: 1.3,
            ),
          ),
          trailing: onSignOut == null
              ? null
              : _ChromeIconButton(
                  icon: Icons.logout_rounded,
                  tooltip: 'Log out',
                  finish: finish,
                  accent: accent,
                  onPressed: onSignOut!,
                ),
        ),
      ),
    );
  }
}

class _ChromeIconButton extends StatelessWidget {
  const _ChromeIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.finish,
    required this.accent,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final SidebarFinish finish;
  final AppAccentPalette accent;
  final VoidCallback onPressed;

  static const double _size = 32;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _size,
      height: _size,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: _size, height: _size),
        style: IconButton.styleFrom(
          backgroundColor: finish.raised,
          foregroundColor: finish.text,
          hoverColor: accent.primary.withValues(alpha: 0.14),
          shape: RoundedRectangleBorder(
            borderRadius: AppRadii.smAll,
            side: BorderSide(color: finish.divider),
          ),
        ),
        icon: Icon(icon, size: 17),
      ),
    );
  }
}

class _SidebarGridPainter extends CustomPainter {
  const _SidebarGridPainter({required this.accent, required this.isLight});

  final Color accent;
  final bool isLight;

  static const double _minorStep = 28;
  static const double _majorStep = _minorStep * 5;

  @override
  void paint(Canvas canvas, Size size) {
    final glowRect = Rect.fromCircle(
      center: Offset(size.width * 0.2, 48),
      radius: size.width * 1.15,
    );
    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          accent.withValues(alpha: isLight ? 0.05 : 0.08),
          Colors.transparent,
        ],
      ).createShader(glowRect);
    canvas.drawRect(Offset.zero & size, glowPaint);

    final opacity = isLight ? 0.28 : 0.48;
    final minor = Paint()
      ..color = accent.withValues(alpha: 0.05 * opacity)
      ..strokeWidth = 1;
    final major = Paint()
      ..color = accent.withValues(alpha: 0.11 * opacity)
      ..strokeWidth = 1;

    for (double x = 0; x <= size.width; x += _minorStep) {
      final paint = x % _majorStep == 0 ? major : minor;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y <= size.height; y += _minorStep) {
      final paint = y % _majorStep == 0 ? major : minor;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SidebarGridPainter oldDelegate) =>
      oldDelegate.accent != accent || oldDelegate.isLight != isLight;
}

class HexagonClipper extends CustomClipper<Path> {
  const HexagonClipper();

  @override
  Path getClip(Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = math.min(cx, cy);
    final path = Path();
    for (var i = 0; i < 6; i++) {
      final angle = (math.pi / 3) * i - (math.pi / 2);
      final x = cx + r * math.cos(angle);
      final y = cy + r * math.sin(angle);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

String _initials(String name) {
  final parts = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((p) => p.isNotEmpty)
      .toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) {
    final word = parts.first;
    return word.substring(0, math.min(2, word.length)).toUpperCase();
  }
  return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
}

class _GroupHeading extends StatelessWidget {
  const _GroupHeading(this.label, {required this.first, required this.color});
  final String label;
  final bool first;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        10,
        first ? 0 : AppSpacing.md + 2,
        10,
        AppSpacing.sm,
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 1.5,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(1),
            ),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              label.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: AppFonts.body,
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

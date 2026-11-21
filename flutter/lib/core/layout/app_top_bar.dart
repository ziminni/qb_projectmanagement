import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/services/local_settings_service.dart';
import '../../data/services/session_service.dart';
import '../constants/app_colors.dart';
import '../constants/app_fonts.dart';
import '../constants/app_radii.dart';
import '../constants/app_spacing.dart';
import 'app_notification_button.dart';
import 'role_navigation.dart';

/// The title the shell's header is showing, so a page's own header can
/// skip repeating it.
class AppShellTitle extends InheritedWidget {
  const AppShellTitle({super.key, required this.title, required super.child});

  final String title;

  static String? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppShellTitle>()?.title;

  @override
  bool updateShouldNotify(AppShellTitle old) => old.title != title;
}

/// The shell's header, matching the Queen Builders hardware shell:
/// 2px top accent gradient, vertical accent bar + Cinzel title & subtitle,
/// date pill, vertical divider, Notifications pill, and 6px bottom MeasureRuler.
class AppTopBar extends StatelessWidget implements PreferredSizeWidget {
  const AppTopBar({
    super.key,
    required this.session,
    required this.current,
    required this.eyebrow,
    required this.isNested,
    required this.wide,
  });

  final SessionService session;
  final RoleDestination current;

  /// Small context line under the title.
  final String eyebrow;
  final bool isNested;
  final bool wide;

  static const height = 72.0;

  @override
  Size get preferredSize => const Size.fromHeight(height);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final accent = context.watch<LocalSettingsService>().accent;
    final subtitle = _subtitleFor(current.label, eyebrow);
    final hasSubtitle = subtitle.isNotEmpty;

    return Material(
      color: cs.surface,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: height,
          child: Column(
            children: [
              // Thin signature accent edge.
              Container(
                height: 2,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      accent.primary,
                      accent.light,
                      accent.primary.withValues(alpha: 0.25),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: wide ? AppSpacing.xl : AppSpacing.md,
                  ),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final showDatePill = wide && constraints.maxWidth >= 640;
                      return Row(
                        children: [
                          if (!wide) ...[
                            SizedBox(
                              width: 38,
                              height: 38,
                              child: IconButton(
                                tooltip: 'Open navigation menu',
                                onPressed: () =>
                                    Scaffold.of(context).openDrawer(),
                                padding: EdgeInsets.zero,
                                style: IconButton.styleFrom(
                                  backgroundColor: isDark
                                      ? cs.surfaceContainer
                                      : AppColors.surfaceSunken,
                                  foregroundColor: cs.onSurface,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: AppRadii.smAll,
                                    side: BorderSide(color: cs.outlineVariant),
                                  ),
                                ),
                                icon: const Icon(Icons.menu_rounded, size: 20),
                              ),
                            ),
                            const SizedBox(width: AppSpacing.md),
                          ],
                          Container(
                            width: 3.5,
                            height: hasSubtitle ? 32 : 22,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(2),
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [accent.primary, accent.light],
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  current.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontFamily: AppFonts.display,
                                    fontSize: wide ? 19 : 16.5,
                                    fontWeight: FontWeight.w700,
                                    color: cs.onSurface,
                                    letterSpacing: 0.35,
                                    height: 1.15,
                                  ),
                                ),
                                if (hasSubtitle) ...[
                                  const SizedBox(height: 1),
                                  Text(
                                    subtitle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontFamily: AppFonts.body,
                                      fontSize: 12,
                                      color: cs.onSurfaceVariant,
                                      height: 1.25,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          if (showDatePill) ...[
                            const SizedBox(width: AppSpacing.md),
                            _HeaderDatePill(accent: accent, isDark: isDark),
                            const SizedBox(width: AppSpacing.md),
                            Container(
                              width: 1,
                              height: 22,
                              color: cs.outlineVariant,
                            ),
                            const SizedBox(width: AppSpacing.md),
                          ] else
                            const SizedBox(width: AppSpacing.sm),
                          AppNotificationButton(
                            userId: session.user!.id,
                            compact: !wide,
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
              // Tape-measure signature edge.
              Container(
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: cs.outlineVariant.withValues(alpha: 0.7),
                    ),
                  ),
                ),
                child: _MeasureRuler(height: 6, color: accent.primary),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _subtitleFor(String label, String eyebrow) {
    switch (label.toLowerCase()) {
      case 'dashboard':
        return 'Track active projects, schedules, and approvals.';
      case 'approvals':
        return 'Review and act on pending project items.';
      case 'my projects':
      case 'my sites':
        return 'Monitor project progress, schedules, and site status.';
      case 'purchasing':
        return 'Manage material requests, purchase orders, and deliveries.';
      case 'billing':
      case 'billings and payments':
      case 'billings':
        return 'Track progress billings, collections, and statements.';
      case 'variation orders':
        return 'Review scope changes and revised contract amounts.';
      case 'user management':
        return 'Manage staff directory, roles, and access permissions.';
      case 'audit log':
        return 'Track approvals, orders, deliveries, payments, and admin changes.';
      case 'system health':
        return 'Monitor database status, storage usage, and POS sync outbox.';
      case 'backups':
        return 'Create verified snapshots, download archives, and manage retention.';
      case 'security':
        return 'Monitor active sessions, login attempts, and security policies.';
      case 'settings':
        return 'Configure workspace and device preferences.';
      default:
        return eyebrow;
    }
  }
}

class _HeaderDatePill extends StatelessWidget {
  const _HeaderDatePill({required this.accent, required this.isDark});

  final AppAccentPalette accent;
  final bool isDark;

  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final formatted =
        '${_weekdays[now.weekday - 1]}, ${_months[now.month - 1]} ${now.day}, ${now.year}';
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: isDark ? cs.surfaceContainer : AppColors.surfaceSunken,
        borderRadius: AppRadii.pillAll,
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.calendar_today_outlined,
            size: 13.5,
            color: isDark ? accent.light : accent.onLightSurface,
          ),
          const SizedBox(width: 7),
          Text(
            formatted,
            maxLines: 1,
            style: TextStyle(
              fontFamily: AppFonts.body,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: cs.onSurface,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

/// Tape-measure style tick marks along the bottom edge of the header.
class _MeasureRuler extends StatelessWidget {
  const _MeasureRuler({required this.height, required this.color});

  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(painter: _RulerPainter(color)),
    );
  }
}

class _RulerPainter extends CustomPainter {
  const _RulerPainter(this.color);

  final Color color;
  static const double _step = 8;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.55)
      ..strokeWidth = 1;

    canvas.drawLine(Offset.zero, Offset(size.width, 0), paint);

    var index = 0;
    for (double x = 0; x <= size.width; x += _step, index++) {
      final length = index % 10 == 0
          ? size.height
          : index % 5 == 0
          ? size.height * 0.6
          : size.height * 0.3;
      canvas.drawLine(Offset(x, 0), Offset(x, length), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _RulerPainter oldDelegate) =>
      oldDelegate.color != color;
}

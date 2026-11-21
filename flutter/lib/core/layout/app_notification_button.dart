import 'package:flutter/material.dart';

import '../../data/services/notification_preferences_service.dart';
import '../../data/services/notification_service.dart';
import '../../features/dashboard/widgets/notifications_dialog.dart';
import '../constants/app_fonts.dart';
import '../constants/app_radii.dart';
import '../di/service_locator.dart';

/// App bar Notifications pill button with live unread count for [userId].
class AppNotificationButton extends StatefulWidget {
  const AppNotificationButton({
    super.key,
    required this.userId,
    this.compact = false,
  });

  final int userId;
  final bool compact;

  @override
  State<AppNotificationButton> createState() => _AppNotificationButtonState();
}

class _AppNotificationButtonState extends State<AppNotificationButton> {
  final _service = getIt<NotificationService>();
  final _prefs = getIt<NotificationPreferencesService>();
  int _unread = 0;

  @override
  void initState() {
    super.initState();
    _service.addListener(_refresh);
    _prefs.addListener(_onPrefsChanged);
    _refresh();
  }

  @override
  void didUpdateWidget(AppNotificationButton old) {
    super.didUpdateWidget(old);
    if (old.userId != widget.userId) _refresh();
  }

  @override
  void dispose() {
    _service.removeListener(_refresh);
    _prefs.removeListener(_onPrefsChanged);
    super.dispose();
  }

  void _onPrefsChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _refresh() async {
    final count = await _service.unreadCount(widget.userId);
    if (mounted) setState(() => _unread = count);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final showBadge = _unread > 0 && _prefs.showBellBadge;
    final tooltip = _unread == 0
        ? 'Notifications'
        : '$_unread unread notifications';

    if (widget.compact) {
      return Tooltip(
        message: tooltip,
        child: Material(
          color: cs.surface,
          shape: RoundedRectangleBorder(
            borderRadius: AppRadii.pillAll,
            side: BorderSide(color: cs.outlineVariant),
          ),
          child: InkWell(
            onTap: () => showNotificationsDialog(context),
            borderRadius: AppRadii.pillAll,
            child: SizedBox(
              width: 36,
              height: 34,
              child: Center(
                child: Badge(
                  isLabelVisible: showBadge,
                  label: Text('$_unread'),
                  backgroundColor: cs.primary,
                  textColor: cs.onPrimary,
                  child: Icon(
                    Icons.notifications_none_rounded,
                    size: 18,
                    color: cs.onSurface,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Tooltip(
      message: tooltip,
      child: Material(
        color: cs.surface,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadii.pillAll,
          side: BorderSide(color: cs.outlineVariant),
        ),
        child: InkWell(
          onTap: () => showNotificationsDialog(context),
          borderRadius: AppRadii.pillAll,
          child: Container(
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 13),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.notifications_none_rounded,
                  size: 16,
                  color: cs.onSurface,
                ),
                const SizedBox(width: 7),
                Text(
                  'Notifications',
                  style: TextStyle(
                    fontFamily: AppFonts.body,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                    height: 1.2,
                  ),
                ),
                if (showBadge) ...[
                  const SizedBox(width: 7),
                  Container(
                    constraints: const BoxConstraints(minWidth: 18),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1.5,
                    ),
                    decoration: BoxDecoration(
                      color: cs.primary,
                      borderRadius: AppRadii.pillAll,
                    ),
                    child: Text(
                      '$_unread',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: AppFonts.body,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: cs.onPrimary,
                        height: 1.1,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

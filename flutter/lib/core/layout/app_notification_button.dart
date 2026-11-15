import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/services/notification_service.dart';
import '../../routes/routes.dart';
import '../di/service_locator.dart';

/// App bar bell with the unread count for [userId].
class AppNotificationButton extends StatefulWidget {
  const AppNotificationButton({super.key, required this.userId});

  final int userId;

  @override
  State<AppNotificationButton> createState() => _AppNotificationButtonState();
}

class _AppNotificationButtonState extends State<AppNotificationButton> {
  final _service = getIt<NotificationService>();
  int _unread = 0;

  @override
  void initState() {
    super.initState();
    _service.addListener(_refresh);
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
    super.dispose();
  }

  Future<void> _refresh() async {
    final count = await _service.unreadCount(widget.userId);
    if (mounted) setState(() => _unread = count);
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: _unread == 0 ? 'Notifications' : '$_unread unread notifications',
      icon: Badge(
        isLabelVisible: _unread > 0,
        label: Text('$_unread'),
        child: const Icon(Icons.notifications_outlined),
      ),
      onPressed: () => context.go(AppRoutes.notifications),
    );
  }
}

import 'package:flutter/material.dart';

import '../../../core/utils/formatters.dart';
import '../../../data/models/app_notification.dart';

class DashboardNotificationTile extends StatelessWidget {
  const DashboardNotificationTile({
    super.key,
    required this.notification,
    required this.onTap,
  });

  final AppNotification notification;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final n = notification;
    return ListTile(
      onTap: onTap,
      leading: Icon(
        n.isRead ? Icons.notifications_none : Icons.notifications_active,
        color: n.isRead ? colors.onSurfaceVariant : colors.primary,
      ),
      title: Text(
        n.message,
        style: TextStyle(fontWeight: n.isRead ? null : FontWeight.w600),
      ),
      subtitle: n.createdAt == null
          ? null
          : Text(Formatters.dateTime(n.createdAt!.toLocal())),
      trailing: n.link == null ? null : const Icon(Icons.chevron_right),
    );
  }
}

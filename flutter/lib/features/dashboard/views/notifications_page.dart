import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/utils/page_padding.dart';
import '../../../shared/widgets/app_empty_state.dart';
import '../viewmodels/notifications_viewmodel.dart';
import '../widgets/dashboard_notification_tile.dart';

class NotificationsPage extends StatelessWidget {
  const NotificationsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => NotificationsViewModel(
        session: getIt(),
        notifications: getIt(),
        service: getIt(),
      )..load(),
      builder: (context, _) {
        final vm = context.watch<NotificationsViewModel>();
        if (vm.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        if (vm.items.isEmpty) {
          return const AppEmptyState(
            message: 'No notifications yet.',
            icon: Icons.notifications_none,
          );
        }
        return ListView(
          padding: pagePadding(context),
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: vm.hasUnread ? vm.markAllRead : null,
                icon: const Icon(Icons.done_all),
                label: const Text('Mark all as read'),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (final (i, n) in vm.items.indexed) ...[
                    if (i > 0) const Divider(height: 1),
                    DashboardNotificationTile(
                      notification: n,
                      onTap: () async {
                        await vm.markRead(n);
                        if (n.link != null && context.mounted) {
                          context.go(n.link!);
                        }
                      },
                    ),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

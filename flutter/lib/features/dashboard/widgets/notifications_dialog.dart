import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_radii.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/theme/app_motion.dart';
import '../../../shared/widgets/app_empty_state.dart';
import '../viewmodels/notifications_viewmodel.dart';
import 'dashboard_notification_tile.dart';

enum _NotificationFilter { all, unread, read }

/// Opens the notifications modal with All, Unread, and Read filters.
Future<void> showNotificationsDialog(BuildContext context) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close notifications',
    barrierColor: Colors.black.withValues(alpha: 0.45),
    transitionDuration: AppMotion.medium,
    pageBuilder: (_, _, _) => const _NotificationsDialog(),
    transitionBuilder: (context, animation, _, child) =>
        AppMotion.dialog(animation, child),
  );
}

class _NotificationsDialog extends StatefulWidget {
  const _NotificationsDialog();

  @override
  State<_NotificationsDialog> createState() => _NotificationsDialogState();
}

class _NotificationsDialogState extends State<_NotificationsDialog> {
  _NotificationFilter _filter = _NotificationFilter.all;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final phone = MediaQuery.sizeOf(context).width < 600;
    return ChangeNotifierProvider(
      create: (_) => NotificationsViewModel(
        session: getIt(),
        notifications: getIt(),
        service: getIt(),
      )..load(),
      child: Consumer<NotificationsViewModel>(
        builder: (context, vm, _) {
          final unread = vm.items.where((n) => !n.isRead).toList();
          final read = vm.items.where((n) => n.isRead).toList();
          final visible = switch (_filter) {
            _NotificationFilter.all => vm.items,
            _NotificationFilter.unread => unread,
            _NotificationFilter.read => read,
          };

          return Dialog(
            backgroundColor: AppColors.background,
            surfaceTintColor: Colors.transparent,
            insetPadding: EdgeInsets.symmetric(
              horizontal: phone ? AppSpacing.lg : AppSpacing.xxl,
              vertical: AppSpacing.xl,
            ),
            shape: const RoundedRectangleBorder(borderRadius: AppRadii.xlAll),
            clipBehavior: Clip.antiAlias,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640, maxHeight: 620),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    color: AppColors.surface,
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.xl,
                      AppSpacing.lg,
                      AppSpacing.sm,
                      AppSpacing.md,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Notifications',
                                style: textTheme.titleLarge,
                              ),
                            ),
                            if (vm.hasUnread)
                              TextButton.icon(
                                onPressed: vm.markAllRead,
                                icon: const Icon(Icons.done_all, size: 18),
                                label: const Text('Mark all as read'),
                              ),
                            IconButton(
                              tooltip: 'Close',
                              icon: const Icon(Icons.close),
                              onPressed: () => Navigator.of(context).pop(),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Wrap(
                          spacing: AppSpacing.sm,
                          children: [
                            ChoiceChip(
                              label: Text('All (${vm.items.length})'),
                              selected: _filter == _NotificationFilter.all,
                              onSelected: (_) => setState(
                                () => _filter = _NotificationFilter.all,
                              ),
                            ),
                            ChoiceChip(
                              label: Text('Unread (${unread.length})'),
                              selected: _filter == _NotificationFilter.unread,
                              onSelected: (_) => setState(
                                () => _filter = _NotificationFilter.unread,
                              ),
                            ),
                            ChoiceChip(
                              label: Text('Read (${read.length})'),
                              selected: _filter == _NotificationFilter.read,
                              onSelected: (_) => setState(
                                () => _filter = _NotificationFilter.read,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Flexible(
                    child: vm.isLoading
                        ? const Padding(
                            padding: EdgeInsets.all(AppSpacing.xxl),
                            child: Center(child: CircularProgressIndicator()),
                          )
                        : visible.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.all(AppSpacing.xl),
                            child: AppEmptyState(
                              message: switch (_filter) {
                                _NotificationFilter.all =>
                                  'No notifications yet.',
                                _NotificationFilter.unread =>
                                  'No unread notifications.',
                                _NotificationFilter.read =>
                                  'No read notifications.',
                              },
                              icon: Icons.notifications_none,
                            ),
                          )
                        : ListView.separated(
                            shrinkWrap: true,
                            itemCount: visible.length,
                            separatorBuilder: (_, _) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final n = visible[index];
                              return DashboardNotificationTile(
                                notification: n,
                                onTap: () async {
                                  final router = GoRouter.of(context);
                                  final nav = Navigator.of(context);
                                  await vm.markRead(n);
                                  nav.pop();
                                  if (n.link != null) {
                                    router.go(n.link!);
                                  }
                                },
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

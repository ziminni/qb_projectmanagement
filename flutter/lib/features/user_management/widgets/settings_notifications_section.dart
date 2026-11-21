import 'package:flutter/material.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/di/service_locator.dart';
import '../../../data/services/notification_preferences_service.dart';
import '../../../data/services/workspace_preferences_service.dart';
import '../../../shared/widgets/app_section_card.dart';
import 'settings_section_frame.dart';

class SettingsNotificationsSection extends StatefulWidget {
  const SettingsNotificationsSection({super.key});

  @override
  State<SettingsNotificationsSection> createState() =>
      _SettingsNotificationsSectionState();
}

class _SettingsNotificationsSectionState
    extends State<SettingsNotificationsSection> {
  final _prefs = getIt<NotificationPreferencesService>();
  final _workspace = getIt<WorkspacePreferencesService>();

  @override
  void initState() {
    super.initState();
    _prefs.addListener(_onChanged);
    _workspace.addListener(_onChanged);
  }

  @override
  void dispose() {
    _prefs.removeListener(_onChanged);
    _workspace.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return SettingsSectionFrame(
      title: 'Notifications',
      description:
          'Control request badges in the sidebar, header indicators, and event alert categories.',
      children: [
        AppSectionCard(
          title: 'Notification indicators',
          icon: Icons.notifications_outlined,
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              SwitchListTile(
                title: const Text('Sidebar request badges'),
                subtitle: const Text(
                  'Show pending request and approval counts in the sidebar for Project Managers.',
                ),
                value: _prefs.showSidebarRequestBadges,
                onChanged: _prefs.setShowSidebarRequestBadges,
              ),
              const Divider(height: 1),
              SwitchListTile(
                title: const Text('Header notification badge'),
                subtitle: const Text(
                  'Show the unread count badge on the top-bar notification bell.',
                ),
                value: _prefs.showBellBadge,
                onChanged: _prefs.setShowBellBadge,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        AppSectionCard(
          title: 'Event alerts',
          icon: Icons.filter_list_outlined,
          subtitle: 'Choose which project events surface in your feed',
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              SwitchListTile(
                title: const Text('Daily reports & site updates'),
                value: _workspace.notifyDailyReports,
                onChanged: (v) =>
                    _workspace.update(() => _workspace.notifyDailyReports = v),
              ),
              const Divider(height: 1),
              SwitchListTile(
                title: const Text('Material requests & approvals'),
                value: _workspace.notifyMaterialRequests,
                onChanged: (v) => _workspace.update(
                  () => _workspace.notifyMaterialRequests = v,
                ),
              ),
              const Divider(height: 1),
              SwitchListTile(
                title: const Text('Deliveries & receiving'),
                value: _workspace.notifyDeliveries,
                onChanged: (v) =>
                    _workspace.update(() => _workspace.notifyDeliveries = v),
              ),
              const Divider(height: 1),
              SwitchListTile(
                title: const Text('Progress billings & payments'),
                value: _workspace.notifyBillings,
                onChanged: (v) =>
                    _workspace.update(() => _workspace.notifyBillings = v),
              ),
              const Divider(height: 1),
              SwitchListTile(
                title: const Text('Variation orders'),
                value: _workspace.notifyVariationOrders,
                onChanged: (v) => _workspace.update(
                  () => _workspace.notifyVariationOrders = v,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

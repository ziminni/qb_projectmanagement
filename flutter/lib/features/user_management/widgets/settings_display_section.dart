import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/utils/app_messages.dart';
import '../../../data/models/app_role.dart';
import '../../../data/services/session_service.dart';
import '../../../data/services/workspace_preferences_service.dart';
import '../../../shared/widgets/app_section_card.dart';
import 'settings_section_frame.dart';

class SettingsDisplaySection extends StatefulWidget {
  const SettingsDisplaySection({super.key});

  @override
  State<SettingsDisplaySection> createState() => _SettingsDisplaySectionState();
}

class _SettingsDisplaySectionState extends State<SettingsDisplaySection> {
  final _prefs = getIt<WorkspacePreferencesService>();

  @override
  void initState() {
    super.initState();
    _prefs.addListener(_onChanged);
  }

  @override
  void dispose() {
    _prefs.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionService>();
    final heldRoles = session.roles;
    return SettingsSectionFrame(
      title: 'Display & startup',
      description:
          'Adjust list density, date formatting, and default workspace on sign-in.',
      children: [
        AppSectionCard(
          title: 'Interface preferences',
          icon: Icons.tune_outlined,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Compact list density'),
                subtitle: const Text(
                  'Show tighter row spacing in tables and lists.',
                ),
                value: _prefs.compactDensity,
                onChanged: (v) => _prefs.update(() => _prefs.compactDensity = v),
              ),
              const SizedBox(height: AppSpacing.md),
              DropdownButtonFormField<String>(
                key: ValueKey('date-${_prefs.dateFormat}'),
                initialValue: _prefs.dateFormat,
                decoration: const InputDecoration(labelText: 'Date format'),
                items: const [
                  DropdownMenuItem(
                    value: 'MMM d, yyyy',
                    child: Text('Nov 21, 2026 (MMM d, yyyy)'),
                  ),
                  DropdownMenuItem(
                    value: 'yyyy-MM-dd',
                    child: Text('2026-11-21 (ISO yyyy-MM-dd)'),
                  ),
                  DropdownMenuItem(
                    value: 'dd/MM/yyyy',
                    child: Text('21/11/2026 (dd/MM/yyyy)'),
                  ),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  _prefs.update(() => _prefs.dateFormat = v);
                  showAppMessage(context, 'Date format updated.');
                },
              ),
              if (heldRoles.length > 1) ...[
                const SizedBox(height: AppSpacing.md),
                DropdownButtonFormField<AppRole?>(
                  key: ValueKey('role-${_prefs.defaultStartupRole}'),
                  initialValue: heldRoles.contains(_prefs.defaultStartupRole)
                      ? _prefs.defaultStartupRole
                      : null,
                  decoration: const InputDecoration(
                    labelText: 'Default startup role',
                    helperText:
                        'Workspace to open automatically when you sign in.',
                  ),
                  items: [
                    const DropdownMenuItem<AppRole?>(
                      value: null,
                      child: Text('Ask me each time'),
                    ),
                    for (final r in heldRoles)
                      DropdownMenuItem<AppRole?>(
                        value: r,
                        child: Text(r.label),
                      ),
                  ],
                  onChanged: (v) {
                    _prefs.update(() => _prefs.defaultStartupRole = v);
                    showAppMessage(context, 'Startup role preference saved.');
                  },
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

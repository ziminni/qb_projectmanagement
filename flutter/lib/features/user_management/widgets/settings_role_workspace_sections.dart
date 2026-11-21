import 'package:flutter/material.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/utils/app_messages.dart';
import '../../../data/models/client.dart';
import '../../../data/models/project.dart';
import '../../../data/repositories/client_repository.dart';
import '../../../data/repositories/project_repository.dart';
import '../../../data/services/session_service.dart';
import '../../../data/services/workspace_preferences_service.dart';
import '../../../shared/widgets/app_info_row.dart';
import '../../../shared/widgets/app_section_card.dart';
import 'settings_section_frame.dart';

class SettingsPmPreferencesSection extends StatefulWidget {
  const SettingsPmPreferencesSection({super.key});

  @override
  State<SettingsPmPreferencesSection> createState() =>
      _SettingsPmPreferencesSectionState();
}

class _SettingsPmPreferencesSectionState
    extends State<SettingsPmPreferencesSection> {
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
    return SettingsSectionFrame(
      title: 'Project & procurement defaults',
      description:
          'Configure approval reminders, default project views, and purchasing defaults.',
      children: [
        AppSectionCard(
          title: 'Project & schedule view',
          icon: Icons.view_timeline_outlined,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<String>(
                key: ValueKey('pm-tab-${_prefs.defaultProjectTab}'),
                initialValue: _prefs.defaultProjectTab,
                decoration: const InputDecoration(
                  labelText: 'Default project tab',
                ),
                items: const [
                  DropdownMenuItem(value: 'overview', child: Text('Overview')),
                  DropdownMenuItem(value: 'schedule', child: Text('Schedule')),
                  DropdownMenuItem(value: 'gantt', child: Text('Gantt chart')),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  _prefs.update(() => _prefs.defaultProjectTab = v);
                  showAppMessage(context, 'Default project tab updated.');
                },
              ),
              const SizedBox(height: AppSpacing.md),
              DropdownButtonFormField<String>(
                key: ValueKey('pm-zoom-${_prefs.defaultGanttZoom}'),
                initialValue: _prefs.defaultGanttZoom,
                decoration: const InputDecoration(
                  labelText: 'Default Gantt zoom',
                ),
                items: const [
                  DropdownMenuItem(value: 'day', child: Text('Day')),
                  DropdownMenuItem(value: 'week', child: Text('Week')),
                  DropdownMenuItem(value: 'month', child: Text('Month')),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  _prefs.update(() => _prefs.defaultGanttZoom = v);
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        AppSectionCard(
          title: 'Approvals & procurement',
          icon: Icons.shopping_cart_outlined,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<String>(
                key: ValueKey('pm-po-${_prefs.defaultPoSource}'),
                initialValue: _prefs.defaultPoSource,
                decoration: const InputDecoration(
                  labelText: 'Default purchase order source',
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'own_store',
                    child: Text('Own store (POS)'),
                  ),
                  DropdownMenuItem(
                    value: 'external',
                    child: Text('External supplier'),
                  ),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  _prefs.update(() => _prefs.defaultPoSource = v);
                },
              ),
              const SizedBox(height: AppSpacing.md),
              DropdownButtonFormField<int>(
                key: ValueKey('pm-rem-${_prefs.approvalReminderDays}'),
                initialValue: _prefs.approvalReminderDays,
                decoration: const InputDecoration(
                  labelText: 'Approval reminder digest',
                  helperText:
                      'Highlight unverified to-dos, reports, and requests older than this.',
                ),
                items: const [
                  DropdownMenuItem(value: 1, child: Text('After 1 day')),
                  DropdownMenuItem(value: 3, child: Text('After 3 days')),
                  DropdownMenuItem(value: 7, child: Text('After 7 days')),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  _prefs.update(() => _prefs.approvalReminderDays = v);
                },
              ),
              const SizedBox(height: AppSpacing.sm),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Low-budget category alerts'),
                subtitle: const Text(
                  'Warn when a category purchase order nears its allocated budget.',
                ),
                value: _prefs.lowBudgetAlerts,
                onChanged: (v) =>
                    _prefs.update(() => _prefs.lowBudgetAlerts = v),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class SettingsForemanPreferencesSection extends StatefulWidget {
  const SettingsForemanPreferencesSection({super.key});

  @override
  State<SettingsForemanPreferencesSection> createState() =>
      _SettingsForemanPreferencesSectionState();
}

class _SettingsForemanPreferencesSectionState
    extends State<SettingsForemanPreferencesSection> {
  final _prefs = getIt<WorkspacePreferencesService>();
  late final Future<List<Project>> _projectsFuture =
      getIt<ProjectRepository>().getProjects();

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
    return SettingsSectionFrame(
      title: 'Site workspace & defaults',
      description:
          'Default assigned site, daily report presets, and photo upload quality.',
      children: [
        FutureBuilder<List<Project>>(
          future: _projectsFuture,
          builder: (context, snap) {
            final projects = snap.data ?? const [];
            final validId = projects.any(
              (p) => p.id == _prefs.defaultSiteProjectId,
            )
                ? _prefs.defaultSiteProjectId
                : null;
            return AppSectionCard(
              title: 'Daily report & site defaults',
              icon: Icons.edit_note_outlined,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DropdownButtonFormField<int?>(
                    key: ValueKey('site-$validId-${projects.length}'),
                    initialValue: validId,
                    decoration: const InputDecoration(
                      labelText: 'Default assigned site',
                      helperText:
                          'Pre-selected in Daily Reports, Attendance, and Material Requests.',
                    ),
                    items: [
                      const DropdownMenuItem<int?>(
                        value: null,
                        child: Text('Choose each time'),
                      ),
                      for (final p in projects)
                        DropdownMenuItem<int?>(
                          value: p.id,
                          child: Text(p.name),
                        ),
                    ],
                    onChanged: (v) =>
                        _prefs.update(() => _prefs.defaultSiteProjectId = v),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  DropdownButtonFormField<String>(
                    key: ValueKey('weather-${_prefs.defaultWeather}'),
                    initialValue: _prefs.defaultWeather,
                    decoration: const InputDecoration(
                      labelText: 'Default weather condition',
                    ),
                    items: const [
                      DropdownMenuItem(value: 'Sunny', child: Text('Sunny')),
                      DropdownMenuItem(value: 'Cloudy', child: Text('Cloudy')),
                      DropdownMenuItem(value: 'Rainy', child: Text('Rainy')),
                      DropdownMenuItem(value: 'Windy', child: Text('Windy')),
                    ],
                    onChanged: (v) {
                      if (v != null) {
                        _prefs.update(() => _prefs.defaultWeather = v);
                      }
                    },
                  ),
                  const SizedBox(height: AppSpacing.md),
                  DropdownButtonFormField<String>(
                    key: ValueKey('photo-${_prefs.photoQuality}'),
                    initialValue: _prefs.photoQuality,
                    decoration: const InputDecoration(
                      labelText: 'Site photo upload quality',
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'standard',
                        child: Text('Standard (faster upload)'),
                      ),
                      DropdownMenuItem(
                        value: 'high',
                        child: Text('High detail'),
                      ),
                    ],
                    onChanged: (v) {
                      if (v != null) {
                        _prefs.update(() => _prefs.photoQuality = v);
                      }
                    },
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Remind missing daily report'),
                    value: _prefs.remindMissingDailyReport,
                    onChanged: (v) => _prefs.update(
                      () => _prefs.remindMissingDailyReport = v,
                    ),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Remind missing attendance'),
                    value: _prefs.remindMissingAttendance,
                    onChanged: (v) =>
                        _prefs.update(() => _prefs.remindMissingAttendance = v),
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: AppSpacing.lg),
        const AppSectionCard(
          title: 'Field permissions',
          icon: Icons.construction_outlined,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppInfoRow(label: 'Project scope', value: 'Assigned sites only'),
              AppInfoRow(
                label: 'Financial visibility',
                value: 'Hidden on field accounts',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class SettingsAccountantPreferencesSection extends StatefulWidget {
  const SettingsAccountantPreferencesSection({super.key});

  @override
  State<SettingsAccountantPreferencesSection> createState() =>
      _SettingsAccountantPreferencesSectionState();
}

class _SettingsAccountantPreferencesSectionState
    extends State<SettingsAccountantPreferencesSection> {
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
    return SettingsSectionFrame(
      title: 'Payroll, billing & reports',
      description:
          'Configure payroll cycle defaults, overdue billing alerts, and expense report grouping.',
      children: [
        AppSectionCard(
          title: 'Payroll & billing alerts',
          icon: Icons.payments_outlined,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<String>(
                key: ValueKey('pay-${_prefs.defaultPayrollCycle}'),
                initialValue: _prefs.defaultPayrollCycle,
                decoration: const InputDecoration(
                  labelText: 'Default payroll period length',
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'semi_monthly',
                    child: Text('Semi-monthly (15 days)'),
                  ),
                  DropdownMenuItem(
                    value: 'weekly',
                    child: Text('Weekly (7 days)'),
                  ),
                ],
                onChanged: (v) {
                  if (v != null) {
                    _prefs.update(() => _prefs.defaultPayrollCycle = v);
                  }
                },
              ),
              const SizedBox(height: AppSpacing.md),
              DropdownButtonFormField<int>(
                key: ValueKey('overdue-${_prefs.overdueBillingDays}'),
                initialValue: _prefs.overdueBillingDays,
                decoration: const InputDecoration(
                  labelText: 'Highlight overdue billings after',
                ),
                items: const [
                  DropdownMenuItem(value: 7, child: Text('7 days unpaid')),
                  DropdownMenuItem(value: 15, child: Text('15 days unpaid')),
                  DropdownMenuItem(value: 30, child: Text('30 days unpaid')),
                ],
                onChanged: (v) {
                  if (v != null) {
                    _prefs.update(() => _prefs.overdueBillingDays = v);
                  }
                },
              ),
              const SizedBox(height: AppSpacing.sm),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Retention release milestone alerts'),
                value: _prefs.retentionMilestoneAlerts,
                onChanged: (v) =>
                    _prefs.update(() => _prefs.retentionMilestoneAlerts = v),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        AppSectionCard(
          title: 'Expense report preferences',
          icon: Icons.summarize_outlined,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<String>(
                key: ValueKey('exp-${_prefs.expenseGrouping}'),
                initialValue: _prefs.expenseGrouping,
                decoration: const InputDecoration(
                  labelText: 'Default report grouping',
                ),
                items: const [
                  DropdownMenuItem(value: 'project', child: Text('By project')),
                  DropdownMenuItem(
                    value: 'category',
                    child: Text('By category'),
                  ),
                ],
                onChanged: (v) {
                  if (v != null) {
                    _prefs.update(() => _prefs.expenseGrouping = v);
                  }
                },
              ),
              const SizedBox(height: AppSpacing.sm),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Include draft items in previews'),
                value: _prefs.includeDraftsInPreview,
                onChanged: (v) =>
                    _prefs.update(() => _prefs.includeDraftsInPreview = v),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class SettingsClientPreferencesSection extends StatefulWidget {
  const SettingsClientPreferencesSection({super.key});

  @override
  State<SettingsClientPreferencesSection> createState() =>
      _SettingsClientPreferencesSectionState();
}

class _SettingsClientPreferencesSectionState
    extends State<SettingsClientPreferencesSection> {
  final _prefs = getIt<WorkspacePreferencesService>();
  late final Future<Client?> _clientFuture = _loadClient();

  Future<Client?> _loadClient() async {
    final userId = getIt<SessionService>().user?.id;
    if (userId == null) return null;
    try {
      return await getIt<ClientRepository>().getClientForUser(userId);
    } catch (_) {
      return null;
    }
  }

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
    return SettingsSectionFrame(
      title: 'Portal & statement preferences',
      description:
          'Choose project update alerts, statement format, and review your billing contact.',
      children: [
        AppSectionCard(
          title: 'Project update alerts',
          icon: Icons.notifications_active_outlined,
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              SwitchListTile(
                title: const Text('Progress milestones'),
                value: _prefs.alertProgressMilestones,
                onChanged: (v) =>
                    _prefs.update(() => _prefs.alertProgressMilestones = v),
              ),
              const Divider(height: 1),
              SwitchListTile(
                title: const Text('New approved site photos'),
                value: _prefs.alertApprovedPhotos,
                onChanged: (v) =>
                    _prefs.update(() => _prefs.alertApprovedPhotos = v),
              ),
              const Divider(height: 1),
              SwitchListTile(
                title: const Text('New progress billings'),
                value: _prefs.alertNewBillings,
                onChanged: (v) =>
                    _prefs.update(() => _prefs.alertNewBillings = v),
              ),
              const Divider(height: 1),
              SwitchListTile(
                title: const Text('Variation orders awaiting signature'),
                value: _prefs.alertVariationOrders,
                onChanged: (v) =>
                    _prefs.update(() => _prefs.alertVariationOrders = v),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        AppSectionCard(
          title: 'Billing statement format',
          icon: Icons.receipt_long_outlined,
          child: DropdownButtonFormField<String>(
            key: ValueKey('stmt-${_prefs.statementFormat}'),
            initialValue: _prefs.statementFormat,
            decoration: const InputDecoration(
              labelText: 'Preferred statement layout',
            ),
            items: const [
              DropdownMenuItem(
                value: 'itemized',
                child: Text('Itemized breakdown'),
              ),
              DropdownMenuItem(value: 'summary', child: Text('Summary view')),
            ],
            onChanged: (v) {
              if (v != null) {
                _prefs.update(() => _prefs.statementFormat = v);
              }
            },
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        FutureBuilder<Client?>(
          future: _clientFuture,
          builder: (context, snap) {
            final client = snap.data;
            if (client == null) return const SizedBox.shrink();
            return AppSectionCard(
              title: 'Linked billing contact',
              icon: Icons.badge_outlined,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppInfoRow(label: 'Client', value: client.name),
                  if ((client.contactPerson ?? '').isNotEmpty)
                    AppInfoRow(
                      label: 'Contact person',
                      value: client.contactPerson!,
                    ),
                  if ((client.email ?? '').isNotEmpty)
                    AppInfoRow(label: 'Email', value: client.email!),
                  if ((client.address ?? '').isNotEmpty)
                    AppInfoRow(label: 'Address', value: client.address!),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

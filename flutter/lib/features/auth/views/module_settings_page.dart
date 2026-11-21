import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/utils/app_messages.dart';
import '../../../data/models/app_role.dart';
import '../../../data/models/company.dart';
import '../../../data/models/company_settings.dart';
import '../../../data/repositories/company_repository.dart';
import '../../../data/services/session_service.dart';
import '../../../routes/routes.dart';
import '../../../shared/widgets/app_info_row.dart';
import '../../../shared/widgets/app_section_card.dart';
import '../../../shared/widgets/app_settings_shell.dart';
import '../../user_management/widgets/settings_categories_section.dart';
import '../../user_management/widgets/settings_notifications_section.dart';
import '../../user_management/widgets/settings_role_workspace_sections.dart';
import '../../user_management/widgets/settings_section_frame.dart';
import '../../user_management/widgets/settings_system_appearance_section.dart';
import '../viewmodels/profile_viewmodel.dart';
import '../widgets/auth_change_password_dialog.dart';

/// Role-scoped settings page using the same side-tab layout as Admin Settings.
class ModuleSettingsPage extends StatefulWidget {
  const ModuleSettingsPage({super.key, this.section});

  final String? section;

  @override
  State<ModuleSettingsPage> createState() => _ModuleSettingsPageState();
}

class _ModuleSettingsPageState extends State<ModuleSettingsPage> {
  final _profileFormKey = GlobalKey<FormState>();
  late final _vm = ProfileViewModel(
    session: getIt(),
    users: getIt(),
    auth: getIt(),
  );
  late final _name = TextEditingController(text: _vm.user.fullName);
  late final _phone = TextEditingController(text: _vm.user.phone);

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _vm.dispose();
    super.dispose();
  }

  Future<void> _saveProfile() async {
    if (!_profileFormKey.currentState!.validate()) return;
    await reportAction(
      context,
      _vm.saveProfile(fullName: _name.text, phone: _phone.text),
      success: 'Profile saved.',
    );
  }

  Future<void> _changePassword() async {
    final result = await AuthChangePasswordDialog.show(context);
    if (result == null || !mounted) return;
    await reportAction(
      context,
      _vm.changePassword(
        currentPassword: result.currentPassword,
        newPassword: result.newPassword,
      ),
      success: 'Password changed.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final role = context.watch<SessionService>().activeRole ?? AppRole.owner;
    final tabs = <AppSettingsTab>[
      AppSettingsTab(
        slug: 'profile',
        label: 'Profile',
        icon: Icons.person_outline,
        group: 'Account',
        builder: (_) => _ProfileSection(
          formKey: _profileFormKey,
          vm: _vm,
          name: _name,
          phone: _phone,
          onSave: _saveProfile,
        ),
      ),
      AppSettingsTab(
        slug: 'security',
        label: 'Password & sign-in',
        icon: Icons.lock_outline,
        group: 'Account',
        builder: (_) => _SecuritySection(
          vm: _vm,
          activeRole: role,
          onChangePassword: _changePassword,
        ),
      ),
      AppSettingsTab(
        slug: 'system',
        label: 'System settings',
        icon: Icons.palette_outlined,
        group: 'System',
        builder: (_) => const SettingsSystemAppearanceSection(),
      ),
      AppSettingsTab(
        slug: 'notifications',
        label: 'Notifications',
        icon: Icons.notifications_outlined,
        group: 'Account',
        builder: (_) => const SettingsNotificationsSection(),
      ),
      if (role == AppRole.owner || role == AppRole.accountant)
        AppSettingsTab(
          slug: 'defaults',
          label: 'Company defaults',
          icon: Icons.percent_rounded,
          group: 'Workspace',
          builder: (_) => _CompanyDefaultsSection(role: role),
        ),
      if (role == AppRole.owner) ...[
        AppSettingsTab(
          slug: 'categories',
          label: 'Work categories',
          icon: Icons.category_outlined,
          group: 'Workspace',
          builder: (_) => const SettingsCategoriesSection(),
        ),
        AppSettingsTab(
          slug: 'pm',
          label: 'Project & procurement',
          icon: Icons.view_timeline_outlined,
          group: 'Workspace',
          builder: (_) => const SettingsPmPreferencesSection(),
        ),
      ],
      if (role == AppRole.siteEngineer)
        AppSettingsTab(
          slug: 'site',
          label: 'Site workspace',
          icon: Icons.engineering_outlined,
          group: 'Workspace',
          builder: (_) => const SettingsForemanPreferencesSection(),
        ),
      if (role == AppRole.accountant)
        AppSettingsTab(
          slug: 'accounting',
          label: 'Payroll & billing',
          icon: Icons.payments_outlined,
          group: 'Workspace',
          builder: (_) => const SettingsAccountantPreferencesSection(),
        ),
      if (role == AppRole.client) ...[
        AppSettingsTab(
          slug: 'company',
          label: 'Contractor info',
          icon: Icons.business_outlined,
          group: 'Workspace',
          builder: (_) => const _ClientCompanySection(),
        ),
        AppSettingsTab(
          slug: 'portal',
          label: 'Portal & statements',
          icon: Icons.receipt_long_outlined,
          group: 'Workspace',
          builder: (_) => const SettingsClientPreferencesSection(),
        ),
      ],
    ];

    return ChangeNotifierProvider.value(
      value: _vm,
      child: AppSettingsShell(
        title: 'Settings',
        subtitle: '${role.label} account and workspace preferences.',
        tabs: tabs,
        currentSlug: widget.section,
        onSelect: (tab) => context.go(AppRoutes.settingsSection(tab.slug)),
      ),
    );
  }
}

class _ProfileSection extends StatelessWidget {
  const _ProfileSection({
    required this.formKey,
    required this.vm,
    required this.name,
    required this.phone,
    required this.onSave,
  });

  final GlobalKey<FormState> formKey;
  final ProfileViewModel vm;
  final TextEditingController name;
  final TextEditingController phone;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return Form(
      key: formKey,
      child: SettingsSectionFrame(
        title: 'Profile',
        description: 'Your name, contact phone, and assigned roles.',
        children: [
          TextFormField(
            controller: name,
            decoration: const InputDecoration(labelText: 'Full name'),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Enter your name.' : null,
          ),
          const SizedBox(height: AppSpacing.md),
          TextFormField(
            controller: phone,
            decoration: const InputDecoration(labelText: 'Phone'),
            keyboardType: TextInputType.phone,
          ),
          const SizedBox(height: AppSpacing.lg),
          AppInfoRow(label: 'Email', value: vm.user.email),
          AppInfoRow(
            label: 'Roles',
            value: vm.roles.map((r) => r.label).join(', '),
          ),
          const SizedBox(height: AppSpacing.lg),
          Consumer<ProfileViewModel>(
            builder: (context, model, _) => SettingsSaveButton(
              label: 'Save profile',
              onPressed: model.isBusy ? null : onSave,
            ),
          ),
        ],
      ),
    );
  }
}

class _SecuritySection extends StatelessWidget {
  const _SecuritySection({
    required this.vm,
    required this.activeRole,
    required this.onChangePassword,
  });

  final ProfileViewModel vm;
  final AppRole activeRole;
  final VoidCallback onChangePassword;

  @override
  Widget build(BuildContext context) {
    return SettingsSectionFrame(
      title: 'Password & sign-in',
      description: 'Update your account password and review your active role.',
      children: [
        AppSectionCard(
          title: 'Active session',
          icon: Icons.badge_outlined,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppInfoRow(label: 'Signed in as', value: vm.user.email),
              AppInfoRow(label: 'Current workspace', value: activeRole.label),
              const SizedBox(height: AppSpacing.md),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: onChangePassword,
                  icon: const Icon(Icons.lock_reset_outlined),
                  label: const Text('Change password'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CompanyDefaultsSection extends StatefulWidget {
  const _CompanyDefaultsSection({required this.role});

  final AppRole role;

  @override
  State<_CompanyDefaultsSection> createState() =>
      _CompanyDefaultsSectionState();
}

class _CompanyDefaultsSectionState extends State<_CompanyDefaultsSection> {
  late final Future<(Company, CompanySettings)> _future = _load();

  Future<(Company, CompanySettings)> _load() async {
    final repo = getIt<CompanyRepository>();
    final company = await repo.getCompany();
    final settings = await repo.getSettings();
    return (company, settings);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<(Company, CompanySettings)>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(AppSpacing.xl),
              child: CircularProgressIndicator(),
            ),
          );
        }
        if (snap.hasError || !snap.hasData) {
          return SettingsSectionFrame(
            title: 'Company defaults',
            description: 'Default percentages configured by your system admin.',
            children: [
              Text('Could not load company defaults: ${snap.error}'),
            ],
          );
        }
        final (company, settings) = snap.data!;
        return SettingsSectionFrame(
          title: 'Company defaults',
          description:
              'Read-only company profile and project defaults managed by System Admin.',
          children: [
            AppSectionCard(
              title: company.name,
              icon: Icons.business_outlined,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppInfoRow(
                    label: 'Default retention',
                    value: '${settings.defaultRetentionPct.toStringAsFixed(1)}%',
                  ),
                  AppInfoRow(
                    label: 'Default down payment',
                    value:
                        '${settings.defaultDownPaymentPct.toStringAsFixed(1)}%',
                  ),
                  AppInfoRow(
                    label: 'Behind-schedule alert',
                    value:
                        '${settings.behindScheduleThresholdPct.toStringAsFixed(1)}%',
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ClientCompanySection extends StatefulWidget {
  const _ClientCompanySection();

  @override
  State<_ClientCompanySection> createState() => _ClientCompanySectionState();
}

class _ClientCompanySectionState extends State<_ClientCompanySection> {
  late final Future<Company> _future = getIt<CompanyRepository>().getCompany();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Company>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(AppSpacing.xl),
              child: CircularProgressIndicator(),
            ),
          );
        }
        final company = snap.data;
        return SettingsSectionFrame(
          title: 'Contractor info',
          description: 'Company details for your construction contractor.',
          children: [
            if (company == null)
              const Text('Contractor details unavailable.')
            else
              AppSectionCard(
                title: company.name,
                icon: Icons.business_outlined,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (company.address.isNotEmpty)
                      AppInfoRow(label: 'Address', value: company.address),
                    if (company.pcabLicenseNo.isNotEmpty)
                      AppInfoRow(
                        label: 'PCAB license',
                        value: company.pcabLicenseNo,
                      ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

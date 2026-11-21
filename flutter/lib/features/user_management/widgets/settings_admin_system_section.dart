import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/utils/app_messages.dart';
import '../../../data/models/system_admin.dart';
import '../../../data/repositories/system_admin_repository.dart';
import '../../../data/services/workspace_preferences_service.dart';
import '../../../routes/routes.dart';
import '../../../shared/widgets/app_info_row.dart';
import '../../../shared/widgets/app_section_card.dart';
import 'settings_section_frame.dart';

class SettingsPdfBrandingSection extends StatefulWidget {
  const SettingsPdfBrandingSection({super.key});

  @override
  State<SettingsPdfBrandingSection> createState() =>
      _SettingsPdfBrandingSectionState();
}

class _SettingsPdfBrandingSectionState
    extends State<SettingsPdfBrandingSection> {
  final _prefs = getIt<WorkspacePreferencesService>();
  late final _footer = TextEditingController(text: _prefs.pdfFooterText);
  late final _signatory = TextEditingController(text: _prefs.pdfSignatoryName);
  late final _title = TextEditingController(text: _prefs.pdfSignatoryTitle);

  @override
  void dispose() {
    _footer.dispose();
    _signatory.dispose();
    _title.dispose();
    super.dispose();
  }

  void _save() {
    _prefs.update(() {
      _prefs.pdfFooterText = _footer.text.trim();
      _prefs.pdfSignatoryName = _signatory.text.trim();
      _prefs.pdfSignatoryTitle = _title.text.trim();
    });
    showAppMessage(context, 'PDF & report branding saved.');
  }

  @override
  Widget build(BuildContext context) {
    return SettingsSectionFrame(
      title: 'PDF & report branding',
      description:
          'Configure letterhead footer, signatory details, and license visibility on exported PDFs.',
      children: [
        AppSectionCard(
          title: 'Exported document layout',
          icon: Icons.picture_as_pdf_outlined,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _footer,
                decoration: const InputDecoration(
                  labelText: 'Letterhead footer text',
                  hintText: 'Queen Builders Construction',
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _signatory,
                decoration: const InputDecoration(
                  labelText: 'Default signatory name',
                  hintText: 'e.g. Maria Santos',
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _title,
                decoration: const InputDecoration(
                  labelText: 'Signatory title',
                  hintText: 'e.g. Authorized Signatory',
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Show PCAB license on PDFs'),
                subtitle: const Text(
                  'Include the company PCAB license number on progress billings and reports.',
                ),
                value: _prefs.showPcabOnPdf,
                onChanged: (v) => setState(
                  () => _prefs.update(() => _prefs.showPcabOnPdf = v),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              SettingsSaveButton(label: 'Save branding', onPressed: _save),
            ],
          ),
        ),
      ],
    );
  }
}

class SettingsDocumentsAuditSection extends StatefulWidget {
  const SettingsDocumentsAuditSection({super.key});

  @override
  State<SettingsDocumentsAuditSection> createState() =>
      _SettingsDocumentsAuditSectionState();
}

class _SettingsDocumentsAuditSectionState
    extends State<SettingsDocumentsAuditSection> {
  final _prefs = getIt<WorkspacePreferencesService>();
  late final Future<SystemHealthOverview> _healthFuture =
      getIt<SystemAdminRepository>().getSystemHealth();

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
      title: 'Documents, audit & POS',
      description:
          'Upload limits, audit log retention policy, and POS bridge configuration.',
      children: [
        AppSectionCard(
          title: 'Document & photo uploads',
          icon: Icons.upload_file_outlined,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<int>(
                key: ValueKey('upload-${_prefs.maxUploadSizeMb}'),
                initialValue: _prefs.maxUploadSizeMb,
                decoration: const InputDecoration(labelText: 'Max upload size'),
                items: const [
                  DropdownMenuItem(value: 5, child: Text('5 MB')),
                  DropdownMenuItem(value: 10, child: Text('10 MB')),
                  DropdownMenuItem(value: 20, child: Text('20 MB')),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  _prefs.update(() => _prefs.maxUploadSizeMb = v);
                  showAppMessage(context, 'Upload limit updated.');
                },
              ),
              const SizedBox(height: AppSpacing.md),
              const AppInfoRow(
                label: 'Allowed file types',
                value: 'JPG, PNG, WebP, PDF, DOCX, XLSX',
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        AppSectionCard(
          title: 'Audit log retention',
          icon: Icons.history_outlined,
          child: DropdownButtonFormField<int>(
            key: ValueKey('audit-${_prefs.auditRetentionDays}'),
            initialValue: _prefs.auditRetentionDays,
            decoration: const InputDecoration(
              labelText: 'Keep audit entries before archiving',
            ),
            items: const [
              DropdownMenuItem(value: 90, child: Text('90 days')),
              DropdownMenuItem(value: 180, child: Text('180 days')),
              DropdownMenuItem(value: 365, child: Text('1 year (365 days)')),
              DropdownMenuItem(value: 730, child: Text('2 years (730 days)')),
            ],
            onChanged: (v) {
              if (v == null) return;
              _prefs.update(() => _prefs.auditRetentionDays = v);
              showAppMessage(context, 'Audit retention policy updated.');
            },
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        FutureBuilder<SystemHealthOverview>(
          future: _healthFuture,
          builder: (context, snap) {
            final pos = snap.data?.posBridge;
            return AppSectionCard(
              title: 'POS bridge configuration',
              icon: Icons.storefront_outlined,
              trailing: TextButton(
                onPressed: () => context.go(AppRoutes.adminHealth),
                child: const Text('Open monitor'),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppInfoRow(
                    label: 'POS API endpoint',
                    value: (pos?.baseUrl.isNotEmpty ?? false)
                        ? pos!.baseUrl
                        : 'Not configured',
                  ),
                  AppInfoRow(
                    label: 'Synced own-store orders',
                    value: pos == null ? '—' : '${pos.syncedCount}',
                  ),
                  AppInfoRow(
                    label: 'Pending / failed syncs',
                    value: pos == null
                        ? '—'
                        : '${pos.pendingCount} pending · ${pos.failedCount} failed',
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/utils/app_messages.dart';
import '../../../core/utils/input_parsers.dart';
import '../../../data/services/master_data_rules.dart';
import '../../../shared/widgets/app_date_field.dart';
import '../../../shared/widgets/app_empty_state.dart';
import '../viewmodels/admin_audit.dart';
import '../viewmodels/company_profile_viewmodel.dart';
import 'settings_section_frame.dart';
import 'user_management_pcab_banner.dart';

/// Which part of the company record a [SettingsCompanySection] edits.
enum CompanySectionPart { profile, licenses }

/// Company details in Settings: the profile (name, address, TIN, logo) or
/// licenses (PCAB). Each part saves only its own fields.
class SettingsCompanySection extends StatefulWidget {
  const SettingsCompanySection({super.key, required this.part});

  final CompanySectionPart part;

  @override
  State<SettingsCompanySection> createState() => _SettingsCompanySectionState();
}

class _SettingsCompanySectionState extends State<SettingsCompanySection> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _address = TextEditingController();
  final _tin = TextEditingController();
  final _pcab = TextEditingController();
  final _logo = TextEditingController();
  DateTime? _expiry;
  bool _expiryMissing = false;
  late final _vm = CompanyProfileViewModel(
    company: getIt(),
    audit: AdminAudit.fromLocator(),
  );

  bool get _isProfile => widget.part == CompanySectionPart.profile;

  @override
  void initState() {
    super.initState();
    _vm.load().then((_) {
      final c = _vm.company;
      if (c == null || !mounted) return;
      setState(() {
        _name.text = c.name;
        _address.text = c.address;
        _tin.text = c.tin;
        _pcab.text = c.pcabLicenseNo;
        _logo.text = c.logoUrl ?? '';
        _expiry = c.pcabLicenseExpiry;
      });
    });
  }

  @override
  void dispose() {
    for (final c in [_name, _address, _tin, _pcab, _logo]) {
      c.dispose();
    }
    _vm.dispose();
    super.dispose();
  }

  Future<void> _pickExpiry() async {
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      initialDate: _expiry ?? DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        _expiry = picked;
        _expiryMissing = false;
      });
    }
  }

  Future<void> _save() async {
    final valid = _formKey.currentState!.validate();
    if (!_isProfile && _expiry == null) {
      setState(() => _expiryMissing = true);
      return;
    }
    if (!valid) return;
    final current = _vm.company!;
    final updated = _isProfile
        ? current.copyWith(
            name: _name.text.trim(),
            address: _address.text.trim(),
            tin: _tin.text.trim(),
            logoUrl: () => InputParsers.optional(_logo.text),
          )
        : current.copyWith(
            pcabLicenseNo: _pcab.text.trim(),
            pcabLicenseExpiry: _expiry,
          );
    await reportAction(
      context,
      _vm.save(updated),
      success: _isProfile ? 'Company profile saved.' : 'License details saved.',
    );
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _vm,
      child: Consumer<CompanyProfileViewModel>(
        builder: (context, vm, _) {
          if (vm.isLoading) {
            return const Padding(
              padding: EdgeInsets.all(AppSpacing.xxl),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          if (vm.error != null) return AppEmptyState(message: vm.error!);
          final reminder = vm.pcabReminder;
          final banner = reminder == null
              ? null
              : UserManagementPcabBanner(message: reminder);
          return Form(
            key: _formKey,
            child: _isProfile
                ? SettingsSectionFrame(
                    title: 'Company profile',
                    description:
                        'How Queen Builders appears on reports, billings and '
                        'the client portal.',
                    banner: banner,
                    children: [
                      TextFormField(
                        controller: _name,
                        decoration: const InputDecoration(
                          labelText: 'Company name',
                        ),
                        validator: (v) =>
                            MasterDataRules.required(v, 'company name'),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      TextFormField(
                        controller: _address,
                        decoration: const InputDecoration(labelText: 'Address'),
                        validator: (v) =>
                            MasterDataRules.required(v, 'address'),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      TextFormField(
                        controller: _tin,
                        decoration: const InputDecoration(
                          labelText: 'TIN',
                          hintText: '000-000-000-000',
                        ),
                        validator: MasterDataRules.validateTin,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      TextFormField(
                        controller: _logo,
                        decoration: const InputDecoration(
                          labelText: 'Logo URL',
                          helperText:
                              'File upload arrives with the API; paste a URL '
                              'for now.',
                        ),
                      ),
                      SettingsSaveButton(
                        label: 'Save profile',
                        onPressed: vm.isBusy ? null : _save,
                      ),
                    ],
                  )
                : SettingsSectionFrame(
                    title: 'Licenses and compliance',
                    description:
                        'Your PCAB contractor license. The overview warns you '
                        'before it expires.',
                    banner: banner,
                    children: [
                      TextFormField(
                        controller: _pcab,
                        decoration: const InputDecoration(
                          labelText: 'PCAB license no.',
                        ),
                        validator: (v) =>
                            MasterDataRules.required(v, 'PCAB license number'),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      AppDateField(
                        label: 'License expiry',
                        value: _expiry,
                        hasError: _expiryMissing,
                        onTap: _pickExpiry,
                      ),
                      SettingsSaveButton(
                        label: 'Save license',
                        onPressed: vm.isBusy ? null : _save,
                      ),
                    ],
                  ),
          );
        },
      ),
    );
  }
}

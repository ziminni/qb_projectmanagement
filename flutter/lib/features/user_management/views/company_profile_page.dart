import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/utils/app_messages.dart';
import '../../../core/utils/input_parsers.dart';
import '../../../core/utils/page_padding.dart';
import '../../../data/services/master_data_rules.dart';
import '../../../shared/widgets/app_date_field.dart';
import '../../../shared/widgets/app_empty_state.dart';
import '../../../shared/widgets/app_section_card.dart';
import '../viewmodels/company_profile_viewmodel.dart';
import '../widgets/user_management_pcab_banner.dart';

class CompanyProfilePage extends StatefulWidget {
  const CompanyProfilePage({super.key});

  @override
  State<CompanyProfilePage> createState() => _CompanyProfilePageState();
}

class _CompanyProfilePageState extends State<CompanyProfilePage> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _address = TextEditingController();
  final _tin = TextEditingController();
  final _pcab = TextEditingController();
  final _logo = TextEditingController();
  DateTime? _expiry;
  late final _vm = CompanyProfileViewModel(company: getIt());

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
    if (picked != null) setState(() => _expiry = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _expiry == null) return;
    await reportAction(
      context,
      _vm.save(
        _vm.company!.copyWith(
          name: _name.text.trim(),
          address: _address.text.trim(),
          tin: _tin.text.trim(),
          pcabLicenseNo: _pcab.text.trim(),
          pcabLicenseExpiry: _expiry,
          logoUrl: () => InputParsers.optional(_logo.text),
        ),
      ),
      success: 'Company profile saved.',
    );
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _vm,
      child: Consumer<CompanyProfileViewModel>(
        builder: (context, vm, _) {
          if (vm.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (vm.error != null) return AppEmptyState(message: vm.error!);
          final reminder = vm.pcabReminder;
          return Form(
            key: _formKey,
            child: ListView(
              padding: pagePadding(context),
              children: [
                if (reminder != null) ...[
                  UserManagementPcabBanner(message: reminder),
                  const SizedBox(height: AppSpacing.lg),
                ],
                AppSectionCard(
                  title: 'Company profile',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
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
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _pcab,
                              decoration: const InputDecoration(
                                labelText: 'PCAB license no.',
                              ),
                              validator: (v) => MasterDataRules.required(
                                v,
                                'PCAB license number',
                              ),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: AppDateField(
                              label: 'License expiry',
                              value: _expiry,
                              hasError: false,
                              onTap: _pickExpiry,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.md),
                      TextFormField(
                        controller: _logo,
                        decoration: const InputDecoration(
                          labelText: 'Logo URL',
                          helperText:
                              'File upload arrives with the API; paste a URL for now.',
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: FilledButton(
                          onPressed: vm.isBusy ? null : _save,
                          child: const Text('Save'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

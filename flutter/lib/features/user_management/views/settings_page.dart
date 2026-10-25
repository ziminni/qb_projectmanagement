import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/utils/app_messages.dart';
import '../../../core/utils/input_parsers.dart';
import '../../../core/utils/page_padding.dart';
import '../../../data/services/master_data_rules.dart';
import '../../../shared/widgets/app_empty_state.dart';
import '../../../shared/widgets/app_section_card.dart';
import '../viewmodels/settings_viewmodel.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _formKey = GlobalKey<FormState>();
  final _threshold = TextEditingController();
  final _retention = TextEditingController();
  final _downPayment = TextEditingController();
  final _behind = TextEditingController();
  late final _vm = SettingsViewModel(company: getIt());

  @override
  void initState() {
    super.initState();
    _vm.load().then((_) {
      final s = _vm.settings;
      if (s == null) return;
      _threshold.text = InputParsers.amountText(s.poApprovalThreshold);
      _retention.text = InputParsers.amountText(s.defaultRetentionPct);
      _downPayment.text = InputParsers.amountText(s.defaultDownPaymentPct);
      _behind.text = InputParsers.amountText(s.behindScheduleThresholdPct);
    });
  }

  @override
  void dispose() {
    for (final c in [_threshold, _retention, _downPayment, _behind]) {
      c.dispose();
    }
    _vm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    await reportAction(
      context,
      _vm.save(
        _vm.settings!.copyWith(
          poApprovalThreshold: InputParsers.amount(_threshold.text),
          defaultRetentionPct: InputParsers.amount(_retention.text),
          defaultDownPaymentPct: InputParsers.amount(_downPayment.text),
          behindScheduleThresholdPct: InputParsers.amount(_behind.text),
        ),
      ),
      success: 'Settings saved.',
    );
  }

  Widget _field(
    TextEditingController c,
    String label, {
    String? helper,
    bool peso = false,
  }) => TextFormField(
    controller: c,
    decoration: InputDecoration(
      labelText: label,
      helperText: helper,
      prefixText: peso ? '₱ ' : null,
      suffixText: peso ? null : '%',
    ),
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    validator: (v) => peso
        ? MasterDataRules.validateAmount(InputParsers.amount(v), label)
        : MasterDataRules.validatePercent(InputParsers.amount(v), label),
  );

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _vm,
      child: Consumer<SettingsViewModel>(
        builder: (context, vm, _) {
          if (vm.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (vm.error != null) return AppEmptyState(message: vm.error!);
          return Form(
            key: _formKey,
            child: ListView(
              padding: pagePadding(context),
              children: [
                AppSectionCard(
                  title: 'Approvals',
                  child: _field(
                    _threshold,
                    'Large purchase threshold',
                    helper:
                        'Purchase orders above this amount need owner approval.',
                    peso: true,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                AppSectionCard(
                  title: 'Billing defaults for new projects',
                  child: Column(
                    children: [
                      _field(_retention, 'Default retention'),
                      const SizedBox(height: AppSpacing.md),
                      _field(_downPayment, 'Default down payment'),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                AppSectionCard(
                  title: 'Schedule monitoring',
                  child: _field(
                    _behind,
                    'Behind-schedule threshold',
                    helper:
                        'Projects this many points behind plan are flagged on '
                        'the owner dashboard.',
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton(
                    onPressed: vm.isBusy ? null : _save,
                    child: const Text('Save settings'),
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

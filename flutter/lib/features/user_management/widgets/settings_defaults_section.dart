import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/utils/app_messages.dart';
import '../../../core/utils/input_parsers.dart';
import '../../../data/services/master_data_rules.dart';
import '../../../shared/widgets/app_empty_state.dart';
import '../viewmodels/admin_audit.dart';
import '../viewmodels/settings_viewmodel.dart';
import 'settings_section_frame.dart';

/// Which company settings a [SettingsDefaultsSection] edits.
enum DefaultsSectionPart { billing, schedule }

/// Project defaults in Settings: billing percentages for new projects, or
/// the behind-schedule threshold. Each part saves only its own fields.
class SettingsDefaultsSection extends StatefulWidget {
  const SettingsDefaultsSection({super.key, required this.part});

  final DefaultsSectionPart part;

  @override
  State<SettingsDefaultsSection> createState() =>
      _SettingsDefaultsSectionState();
}

class _SettingsDefaultsSectionState extends State<SettingsDefaultsSection> {
  final _formKey = GlobalKey<FormState>();
  final _retention = TextEditingController();
  final _downPayment = TextEditingController();
  final _behind = TextEditingController();
  late final _vm = SettingsViewModel(
    company: getIt(),
    audit: AdminAudit.fromLocator(),
  );

  bool get _isBilling => widget.part == DefaultsSectionPart.billing;

  @override
  void initState() {
    super.initState();
    _vm.load().then((_) {
      final s = _vm.settings;
      if (s == null) return;
      _retention.text = InputParsers.amountText(s.defaultRetentionPct);
      _downPayment.text = InputParsers.amountText(s.defaultDownPaymentPct);
      _behind.text = InputParsers.amountText(s.behindScheduleThresholdPct);
    });
  }

  @override
  void dispose() {
    for (final c in [_retention, _downPayment, _behind]) {
      c.dispose();
    }
    _vm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final s = _vm.settings!;
    await reportAction(
      context,
      _vm.save(
        _isBilling
            ? s.copyWith(
                defaultRetentionPct: InputParsers.amount(_retention.text),
                defaultDownPaymentPct: InputParsers.amount(_downPayment.text),
              )
            : s.copyWith(
                behindScheduleThresholdPct: InputParsers.amount(_behind.text),
              ),
      ),
      success: 'Settings saved.',
    );
  }

  Widget _percent(TextEditingController c, String label, {String? helper}) =>
      TextFormField(
        controller: c,
        decoration: InputDecoration(
          labelText: label,
          helperText: helper,
          helperMaxLines: 3,
          suffixText: '%',
        ),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        validator: (v) =>
            MasterDataRules.validatePercent(InputParsers.amount(v), label),
      );

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _vm,
      child: Consumer<SettingsViewModel>(
        builder: (context, vm, _) {
          if (vm.isLoading) {
            return const Padding(
              padding: EdgeInsets.all(AppSpacing.xxl),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          if (vm.error != null) return AppEmptyState(message: vm.error!);
          return Form(
            key: _formKey,
            child: _isBilling
                ? SettingsSectionFrame(
                    title: 'Billing defaults',
                    description:
                        'Starting percentages for new projects. Owners can '
                        'change them per project.',
                    children: [
                      _percent(
                        _retention,
                        'Default retention',
                        helper: 'Held back from each progress billing.',
                      ),
                      const SizedBox(height: AppSpacing.md),
                      _percent(
                        _downPayment,
                        'Default down payment',
                        helper: 'Billed to the client before work starts.',
                      ),
                      SettingsSaveButton(
                        label: 'Save billing defaults',
                        onPressed: vm.isBusy ? null : _save,
                      ),
                    ],
                  )
                : SettingsSectionFrame(
                    title: 'Schedule monitoring',
                    description: 'When a project counts as behind schedule.',
                    children: [
                      _percent(
                        _behind,
                        'Behind-schedule threshold',
                        helper:
                            'Projects this many points behind plan are '
                            'flagged on the owner dashboard.',
                      ),
                      SettingsSaveButton(
                        label: 'Save schedule settings',
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

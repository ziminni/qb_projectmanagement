import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/utils/finance_access.dart';
import '../../../shared/widgets/app_action_bar.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/utils/app_messages.dart';
import '../../../core/utils/input_parsers.dart';
import '../../../core/utils/page_padding.dart';
import '../../../data/models/variation_order.dart';
import '../../../data/services/billing_rules.dart';
import '../../../routes/routes.dart';
import '../../../shared/widgets/app_empty_state.dart';
import '../../../shared/widgets/app_section_card.dart';
import '../viewmodels/variation_order_form_viewmodel.dart';

/// Raise or edit a variation order: added work, deleted work or a design
/// change, with its cost and time impact.
class VariationOrderFormPage extends StatefulWidget {
  const VariationOrderFormPage({super.key, this.voId, this.projectId});

  final int? voId;
  final int? projectId;

  @override
  State<VariationOrderFormPage> createState() => _VariationOrderFormPageState();
}

class _VariationOrderFormPageState extends State<VariationOrderFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _description = TextEditingController();
  final _amount = TextEditingController();
  final _days = TextEditingController(text: '0');
  late final _vm = VariationOrderFormViewModel(
    voId: widget.voId,
    initialProjectId: widget.projectId,
    session: getIt(),
    projects: getIt(),
    billing: getIt(),
  );

  @override
  void initState() {
    super.initState();
    _vm.load().then((_) {
      final e = _vm.existing;
      if (e == null) return;
      _description.text = e.description;
      _amount.text = InputParsers.amountText(
        e.type == VariationOrderType.deductive ? e.amount.abs() : e.amount,
      );
      _days.text = '${e.daysImpact}';
    });
  }

  @override
  void dispose() {
    _description.dispose();
    _amount.dispose();
    _days.dispose();
    _vm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final ok = await reportAction(
      context,
      _vm.save(
        description: _description.text,
        amount: canSeeFinance() ? InputParsers.amount(_amount.text)! : 0,
        daysImpact: InputParsers.integer(_days.text) ?? 0,
      ),
      success: 'Variation order saved.',
    );
    if (ok && mounted) context.go(AppRoutes.variationOrder(_vm.savedId!));
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _vm,
      child: Consumer<VariationOrderFormViewModel>(
        builder: (context, vm, _) {
          final finance = canSeeFinance();
          if (vm.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (vm.error != null) return AppEmptyState(message: vm.error!);
          return Form(
            key: _formKey,
            child: Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: pagePadding(context),
                    children: [
                      AppSectionCard(
                        title: vm.existing == null
                            ? 'Raise a variation order'
                            : 'Edit ${vm.existing!.voNo}',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            DropdownButtonFormField<int>(
                              initialValue: vm.projectId,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Project',
                              ),
                              items: [
                                for (final p in vm.projectOptions)
                                  DropdownMenuItem(
                                    value: p.id,
                                    child: Text('${p.code} · ${p.name}'),
                                  ),
                              ],
                              onChanged: vm.existing == null
                                  ? vm.setProject
                                  : null,
                            ),
                            const SizedBox(height: AppSpacing.md),
                            SegmentedButton<VariationOrderType>(
                              segments: [
                                for (final t in VariationOrderType.values)
                                  ButtonSegment(value: t, label: Text(t.label)),
                              ],
                              selected: {vm.type},
                              onSelectionChanged: (s) => vm.setType(s.first),
                            ),
                            const SizedBox(height: AppSpacing.md),
                            TextFormField(
                              controller: _description,
                              maxLines: 3,
                              decoration: const InputDecoration(
                                labelText: 'Description of the change',
                              ),
                              validator: BillingRules.validateVoDescription,
                            ),
                            const SizedBox(height: AppSpacing.md),
                            Row(
                              children: [
                                if (finance) ...[
                                  Expanded(
                                    child: TextFormField(
                                      controller: _amount,
                                      decoration: InputDecoration(
                                        labelText:
                                            vm.type == VariationOrderType.change
                                            ? 'Cost impact (− for savings)'
                                            : vm.type ==
                                                  VariationOrderType.deductive
                                            ? 'Amount deducted'
                                            : 'Amount added',
                                        prefixText: '₱ ',
                                      ),
                                      keyboardType:
                                          const TextInputType.numberWithOptions(
                                            decimal: true,
                                            signed: true,
                                          ),
                                      validator: (v) =>
                                          BillingRules.validateVoAmount(
                                            vm.type,
                                            InputParsers.amount(v),
                                          ),
                                    ),
                                  ),
                                  const SizedBox(width: AppSpacing.md),
                                ],
                                Expanded(
                                  child: TextFormField(
                                    controller: _days,
                                    decoration: const InputDecoration(
                                      labelText: 'Time impact (days)',
                                    ),
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                          signed: true,
                                        ),
                                    validator: (v) =>
                                        InputParsers.integer(v) == null
                                        ? 'Enter whole days.'
                                        : null,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                AppActionBar(
                  hint: finance
                      ? 'You send the VO to the client for approval.'
                      : 'The owner prices the change and sends it to the client.',
                  children: [
                    FilledButton(
                      onPressed: vm.isBusy ? null : _save,
                      child: const Text('Save'),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

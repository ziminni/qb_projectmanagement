import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../shared/widgets/app_action_bar.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/utils/app_messages.dart';
import '../../../core/utils/input_parsers.dart';
import '../../../core/utils/page_padding.dart';
import '../../../data/services/procurement_rules.dart';
import '../../../routes/routes.dart';
import '../../../shared/widgets/app_date_field.dart';
import '../../../shared/widgets/app_empty_state.dart';
import '../../../shared/widgets/app_section_card.dart';
import '../viewmodels/material_request_form_viewmodel.dart';
import '../viewmodels/procurement_lookups.dart';
import '../widgets/procurement_line_editor.dart';

class MaterialRequestFormPage extends StatefulWidget {
  const MaterialRequestFormPage({super.key, this.projectId});

  final int? projectId;

  @override
  State<MaterialRequestFormPage> createState() =>
      _MaterialRequestFormPageState();
}

class _MaterialRequestFormPageState extends State<MaterialRequestFormPage> {
  final _formKey = GlobalKey<FormState>();
  late final _vm = MaterialRequestFormViewModel(
    initialProjectId: widget.projectId,
    session: getIt(),
    procurement: getIt(),
    lookups: ProcurementLookups.fromServices(),
  )..load();

  @override
  void dispose() {
    _vm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final ok = await reportAction(
      context,
      _vm.submit(),
      success: 'Request sent to the owner.',
    );
    if (ok && mounted) context.go(AppRoutes.materialRequest(_vm.savedId!));
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _vm,
      child: Consumer<MaterialRequestFormViewModel>(
        builder: (context, vm, _) {
          if (vm.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (vm.error != null) return AppEmptyState(message: vm.error!);
          final dateError = ProcurementRules.validateNeededBy(
            vm.neededBy,
            DateTime.now(),
          );
          final small = Theme.of(context).textTheme.bodySmall;
          return Form(
            key: _formKey,
            child: Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: pagePadding(context),
                    children: [
                      AppSectionCard(
                        title: 'Material request',
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
                              validator: (v) =>
                                  v == null ? 'Choose the project.' : null,
                              onChanged: vm.setProject,
                            ),
                            const SizedBox(height: AppSpacing.md),
                            AppDateField(
                              label: 'Needed by',
                              value: vm.neededBy,
                              hasError: dateError != null,
                              onTap: () async {
                                final d = await showDatePicker(
                                  context: context,
                                  firstDate: DateTime.now(),
                                  lastDate: DateTime(2030),
                                  initialDate: vm.neededBy,
                                );
                                if (d != null) vm.setNeededBy(d);
                              },
                            ),
                          ],
                        ),
                      ),
                      if (vm.projectId != null) ...[
                        const SizedBox(height: AppSpacing.lg),
                        AppSectionCard(
                          key: ValueKey('counts-${vm.projectId}'),
                          title: '1. Count what is left on site',
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                vm.counts.isEmpty
                                    ? 'Nothing on site to count yet.'
                                    : 'Count each material before asking for '
                                          'more. The owner sees your count next '
                                          'to what the system expects.',
                                style: small,
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              for (final c in vm.counts)
                                Padding(
                                  padding: const EdgeInsets.only(
                                    bottom: AppSpacing.sm,
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        flex: 3,
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(c.line.name),
                                            Text(
                                              'System: ${InputParsers.amountText(c.line.onHand)} ${c.line.unit}',
                                              style: small,
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: AppSpacing.sm),
                                      Expanded(
                                        flex: 2,
                                        child: TextFormField(
                                          decoration: InputDecoration(
                                            labelText: 'Counted',
                                            suffixText: c.line.unit,
                                          ),
                                          keyboardType:
                                              const TextInputType.numberWithOptions(
                                                decimal: true,
                                              ),
                                          validator: (v) =>
                                              ProcurementRules.validateCount(
                                                InputParsers.amount(v),
                                              ),
                                          onChanged: (v) => c.counted =
                                              InputParsers.amount(v),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: AppSpacing.lg),
                      AppSectionCard(
                        title: '2. What you need',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Type or pick each item, then how many and in '
                              'what unit (bags, kilos, pieces...). The owner '
                              'picks the exact store products when ordering.',
                              style: small,
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            for (final line in vm.lines)
                              ProcurementLineEditor(
                                key: ObjectKey(line),
                                line: line,
                                nameLabel: 'Item',
                                unitChoices: commonUnits,
                                suggestions: vm.lookups.materials.values
                                    .toList(),
                                onChanged: vm.changed,
                                onRemove: () => vm.removeLine(line),
                              ),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton.icon(
                                onPressed: vm.addLine,
                                icon: const Icon(Icons.add),
                                label: const Text('Add item'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                AppActionBar(
                  hint:
                      'The owner orders it from the own store or buys it from '
                      'another store.',
                  children: [
                    FilledButton.icon(
                      onPressed: vm.isBusy ? null : _submit,
                      icon: const Icon(Icons.send),
                      label: const Text('Send to owner'),
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

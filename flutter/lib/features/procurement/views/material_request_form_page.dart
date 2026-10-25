import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../shared/widgets/app_action_bar.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/utils/app_messages.dart';
import '../../../core/utils/page_padding.dart';
import '../../../data/services/procurement_rules.dart';
import '../../../routes/routes.dart';
import '../../../shared/widgets/app_date_field.dart';
import '../../../shared/widgets/app_empty_state.dart';
import '../../../shared/widgets/app_quantity_rows_editor.dart';
import '../../../shared/widgets/app_section_card.dart';
import '../viewmodels/material_request_form_viewmodel.dart';
import '../viewmodels/procurement_lookups.dart';
import '../widgets/procurement_budget_card.dart';

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
      success: 'Request sent to the PM.',
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
                            DropdownButtonFormField<int>(
                              key: ValueKey('category-${vm.projectId}'),
                              initialValue: vm.categoryId,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Category (budget it draws from)',
                              ),
                              items: [
                                for (final c in vm.categoryOptions)
                                  DropdownMenuItem(
                                    value: c.id,
                                    child: Text(c.name),
                                  ),
                              ],
                              validator: (v) =>
                                  v == null ? 'Choose the category.' : null,
                              onChanged: vm.setCategory,
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
                      const SizedBox(height: AppSpacing.lg),
                      AppSectionCard(
                        title: 'Items',
                        child: AppQuantityRowsEditor(
                          rows: vm.rows,
                          options: [
                            for (final m in vm.lookups.materials.values)
                              (m.id, '${m.name} (${m.unit})'),
                          ],
                          itemLabel: 'Material',
                          quantityLabel: 'Quantity',
                          addLabel: 'Add item',
                          validateQuantity: ProcurementRules.validateQuantity,
                          onChanged: vm.refreshBudget,
                        ),
                      ),
                      if (vm.budget != null) ...[
                        const SizedBox(height: AppSpacing.lg),
                        ProcurementBudgetCard(check: vm.budget!),
                      ],
                    ],
                  ),
                ),
                AppActionBar(
                  hint: vm.budget?.exceedsBudget == true
                      ? 'Over the category budget: the owner approves after the PM.'
                      : 'The PM reviews the request before purchasing orders it.',
                  children: [
                    FilledButton.icon(
                      onPressed: vm.isBusy ? null : _submit,
                      icon: const Icon(Icons.send),
                      label: const Text('Send to PM'),
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

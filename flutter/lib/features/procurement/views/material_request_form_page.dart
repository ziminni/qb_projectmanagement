import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_radii.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/utils/app_messages.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/input_parsers.dart';
import '../../../core/utils/page_padding.dart';
import '../../../data/services/procurement_rules.dart';
import '../../../routes/routes.dart';
import '../../../shared/widgets/app_action_bar.dart';
import '../../../shared/widgets/app_date_field.dart';
import '../../../shared/widgets/app_empty_state.dart';
import '../../../shared/widgets/app_section_card.dart';
import '../viewmodels/line_draft.dart';
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
    schedule: getIt(),
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
                              key: ValueKey('mr-project-${vm.projectId}'),
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
                            if (vm.categories.isNotEmpty) ...[
                              const SizedBox(height: AppSpacing.md),
                              DropdownButtonFormField<int?>(
                                key: ValueKey(
                                  'mr-category-${vm.projectId}-${vm.categoryId}',
                                ),
                                initialValue:
                                    vm.categories.any(
                                      (c) => c.id == vm.categoryId,
                                    )
                                    ? vm.categoryId
                                    : null,
                                isExpanded: true,
                                decoration: const InputDecoration(
                                  labelText: 'Item of work',
                                  helperText:
                                      'Filters materials to that Item of Work\'s DUPA list.',
                                ),
                                items: [
                                  const DropdownMenuItem<int?>(
                                    value: null,
                                    child: Text('All Items of Work'),
                                  ),
                                  for (final c in vm.categories)
                                    DropdownMenuItem<int?>(
                                      value: c.id,
                                      child: Text(
                                        vm.hasPlannedMaterials
                                            ? '${c.name} (${vm.plannedCountForCategory(c.id)} materials)'
                                            : c.name,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                ],
                                onChanged: vm.setCategory,
                              ),
                            ],
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
                              vm.hasPlannedMaterials
                                  ? 'Pick materials from this project\'s DUPA Planned Materials. '
                                        'Units lock automatically and remaining quantities are checked against the plan.'
                                  : 'Type or pick each item, then how many and in '
                                        'what unit (bags, kilos, pieces...). The owner '
                                        'picks the exact store products when ordering.',
                              style: small,
                            ),
                            const SizedBox(height: AppSpacing.md),
                            for (final line in vm.lines)
                              if (vm.hasPlannedMaterials && !line.isUnplanned)
                                _PlannedLineCard(
                                  key: ObjectKey(line),
                                  vm: vm,
                                  line: line,
                                )
                              else if (vm.hasPlannedMaterials &&
                                  line.isUnplanned)
                                _UnplannedLineCard(
                                  key: ObjectKey(line),
                                  vm: vm,
                                  line: line,
                                )
                              else
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
                            Wrap(
                              spacing: AppSpacing.sm,
                              runSpacing: AppSpacing.xs,
                              children: [
                                TextButton.icon(
                                  onPressed: vm.addLine,
                                  icon: const Icon(Icons.add),
                                  label: Text(
                                    vm.hasPlannedMaterials
                                        ? 'Add planned material'
                                        : 'Add item',
                                  ),
                                ),
                                if (vm.hasPlannedMaterials)
                                  TextButton.icon(
                                    onPressed: vm.addUnplannedLine,
                                    icon: const Icon(
                                      Icons.add_circle_outline,
                                      size: 18,
                                    ),
                                    label: const Text('Add unplanned material'),
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

class _PlannedLineCard extends StatelessWidget {
  const _PlannedLineCard({super.key, required this.vm, required this.line});

  final MaterialRequestFormViewModel vm;
  final LineDraft line;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final options = vm.availablePlannedMaterials;
    final selected = vm.plannedMaterialById(line.plannedMaterialId);
    final remaining = selected == null
        ? null
        : vm.remainingFor(selected, excluding: line);
    final overPlan = vm.isLineOverPlan(line);
    final excess = (remaining != null && overPlan)
        ? line.quantity - remaining.clamp(0, double.infinity)
        : 0.0;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted.withValues(alpha: 0.5),
        borderRadius: AppRadii.mdAll,
        border: Border.all(
          color: overPlan ? AppColors.warning : cs.outlineVariant,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 4,
                child: DropdownButtonFormField<int?>(
                  key: ValueKey(
                    'pm-${vm.categoryId}-${line.plannedMaterialId}',
                  ),
                  initialValue: options.any((p) => p.id == line.plannedMaterialId)
                      ? line.plannedMaterialId
                      : null,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Planned material (DUPA)',
                  ),
                  items: [
                    for (final pm in options)
                      DropdownMenuItem<int?>(
                        value: pm.id,
                        child: Text(
                          '${pm.name} · Rem: ${Formatters.number(pm.remainingQty.clamp(0, double.infinity))} / ${Formatters.number(pm.plannedQty)} ${pm.unit}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  validator: (v) =>
                      v == null ? 'Choose a planned material.' : null,
                  onChanged: (id) => vm.selectPlannedMaterial(
                    line,
                    vm.plannedMaterialById(id),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                flex: 2,
                child: TextFormField(
                  initialValue: line.quantity > 0
                      ? InputParsers.amountText(line.quantity)
                      : '',
                  decoration: InputDecoration(
                    labelText: 'Qty',
                    suffixText: line.unit.isEmpty ? null : line.unit,
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  validator: (v) =>
                      ProcurementRules.validateQuantity(InputParsers.amount(v)),
                  onChanged: (v) {
                    line.quantity = InputParsers.amount(v) ?? 0;
                    vm.changed();
                  },
                ),
              ),
              IconButton(
                tooltip: 'Remove item',
                onPressed: () => vm.removeLine(line),
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
          if (selected != null && remaining != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: overPlan
                    ? AppColors.warningContainer
                    : AppColors.successContainer,
                borderRadius: AppRadii.smAll,
              ),
              child: Row(
                children: [
                  Icon(
                    overPlan
                        ? Icons.warning_amber_rounded
                        : Icons.check_circle_outline,
                    size: 16,
                    color: overPlan ? AppColors.warning : AppColors.success,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      overPlan
                          ? 'Exceeds DUPA plan by ${Formatters.number(excess)} ${selected.unit} '
                                '(Remaining: ${Formatters.number(remaining.clamp(0, double.infinity))} of ${Formatters.number(selected.plannedQty)} ${selected.unit})'
                          : 'Within DUPA plan · Remaining: ${Formatters.number(remaining.clamp(0, double.infinity))} '
                                'of ${Formatters.number(selected.plannedQty)} ${selected.unit}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: overPlan ? AppColors.warning : AppColors.success,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (overPlan) ...[
            const SizedBox(height: AppSpacing.sm),
            TextFormField(
              initialValue: line.overPlanReason,
              decoration: const InputDecoration(
                labelText: 'Reason for exceeding DUPA plan *',
                hintText: 'e.g. Damaged on site / extra footing depth',
              ),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'Explain why more than planned is needed.'
                  : null,
              onChanged: (v) {
                line.overPlanReason = v;
              },
            ),
          ],
        ],
      ),
    );
  }
}

class _UnplannedLineCard extends StatelessWidget {
  const _UnplannedLineCard({super.key, required this.vm, required this.line});

  final MaterialRequestFormViewModel vm;
  final LineDraft line;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.warningContainer.withValues(alpha: 0.35),
        borderRadius: AppRadii.mdAll,
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: const BoxDecoration(
                  color: AppColors.warningContainer,
                  borderRadius: AppRadii.smAll,
                ),
                child: const Text(
                  'Unplanned (not in DUPA)',
                  style: TextStyle(
                    color: AppColors.warning,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          ProcurementLineEditor(
            line: line,
            nameLabel: 'Unplanned item',
            unitChoices: commonUnits,
            suggestions: vm.lookups.materials.values.toList(),
            onChanged: vm.changed,
            onRemove: () => vm.removeLine(line),
          ),
          TextFormField(
            initialValue: line.overPlanReason,
            decoration: const InputDecoration(
              labelText: 'Reason (why not in DUPA) *',
              hintText: 'e.g. Emergency site safety requirement',
            ),
            validator: (v) => (v == null || v.trim().isEmpty)
                ? 'Explain why this unplanned item is needed.'
                : null,
            onChanged: (v) {
              line.overPlanReason = v;
            },
          ),
        ],
      ),
    );
  }
}

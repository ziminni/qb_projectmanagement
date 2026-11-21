import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_fonts.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/utils/app_messages.dart';
import '../../../core/utils/finance_access.dart';
import '../../../core/utils/input_parsers.dart';
import '../../../core/utils/page_padding.dart';
import '../../../data/models/variation_order.dart';
import '../../../data/services/billing_rules.dart';
import '../../../routes/routes.dart';
import '../../../shared/widgets/app_action_bar.dart';
import '../../../shared/widgets/app_empty_state.dart';
import '../../../shared/widgets/app_section_card.dart';
import '../viewmodels/variation_order_form_viewmodel.dart';
import '../widgets/vo_photo_attachments.dart';

/// Raise or edit a variation order: added work, removed work or a design
/// change, linked to an item of work and task (existing to-do or custom text),
/// with its cost, schedule impact, and photo evidence.
class VariationOrderFormPage extends StatefulWidget {
  const VariationOrderFormPage({super.key, this.voId, this.projectId});

  final int? voId;
  final int? projectId;

  @override
  State<VariationOrderFormPage> createState() => _VariationOrderFormPageState();
}

class _VariationOrderFormPageState extends State<VariationOrderFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _customTask = TextEditingController();
  final _description = TextEditingController();
  final _amount = TextEditingController();
  final _days = TextEditingController(text: '0');
  late final _vm = VariationOrderFormViewModel(
    voId: widget.voId,
    initialProjectId: widget.projectId,
    session: getIt(),
    projects: getIt(),
    billing: getIt(),
    schedule: getIt(),
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
    _customTask.dispose();
    _description.dispose();
    _amount.dispose();
    _days.dispose();
    _vm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final isNew = _vm.existing == null;
    final ok = await reportAction(
      context,
      _vm.save(
        description: _description.text,
        customTask: _customTask.text,
        amount: canSeeFinance() ? InputParsers.amount(_amount.text)! : 0,
        daysImpact: InputParsers.integer(_days.text) ?? 0,
      ),
    );
    if (ok && mounted) {
      final voLabel = _vm.savedVoNo ?? 'Variation order';
      showSuccessAlert(
        context,
        isNew
            ? '$voLabel added as draft. Review and send to the client when ready.'
            : '$voLabel draft updated.',
      );
      context.go(AppRoutes.variationOrder(_vm.savedId!));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _vm,
      child: Consumer<VariationOrderFormViewModel>(
        builder: (context, vm, _) {
          final finance = canSeeFinance();
          final cs = Theme.of(context).colorScheme;
          final textTheme = Theme.of(context).textTheme;
          if (vm.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (vm.error != null) return AppEmptyState(message: vm.error!);

          final wide = MediaQuery.sizeOf(context).width >= 900;
          final todos = vm.todosForSelectedCategory;
          final effectiveTodoValue =
              vm.todoSelection ==
                      VariationOrderFormViewModel.customTaskSentinel ||
                  todos.any((t) => t.id == vm.todoSelection)
              ? vm.todoSelection
              : null;

          final itemOfWorkField = DropdownButtonFormField<int?>(
            key: ValueKey('vo-category-${vm.projectId}-${vm.categoryId}'),
            initialValue: vm.categories.any((c) => c.id == vm.categoryId)
                ? vm.categoryId
                : null,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Item of work'),
            items: [
              const DropdownMenuItem<int?>(
                value: null,
                child: Text('General (not tied to an item)'),
              ),
              for (final c in vm.categories)
                DropdownMenuItem<int?>(value: c.id, child: Text(c.name)),
            ],
            onChanged: vm.isLoadingWorkItems ? null : vm.setCategory,
          );

          final taskField = DropdownButtonFormField<int?>(
            key: ValueKey(
              'vo-todo-${vm.projectId}-${vm.categoryId}-$effectiveTodoValue',
            ),
            initialValue: effectiveTodoValue,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Task (to-do)'),
            items: [
              const DropdownMenuItem<int?>(
                value: null,
                child: Text('None / Whole item of work'),
              ),
              for (final t in todos)
                DropdownMenuItem<int?>(
                  value: t.id,
                  child: Text(t.title, overflow: TextOverflow.ellipsis),
                ),
              const DropdownMenuItem<int?>(
                value: VariationOrderFormViewModel.customTaskSentinel,
                child: Text('Custom task (type below)'),
              ),
            ],
            onChanged: vm.isLoadingWorkItems ? null : vm.setTodoSelection,
          );

          final scopeCard = AppSectionCard(
            title: 'Scope & change details',
            subtitle: 'Select the project, change type, and affected work item',
            icon: Icons.difference_outlined,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<int>(
                  key: ValueKey('vo-project-${vm.projectId}'),
                  initialValue: vm.projectId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Project'),
                  items: [
                    for (final p in vm.projectOptions)
                      DropdownMenuItem(
                        value: p.id,
                        child: Text('${p.code} · ${p.name}'),
                      ),
                  ],
                  onChanged: vm.existing == null ? vm.setProject : null,
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
                const SizedBox(height: AppSpacing.lg),
                LayoutBuilder(
                  builder: (context, constraints) {
                    if (constraints.maxWidth >= 520) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: itemOfWorkField),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(child: taskField),
                        ],
                      );
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        itemOfWorkField,
                        const SizedBox(height: AppSpacing.md),
                        taskField,
                      ],
                    );
                  },
                ),
                if (vm.isCustomTask) ...[
                  const SizedBox(height: AppSpacing.md),
                  TextFormField(
                    key: const ValueKey('vo-custom-task'),
                    controller: _customTask,
                    decoration: const InputDecoration(
                      labelText: 'Custom task name',
                      hintText: 'Enter the specific task not listed above',
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Enter a custom task or choose an existing to-do.'
                        : null,
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _description,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Description of the change',
                    hintText:
                        'Describe what is changing, quantities, or site context',
                    alignLabelWithHint: true,
                  ),
                  validator: BillingRules.validateVoDescription,
                ),
              ],
            ),
          );

          final photoCard = AppSectionCard(
            title: 'Photo evidence',
            subtitle: vm.type == VariationOrderType.change
                ? 'Compare the current condition with the proposed design'
                : 'Attach clear site photos supporting this variation order',
            icon: Icons.photo_library_outlined,
            child: VoPhotoPickerSection(
              type: vm.type,
              primaryAttachments: vm.primaryAttachments,
              secondaryAttachments: vm.secondaryAttachments,
              onAddPrimary: vm.addPrimaryAttachments,
              onRemovePrimary: vm.removePrimaryAttachment,
              onAddSecondary: vm.addSecondaryAttachments,
              onRemoveSecondary: vm.removeSecondaryAttachment,
            ),
          );

          final impactCard = AppSectionCard(
            title: 'Cost & schedule impact',
            subtitle: finance
                ? 'Recorded on the variation order for client review'
                : 'Schedule change; the project manager sets the price',
            icon: Icons.calculate_outlined,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (finance) ...[
                  TextFormField(
                    controller: _amount,
                    decoration: InputDecoration(
                      labelText: vm.type == VariationOrderType.change
                          ? 'Cost impact (− for savings)'
                          : vm.type == VariationOrderType.deductive
                          ? 'Amount deducted'
                          : 'Amount added',
                      prefixIcon: SizedBox(
                        width: 36,
                        child: Center(
                          child: Text(
                            '₱',
                            style: TextStyle(
                              fontFamily: AppFonts.body,
                              fontFamilyFallback: AppFonts.fallback,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                      prefixIconConstraints: const BoxConstraints(
                        minWidth: 36,
                        minHeight: 0,
                      ),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                    validator: (v) => BillingRules.validateVoAmount(
                      vm.type,
                      InputParsers.amount(v),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],
                TextFormField(
                  controller: _days,
                  decoration: const InputDecoration(
                    labelText: 'Additional days (schedule change)',
                    helperText: 'Days added (+) or saved (−); 0 for no change',
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    signed: true,
                  ),
                  validator: (v) => InputParsers.integer(v) == null
                      ? 'Enter whole days.'
                      : null,
                ),
              ],
            ),
          );

          return Form(
            key: _formKey,
            child: Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: pagePadding(context),
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            vm.existing == null
                                ? 'Raise a variation order'
                                : 'Edit ${vm.existing!.voNo}',
                            style: textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            vm.existing == null
                                ? 'Document the scope change, attach site photos, and record cost and schedule impact.'
                                : 'Update this proposed variation order before sending it to the client.',
                            style: textTheme.bodyMedium?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      if (wide)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 13,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  scopeCard,
                                  const SizedBox(height: AppSpacing.lg),
                                  photoCard,
                                ],
                              ),
                            ),
                            const SizedBox(width: AppSpacing.xl),
                            Expanded(flex: 7, child: impactCard),
                          ],
                        )
                      else ...[
                        scopeCard,
                        const SizedBox(height: AppSpacing.lg),
                        impactCard,
                        const SizedBox(height: AppSpacing.lg),
                        photoCard,
                      ],
                    ],
                  ),
                ),
                AppActionBar(
                  hint: finance
                      ? 'You send the VO to the client for approval.'
                      : 'The project manager prices the change and sends it to the client.',
                  children: [
                    FilledButton(
                      onPressed: vm.isBusy ? null : _save,
                      child: const Text('Draft'),
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

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/utils/app_messages.dart';
import '../../../core/utils/page_padding.dart';
import '../../../data/models/category.dart';
import '../../../data/models/todo.dart';
import '../../../data/services/progress_calculator.dart';
import '../../../shared/widgets/app_confirm_dialog.dart';
import '../viewmodels/schedule_viewmodel.dart';
import '../widgets/dupa_breakdown_dialog.dart';
import '../widgets/dupa_import_dialog.dart';
import '../widgets/items_import_dialog.dart';
import '../widgets/schedule_budget_warning.dart';
import '../widgets/schedule_category_card.dart';
import '../widgets/schedule_category_form_dialog.dart';
import '../widgets/schedule_progress_summary.dart';
import '../widgets/schedule_todo_form_dialog.dart';
import '../widgets/schedule_unverify_dialog.dart';

/// The "Categories and to-dos" project tab. The same page serves every role;
/// the view model decides which controls appear.
class ScheduleCategoriesPage extends StatelessWidget {
  const ScheduleCategoriesPage({super.key, required this.projectId});

  final int projectId;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      key: ValueKey(projectId),
      create: (_) => ScheduleViewModel(
        projectId: projectId,
        session: getIt(),
        projects: getIt(),
        schedule: getIt(),
        users: getIt(),
        company: getIt(),
      )..load(),
      builder: (context, _) {
        final vm = context.watch<ScheduleViewModel>();
        if (vm.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        if (vm.error != null) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Text(vm.error!, textAlign: TextAlign.center),
            ),
          );
        }
        return Column(
          children: [
            if (vm.isBusy) const LinearProgressIndicator(minHeight: 2),
            Expanded(child: _categoriesTab(context, vm)),
          ],
        );
      },
    );
  }

  Widget _categoriesTab(BuildContext context, ScheduleViewModel vm) {
    final progress = vm.progress!;
    final warning = vm.budgetWarning;
    final enabled = !vm.isBusy;
    return ListView(
      padding: pagePadding(context),
      children: [
        ..._overview(vm),
        if (warning != null) ...[
          ScheduleBudgetWarning(message: warning),
          const SizedBox(height: AppSpacing.lg),
        ],
        if (progress.categories.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
            child: Text(
              vm.canEdit
                  ? 'No categories yet. Add the first one, e.g. Foundation.'
                  : 'The schedule has not been set up yet.',
              textAlign: TextAlign.center,
            ),
          ),
        for (final item in progress.categories) ...[
          ScheduleCategoryCard(
            key: ValueKey(item.category.id),
            item: item,
            showCosts: vm.showCosts,
            enabled: enabled,
            userName: vm.userName,
            onEdit: vm.canEdit
                ? () => _editCategory(context, vm, item.category)
                : null,
            onDelete: vm.canEdit
                ? () => _deleteCategory(context, vm, item.category)
                : null,
            onAddTodo: vm.canEdit ? () => _addTodo(context, vm, item) : null,
            onImportDupa: vm.canEdit
                ? () => _importItemDupa(context, vm, item.category)
                : null,
            onViewDupa: vm.showCosts && item.category.hasDupaBreakdown
                ? () => DupaBreakdownDialog.show(
                    context,
                    category: item.category,
                  )
                : null,
            onSetDone: vm.canMarkDone
                ? (todo, done) => _report(context, vm.setDone(todo, done))
                : null,
            onVerify: vm.canVerify
                ? (todo) => _report(context, vm.verify(todo))
                : null,
            onUnverify: vm.canVerify
                ? (todo) => _unverify(context, vm, todo)
                : null,
            onEditTodo: vm.canEdit
                ? (todo) => _editTodo(context, vm, item, todo)
                : null,
            onDeleteTodo: vm.canEdit
                ? (todo) => _deleteTodo(context, vm, todo)
                : null,
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        if (vm.canEdit)
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.sm,
            children: [
              OutlinedButton.icon(
                onPressed: enabled ? () => _addCategory(context, vm) : null,
                icon: const Icon(Icons.add),
                label: const Text('Add item of work'),
              ),
              FilledButton.tonalIcon(
                onPressed: enabled ? () => _importItems(context, vm) : null,
                icon: const Icon(Icons.upload_file_rounded, size: 18),
                label: const Text('Import Excel'),
              ),
            ],
          ),
      ],
    );
  }

  List<Widget> _overview(ScheduleViewModel vm) => [
    ScheduleProgressSummary(
      progress: vm.progress!,
      showCosts: vm.showCosts,
      behindThreshold: vm.behindThreshold,
    ),
    const SizedBox(height: AppSpacing.lg),
  ];

  Future<void> _importItemDupa(
    BuildContext context,
    ScheduleViewModel vm,
    Category category,
  ) async {
    final result = await DupaImportDialog.show(
      context,
      projectId: projectId,
      categoryId: category.id,
      categoryName: category.name,
    );
    if (result == null || !context.mounted) return;
    showSuccessAlert(
      context,
      'Imported DUPA for ${category.name} '
      '(${result.materialsImported} planned material${result.materialsImported == 1 ? '' : 's'}).',
    );
    await vm.load();
  }

  Future<void> _importItems(BuildContext context, ScheduleViewModel vm) async {
    final count = await ItemsImportDialog.show(context, projectId: projectId);
    if (count == null || !context.mounted) return;
    showSuccessAlert(
      context,
      'Imported $count item${count == 1 ? '' : 's'} of work. View them on the Gantt chart.',
    );
    await vm.load();
  }

  Future<void> _addCategory(BuildContext context, ScheduleViewModel vm) async {
    final result = await ScheduleCategoryFormDialog.show(
      context,
      validateBudgetTotal: vm.validateBudgetTotal,
    );
    if (result == null || !context.mounted) return;
    await _report(
      context,
      vm.addCategory(
        name: result.name,
        budget: result.budget,
        plannedWeeks: result.plannedWeeks,
        plannedDays: result.plannedDays,
      ),
    );
  }

  Future<void> _editCategory(
    BuildContext context,
    ScheduleViewModel vm,
    Category category,
  ) async {
    final result = await ScheduleCategoryFormDialog.show(
      context,
      initialName: category.name,
      initialBudget: category.budget,
      initialWeeks: category.plannedWeeks,
      initialDays: category.plannedDays,
      validateBudgetTotal: (budget) =>
          vm.validateBudgetTotal(budget, excludingCategoryId: category.id),
    );
    if (result == null || !context.mounted) return;
    await _report(
      context,
      vm.updateCategory(
        category,
        name: result.name,
        budget: result.budget,
        plannedWeeks: result.plannedWeeks,
        plannedDays: result.plannedDays,
      ),
    );
  }

  Future<void> _deleteCategory(
    BuildContext context,
    ScheduleViewModel vm,
    Category category,
  ) async {
    final blocked = vm.canDeleteCategory(category);
    if (blocked != null) {
      _showMessage(context, blocked);
      return;
    }
    final confirmed = await showAppConfirmDialog(
      context,
      title: 'Delete ${category.name}?',
      message: 'The category and all of its to-dos will be deleted.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    await _report(context, vm.deleteCategory(category));
  }

  Future<void> _addTodo(
    BuildContext context,
    ScheduleViewModel vm,
    CategoryProgress item,
  ) async {
    final project = vm.project!;
    final firstDate = item.category.startDate ?? project.startDate;
    final lastDate = item.category.endDate ?? project.targetEndDate;
    final result = await ScheduleTodoFormDialog.show(
      context,
      categoryName: item.category.name,
      firstDate: firstDate,
      lastDate: lastDate,
      validateDates: (s, e) =>
          vm.validateTodoDates(s, e, category: item.category),
      initialStart: firstDate,
      initialEnd: lastDate,
    );
    if (result == null || !context.mounted) return;
    await _report(
      context,
      vm.addTodo(
        categoryId: item.category.id,
        title: result.title,
        start: result.start,
        end: result.end,
      ),
    );
  }

  Future<void> _editTodo(
    BuildContext context,
    ScheduleViewModel vm,
    CategoryProgress item,
    Todo todo,
  ) async {
    final project = vm.project!;
    final firstDate = item.category.startDate ?? project.startDate;
    final lastDate = item.category.endDate ?? project.targetEndDate;
    final result = await ScheduleTodoFormDialog.show(
      context,
      categoryName: item.category.name,
      firstDate: firstDate,
      lastDate: lastDate,
      validateDates: (s, e) =>
          vm.validateTodoDates(s, e, category: item.category),
      initialTitle: todo.title,
      initialStart: todo.startDate,
      initialEnd: todo.endDate,
    );
    if (result == null || !context.mounted) return;
    await _report(
      context,
      vm.updateTodo(
        todo,
        title: result.title,
        start: result.start,
        end: result.end,
      ),
    );
  }

  Future<void> _deleteTodo(
    BuildContext context,
    ScheduleViewModel vm,
    Todo todo,
  ) async {
    final confirmed = await showAppConfirmDialog(
      context,
      title: 'Delete to-do?',
      message: '"${todo.title}" will be removed from the schedule.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    await _report(context, vm.deleteTodo(todo));
  }

  Future<void> _unverify(
    BuildContext context,
    ScheduleViewModel vm,
    Todo todo,
  ) async {
    final reason = await ScheduleUnverifyDialog.show(context, todo);
    if (reason == null || !context.mounted) return;
    await _report(context, vm.unverify(todo, reason));
  }

  /// Awaits a view-model action and shows its error, if any.
  Future<void> _report(BuildContext context, Future<String?> action) async {
    final error = await action;
    if (error != null && context.mounted) _showMessage(context, error);
  }

  void _showMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

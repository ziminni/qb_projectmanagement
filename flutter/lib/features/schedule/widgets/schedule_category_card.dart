import 'package:flutter/material.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/models/todo.dart';
import '../../../data/services/progress_calculator.dart';
import '../../../shared/widgets/app_progress_bar.dart';
import 'schedule_category_status_chip.dart';
import 'schedule_todo_tile.dart';

enum _CategoryAction { edit, delete }

/// A category with its derived status, progress and to-do checklist.
class ScheduleCategoryCard extends StatefulWidget {
  const ScheduleCategoryCard({
    super.key,
    required this.item,
    required this.showCosts,
    required this.enabled,
    required this.userName,
    this.onEdit,
    this.onDelete,
    this.onAddTodo,
    this.onImportDupa,
    this.onViewDupa,
    this.onSetDone,
    this.onVerify,
    this.onUnverify,
    this.onEditTodo,
    this.onDeleteTodo,
  });

  final CategoryProgress item;
  final bool showCosts;
  final bool enabled;
  final String? Function(int? id) userName;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onAddTodo;
  final VoidCallback? onImportDupa;
  final VoidCallback? onViewDupa;
  final void Function(Todo todo, bool done)? onSetDone;
  final ValueChanged<Todo>? onVerify;
  final ValueChanged<Todo>? onUnverify;
  final ValueChanged<Todo>? onEditTodo;
  final ValueChanged<Todo>? onDeleteTodo;

  @override
  State<ScheduleCategoryCard> createState() => _ScheduleCategoryCardState();
}

class _ScheduleCategoryCardState extends State<ScheduleCategoryCard> {
  late bool _expanded = widget.item.status != CategoryStatus.completed;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final textTheme = Theme.of(context).textTheme;
    final hasMenu = widget.onEdit != null || widget.onDelete != null;

    final counts = StringBuffer(
      '${item.verifiedTodos} of ${item.totalTodos} to-dos verified',
    );
    if (item.awaitingVerification > 0) {
      counts.write(' · ${item.awaitingVerification} awaiting verification');
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.sm,
                AppSpacing.md,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Wrap(
                          spacing: AppSpacing.sm,
                          runSpacing: AppSpacing.xs,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              item.category.name,
                              style: textTheme.titleMedium,
                            ),
                            ScheduleCategoryStatusChip(status: item.status),
                          ],
                        ),
                      ),
                      Text(
                        Formatters.percent(item.progress),
                        style: textTheme.titleMedium?.merge(
                          AppTextStyles.numeric,
                        ),
                      ),
                      if (hasMenu)
                        PopupMenuButton<_CategoryAction>(
                          tooltip: 'Category actions',
                          enabled: widget.enabled,
                          onSelected: (a) => switch (a) {
                            _CategoryAction.edit => widget.onEdit?.call(),
                            _CategoryAction.delete => widget.onDelete?.call(),
                          },
                          itemBuilder: (context) => [
                            if (widget.onEdit != null)
                              const PopupMenuItem(
                                value: _CategoryAction.edit,
                                child: Text('Edit category'),
                              ),
                            if (widget.onDelete != null)
                              const PopupMenuItem(
                                value: _CategoryAction.delete,
                                child: Text('Delete category'),
                              ),
                          ],
                        ),
                      Icon(_expanded ? Icons.expand_less : Icons.expand_more),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  AppProgressBar(value: item.progress, height: 8),
                  const SizedBox(height: AppSpacing.sm),
                  Text(counts.toString(), style: textTheme.bodySmall),
                  if (widget.showCosts) ...[
                    Text(
                      item.category.hasBudget
                          ? 'Planned cost ${Formatters.peso(item.category.budget!)} · '
                                'weight ${Formatters.percent(item.weight)}'
                          : 'No planned cost · weight ${Formatters.percent(item.weight)}',
                      style: textTheme.bodySmall,
                    ),
                    if (item.category.hasCostBreakdown)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          'Labor ${Formatters.peso(item.category.laborBudget ?? 0)} · '
                          'Equipment ${Formatters.peso(item.category.equipmentBudget ?? 0)} · '
                          'Materials ${Formatters.peso(item.category.materialBudget ?? 0)}',
                          style: textTheme.bodySmall?.copyWith(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            const Divider(height: 1),
            if (item.todos.isEmpty)
              Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Text('No to-dos yet.', style: textTheme.bodySmall),
              ),
            for (final todo in item.todos)
              ScheduleTodoTile(
                todo: todo,
                userName: widget.userName,
                enabled: widget.enabled,
                onSetDone: widget.onSetDone == null
                    ? null
                    : (done) => widget.onSetDone!(todo, done),
                onVerify: widget.onVerify == null
                    ? null
                    : () => widget.onVerify!(todo),
                onUnverify: widget.onUnverify == null
                    ? null
                    : () => widget.onUnverify!(todo),
                onEdit: widget.onEditTodo == null
                    ? null
                    : () => widget.onEditTodo!(todo),
                onDelete: widget.onDeleteTodo == null
                    ? null
                    : () => widget.onDeleteTodo!(todo),
              ),
            if (widget.onAddTodo != null ||
                widget.onImportDupa != null ||
                widget.onViewDupa != null)
              Padding(
                padding: const EdgeInsets.all(AppSpacing.sm),
                child: Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.xs,
                  children: [
                    if (widget.onAddTodo != null)
                      TextButton.icon(
                        onPressed: widget.enabled ? widget.onAddTodo : null,
                        icon: const Icon(Icons.add),
                        label: const Text('Add to-do'),
                      ),
                    if (widget.onImportDupa != null)
                      TextButton.icon(
                        onPressed: widget.enabled ? widget.onImportDupa : null,
                        icon: const Icon(Icons.table_chart_outlined, size: 18),
                        label: Text(
                          item.category.hasCostBreakdown
                              ? 'Update DUPA'
                              : 'Import DUPA',
                        ),
                      ),
                    if (widget.onViewDupa != null &&
                        widget.showCosts &&
                        item.category.hasDupaBreakdown)
                      TextButton.icon(
                        onPressed: widget.onViewDupa,
                        icon: const Icon(Icons.receipt_long_outlined, size: 18),
                        label: const Text('View DUPA (A–J)'),
                      ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

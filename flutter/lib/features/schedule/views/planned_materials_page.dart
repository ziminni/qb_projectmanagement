import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_radii.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/utils/app_messages.dart';
import '../../../core/utils/finance_access.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/input_parsers.dart';
import '../../../core/utils/page_padding.dart';
import '../../../data/models/app_role.dart';
import '../../../data/models/category.dart';
import '../../../data/models/planned_material.dart';
import '../../../data/repositories/schedule_repository.dart';
import '../../../data/services/session_service.dart';
import '../../../routes/routes.dart';
import '../../../shared/widgets/app_confirm_dialog.dart';
import '../../../shared/widgets/app_empty_state.dart';
import '../../../shared/widgets/app_figure.dart';
import '../../../shared/widgets/app_section_card.dart';
import '../widgets/dupa_import_dialog.dart';

/// Project "Planned materials" tab (Bill of Materials / DUPA Section C),
/// grouped by Item of Work with live Planned vs. Requested vs. Delivered
/// tracking. Unit costs and totals are hidden from the Foreman.
class PlannedMaterialsPage extends StatefulWidget {
  const PlannedMaterialsPage({super.key, required this.projectId});

  final int projectId;

  @override
  State<PlannedMaterialsPage> createState() => _PlannedMaterialsPageState();
}

class _PlannedMaterialsPageState extends State<PlannedMaterialsPage> {
  final _schedule = getIt<ScheduleRepository>();
  bool _loading = true;
  String? _error;
  List<Category> _categories = const [];
  List<PlannedMaterial> _items = const [];

  AppRole get _role => getIt<SessionService>().activeRole!;
  bool get _canEdit => _role == AppRole.owner;
  bool get _isForeman => _role == AppRole.siteEngineer;
  bool get _showCosts => canSeeFinance();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _schedule.getCategories(widget.projectId),
        _schedule.getPlannedMaterials(widget.projectId),
      ]);
      if (!mounted) return;
      setState(() {
        _categories = results[0] as List<Category>;
        _items = results[1] as List<PlannedMaterial>;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load planned materials. $e';
        _loading = false;
      });
    }
  }

  Future<void> _importDupa() async {
    final result = await DupaImportDialog.show(
      context,
      projectId: widget.projectId,
    );
    if (result == null || !mounted) return;
    showSuccessAlert(
      context,
      'Imported ${result.itemsImported} item(s) of work and '
      '${result.materialsImported} planned material(s).',
    );
    await _load();
  }

  Future<void> _addOrEdit({PlannedMaterial? initial, int? categoryId}) async {
    final saved = await showDialog<PlannedMaterial>(
      context: context,
      builder: (_) => _PlannedMaterialFormDialog(
        projectId: widget.projectId,
        categories: _categories,
        initial: initial,
        initialCategoryId: categoryId,
        showCosts: _showCosts,
      ),
    );
    if (saved == null || !mounted) return;
    try {
      await _schedule.savePlannedMaterial(saved);
      if (!mounted) return;
      showSuccessAlert(
        context,
        initial == null ? 'Planned material added.' : 'Planned material updated.',
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      showAppMessage(context, '$e');
    }
  }

  Future<void> _delete(PlannedMaterial item) async {
    final ok = await showAppConfirmDialog(
      context,
      title: 'Remove planned material?',
      message: 'Remove "${item.name}" from this project\'s planned materials?',
      confirmLabel: 'Remove',
      destructive: true,
    );
    if (!ok || !mounted) return;
    try {
      await _schedule.deletePlannedMaterial(item.id);
      if (!mounted) return;
      showSuccessAlert(context, 'Planned material removed.');
      await _load();
    } catch (e) {
      if (!mounted) return;
      showAppMessage(context, '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return AppEmptyState(message: _error!);

    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final totalCost = _items.fold<double>(0, (s, m) => s + m.amount);
    final overPlanCount = _items.where((m) => m.isOverPlan).length;

    // Group items by categoryId (null = Unassigned / General).
    final grouped = <int?, List<PlannedMaterial>>{};
    for (final item in _items) {
      grouped.putIfAbsent(item.categoryId, () => []).add(item);
    }
    final orderedCategoryIds = <int?>[
      for (final c in _categories)
        if (grouped.containsKey(c.id)) c.id,
      for (final key in grouped.keys)
        if (key == null || !_categories.any((c) => c.id == key)) key,
    ];

    String groupTitle(int? catId) {
      if (catId == null) return 'General / Unassigned';
      for (final c in _categories) {
        if (c.id == catId) return c.name;
      }
      return grouped[catId]?.first.categoryName ?? 'Item of work';
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: pagePadding(context),
        children: [
          AppSectionCard(
            title: 'Planned materials (Bill of Materials)',
            subtitle: _isForeman
                ? 'Reference quantities from the project plan — request materials directly below'
                : 'DUPA Section C material plan grouped by Item of Work',
            icon: Icons.inventory_outlined,
            trailing: Wrap(
              spacing: AppSpacing.sm,
              children: [
                if (_canEdit) ...[
                  OutlinedButton.icon(
                    onPressed: _importDupa,
                    icon: const Icon(Icons.upload_file_rounded, size: 18),
                    label: const Text('Import DUPA Excel'),
                  ),
                  FilledButton.icon(
                    onPressed: () => _addOrEdit(),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add material'),
                  ),
                ],
                if (_isForeman)
                  FilledButton.icon(
                    onPressed: () => context.go(
                      '${AppRoutes.materialRequestNew}?projectId=${widget.projectId}',
                    ),
                    icon: const Icon(Icons.add_shopping_cart_rounded, size: 18),
                    label: const Text('Request materials'),
                  ),
              ],
            ),
            child: Wrap(
              spacing: AppSpacing.xl,
              runSpacing: AppSpacing.md,
              children: [
                AppFigure(
                  label: 'Items of work',
                  value: '${orderedCategoryIds.length}',
                ),
                AppFigure(
                  label: 'Planned materials',
                  value: '${_items.length}',
                ),
                if (_showCosts)
                  AppFigure(
                    label: 'Planned material cost',
                    value: Formatters.peso(totalCost),
                  ),
                AppFigure(
                  label: 'Over-plan items',
                  value: '$overPlanCount',
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          if (_items.isEmpty)
            AppEmptyState(
              icon: Icons.inventory_2_outlined,
              message: _canEdit
                  ? 'No planned materials yet. Import a DPWH DUPA Excel (.xlsx) or add materials manually.'
                  : 'No planned materials have been set up for this project yet.',
            ),
          for (final catId in orderedCategoryIds) ...[
            _CategoryMaterialCard(
              title: groupTitle(catId),
              items: grouped[catId]!,
              showCosts: _showCosts,
              canEdit: _canEdit,
              isForeman: _isForeman,
              onAddHere: _canEdit ? () => _addOrEdit(categoryId: catId) : null,
              onEdit: _canEdit ? (m) => _addOrEdit(initial: m) : null,
              onDelete: _canEdit ? _delete : null,
              onRequest: _isForeman
                  ? () => context.go(
                      '${AppRoutes.materialRequestNew}?projectId=${widget.projectId}',
                    )
                  : null,
              cs: cs,
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          const SizedBox(height: AppSpacing.lg),
        ],
      ),
    );
  }
}

class _CategoryMaterialCard extends StatelessWidget {
  const _CategoryMaterialCard({
    required this.title,
    required this.items,
    required this.showCosts,
    required this.canEdit,
    required this.isForeman,
    required this.cs,
    this.onAddHere,
    this.onEdit,
    this.onDelete,
    this.onRequest,
  });

  final String title;
  final List<PlannedMaterial> items;
  final bool showCosts;
  final bool canEdit;
  final bool isForeman;
  final ColorScheme cs;
  final VoidCallback? onAddHere;
  final ValueChanged<PlannedMaterial>? onEdit;
  final ValueChanged<PlannedMaterial>? onDelete;
  final VoidCallback? onRequest;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtotal = items.fold<double>(0, (s, m) => s + m.amount);

    return AppSectionCard(
      title: title,
      subtitle: showCosts
          ? '${items.length} material${items.length == 1 ? '' : 's'} · Planned subtotal: ${Formatters.peso(subtotal)}'
          : '${items.length} material${items.length == 1 ? '' : 's'}',
      padding: EdgeInsets.zero,
      trailing: onAddHere != null
          ? TextButton.icon(
              onPressed: onAddHere,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add'),
            )
          : null,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowHeight: 40,
          dataRowMinHeight: 44,
          dataRowMaxHeight: 56,
          columns: [
            const DataColumn(label: Text('Material & Specification')),
            const DataColumn(label: Text('Unit')),
            const DataColumn(label: Text('Planned'), numeric: true),
            const DataColumn(label: Text('Requested'), numeric: true),
            const DataColumn(label: Text('Delivered'), numeric: true),
            const DataColumn(label: Text('Remaining'), numeric: true),
            if (showCosts) ...[
              const DataColumn(label: Text('Unit Cost'), numeric: true),
              const DataColumn(label: Text('Subtotal'), numeric: true),
            ],
            if (canEdit || isForeman) const DataColumn(label: Text('')),
          ],
          rows: [
            for (final m in items)
              DataRow(
                cells: [
                  DataCell(
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 260),
                          child: Text(
                            m.name,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (m.isOverPlan) ...[
                          const SizedBox(width: AppSpacing.xs),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: const BoxDecoration(
                              color: AppColors.warningContainer,
                              borderRadius: AppRadii.smAll,
                            ),
                            child: const Text(
                              'Over plan',
                              style: TextStyle(
                                color: AppColors.warning,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  DataCell(Text(m.unit)),
                  DataCell(Text(Formatters.number(m.plannedQty))),
                  DataCell(Text(Formatters.number(m.requestedQty))),
                  DataCell(Text(Formatters.number(m.deliveredQty))),
                  DataCell(
                    Text(
                      Formatters.number(m.remainingQty),
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: m.isOverPlan
                            ? AppColors.warning
                            : cs.onSurface,
                      ),
                    ),
                  ),
                  if (showCosts) ...[
                    DataCell(Text(Formatters.peso(m.unitCost))),
                    DataCell(
                      Text(
                        Formatters.peso(m.amount),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                  if (canEdit || isForeman)
                    DataCell(
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isForeman && onRequest != null)
                            TextButton(
                              onPressed: onRequest,
                              child: const Text('Request'),
                            ),
                          if (canEdit && onEdit != null)
                            IconButton(
                              tooltip: 'Edit',
                              icon: const Icon(Icons.edit_outlined, size: 18),
                              onPressed: () => onEdit!(m),
                            ),
                          if (canEdit && onDelete != null)
                            IconButton(
                              tooltip: 'Remove',
                              icon: const Icon(
                                Icons.delete_outline_rounded,
                                size: 18,
                              ),
                              onPressed: () => onDelete!(m),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _PlannedMaterialFormDialog extends StatefulWidget {
  const _PlannedMaterialFormDialog({
    required this.projectId,
    required this.categories,
    required this.showCosts,
    this.initial,
    this.initialCategoryId,
  });

  final int projectId;
  final List<Category> categories;
  final bool showCosts;
  final PlannedMaterial? initial;
  final int? initialCategoryId;

  @override
  State<_PlannedMaterialFormDialog> createState() =>
      _PlannedMaterialFormDialogState();
}

class _PlannedMaterialFormDialogState
    extends State<_PlannedMaterialFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.initial?.name);
  late final _unit = TextEditingController(text: widget.initial?.unit ?? 'pcs');
  late final _qty = TextEditingController(
    text: InputParsers.amountText(widget.initial?.plannedQty),
  );
  late final _cost = TextEditingController(
    text: InputParsers.amountText(widget.initial?.unitCost),
  );
  late int? _categoryId =
      widget.initial?.categoryId ??
      widget.initialCategoryId ??
      (widget.categories.isNotEmpty ? widget.categories.first.id : null);

  @override
  void dispose() {
    _name.dispose();
    _unit.dispose();
    _qty.dispose();
    _cost.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final qty = InputParsers.amount(_qty.text)!;
    final cost = widget.showCosts
        ? (InputParsers.amount(_cost.text) ?? 0)
        : (widget.initial?.unitCost ?? 0);
    final base =
        widget.initial ??
        PlannedMaterial(
          id: 0,
          projectId: widget.projectId,
          name: '',
          unit: 'pcs',
          plannedQty: qty,
        );
    Navigator.of(context).pop(
      base.copyWith(
        categoryId: () => _categoryId,
        name: _name.text.trim(),
        unit: _unit.text.trim().isEmpty ? 'pcs' : _unit.text.trim(),
        plannedQty: qty,
        unitCost: cost,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.initial == null
            ? 'Add planned material'
            : 'Edit planned material',
      ),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<int?>(
                  initialValue:
                      widget.categories.any((c) => c.id == _categoryId)
                      ? _categoryId
                      : null,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Item of work'),
                  items: [
                    const DropdownMenuItem<int?>(
                      value: null,
                      child: Text('General / Unassigned'),
                    ),
                    for (final c in widget.categories)
                      DropdownMenuItem<int?>(
                        value: c.id,
                        child: Text(c.name, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (v) => setState(() => _categoryId = v),
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _name,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Material & specification',
                    hintText: 'e.g. Reflectorized Vest, Portland Cement (40kg)',
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Enter the material name.'
                      : null,
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _qty,
                        decoration: const InputDecoration(
                          labelText: 'Planned qty',
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        validator: (v) {
                          final n = InputParsers.amount(v);
                          if (n == null || n <= 0) {
                            return 'Enter a qty > 0.';
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: TextFormField(
                        controller: _unit,
                        decoration: const InputDecoration(
                          labelText: 'Unit',
                          hintText: 'pcs, bags, pairs, set',
                        ),
                      ),
                    ),
                  ],
                ),
                if (widget.showCosts) ...[
                  const SizedBox(height: AppSpacing.md),
                  TextFormField(
                    controller: _cost,
                    decoration: const InputDecoration(
                      labelText: 'Estimated unit cost',
                      prefixText: '₱ ',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}

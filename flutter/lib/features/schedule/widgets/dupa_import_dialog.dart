import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_radii.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/platform/desktop_files.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/models/planned_material.dart';
import '../../../data/repositories/schedule_repository.dart';
import 'dupa_breakdown_dialog.dart';

/// Upload a DPWH DUPA Excel (`.xlsx`) workbook, preview every parsed Item of
/// Work and Section C material, and import them into the project in one click.
class DupaImportDialog extends StatefulWidget {
  const DupaImportDialog({
    super.key,
    required this.projectId,
    this.categoryId,
    this.categoryName,
  });

  final int projectId;
  final int? categoryId;
  final String? categoryName;

  static Future<DupaImportResult?> show(
    BuildContext context, {
    required int projectId,
    int? categoryId,
    String? categoryName,
  }) => showDialog<DupaImportResult>(
    context: context,
    barrierDismissible: false,
    builder: (_) => DupaImportDialog(
      projectId: projectId,
      categoryId: categoryId,
      categoryName: categoryName,
    ),
  );

  @override
  State<DupaImportDialog> createState() => _DupaImportDialogState();
}

class _DupaImportDialogState extends State<DupaImportDialog> {
  final _schedule = getIt<ScheduleRepository>();
  String? _fileName;
  Uint8List? _fileBytes;
  DupaImportPreview? _preview;
  String? _selectedSheet;
  Set<String> _selectedSheets = {};
  Map<String, int> _manualLinks = {};
  String? _error;
  bool _loading = false;
  bool _importing = false;

  Set<String> _defaultSelection(DupaImportPreview preview) {
    final real = {
      for (final i in preview.items)
        if ((i.budget != null && i.budget! > 0) || i.materials.isNotEmpty)
          i.sheet,
    };
    return real.isNotEmpty ? real : {for (final i in preview.items) i.sheet};
  }

  Future<void> _pickFile() async {
    setState(() {
      _error = null;
      _loading = true;
    });
    try {
      final picked = await pickSpreadsheetFile();
      if (picked == null) {
        if (mounted) setState(() => _loading = false);
        return;
      }
      final preview = await _schedule.previewDupaExcel(
        widget.projectId,
        fileName: picked.name,
        bytes: picked.bytes,
        categoryId: widget.categoryId,
      );
      if (!mounted) return;
      setState(() {
        _fileName = picked.name;
        _fileBytes = picked.bytes;
        _preview = preview;
        _selectedSheet = preview.sheet;
        _selectedSheets = _defaultSelection(preview);
        _manualLinks = {};
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _preview = null;
        _selectedSheet = null;
        _selectedSheets = {};
        _manualLinks = {};
        _loading = false;
      });
    }
  }

  Future<void> _switchSheet(String sheet) async {
    if (_fileBytes == null || _fileName == null || sheet == _selectedSheet) {
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final preview = await _schedule.previewDupaExcel(
        widget.projectId,
        fileName: _fileName!,
        bytes: _fileBytes!,
        categoryId: widget.categoryId,
        sheetName: sheet,
      );
      if (!mounted) return;
      setState(() {
        _preview = preview;
        _selectedSheet = preview.sheet ?? sheet;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _confirmImport() async {
    if (_fileBytes == null || _fileName == null) return;
    setState(() {
      _importing = true;
      _error = null;
    });
    try {
      final isMulti =
          widget.categoryId == null &&
          _preview != null &&
          _preview!.items.length > 1;
      final result = await _schedule.importDupaExcel(
        widget.projectId,
        fileName: _fileName!,
        bytes: _fileBytes!,
        categoryId: widget.categoryId,
        sheetName: _selectedSheet,
        selectedSheets: isMulti ? _selectedSheets.toList() : null,
        sheetCategoryMap: isMulti && _manualLinks.isNotEmpty
            ? _manualLinks
            : null,
      );
      if (!mounted) return;
      Navigator.of(context).pop(result);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _importing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final preview = _preview;
    final isPerItem = widget.categoryId != null;

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.table_chart_outlined, size: 22),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              isPerItem
                  ? 'Import DUPA — ${widget.categoryName ?? 'Item of work'}'
                  : 'Import DPWH DUPA Excel (.xlsx)',
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 760,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              isPerItem
                  ? 'Upload the DUPA Excel (.xlsx) for this Item of Work. '
                        'Imports Labor (A), Equipment (B), Materials (C), and '
                        'Total Adjusted Cost directly into this item without '
                        'changing its Gantt schedule.'
                  : 'Select your DUPA Excel workbook (one sheet per Item of Work). '
                        'Tip: Keep Activity Codes (e.g. B.7(2), 803(1)) consistent '
                        'between your Bar Chart and DUPA sheets so every item matches '
                        'automatically.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                FilledButton.tonalIcon(
                  onPressed: (_loading || _importing) ? null : _pickFile,
                  icon: _loading
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.upload_file_rounded, size: 18),
                  label: Text(
                    _fileName == null ? 'Choose .xlsx file' : 'Change file',
                  ),
                ),
                if (preview != null && preview.sheets.length > 1) ...[
                  const SizedBox(width: AppSpacing.md),
                  DropdownButton<String>(
                    value: preview.sheets.contains(_selectedSheet)
                        ? _selectedSheet
                        : preview.sheets.first,
                    isDense: true,
                    underline: const SizedBox.shrink(),
                    items: [
                      for (final s in preview.sheets)
                        DropdownMenuItem(value: s, child: Text('Sheet: $s')),
                    ],
                    onChanged: (_loading || _importing)
                        ? null
                        : (v) {
                            if (v != null) _switchSheet(v);
                          },
                  ),
                ],
                if (_fileName != null) ...[
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      _fileName!,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.md),
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: const BoxDecoration(
                  color: AppColors.errorContainer,
                  borderRadius: AppRadii.mdAll,
                ),
                child: Text(
                  _error!,
                  style: const TextStyle(color: AppColors.error, fontSize: 13),
                ),
              ),
            ],
            if (preview != null) ...[
              const SizedBox(height: AppSpacing.md),
              Builder(
                builder: (context) {
                  final isMulti =
                      widget.categoryId == null && preview.items.length > 1;
                  final activeItems = isMulti
                      ? [
                          for (final i in preview.items)
                            if (_selectedSheets.contains(i.sheet)) i,
                        ]
                      : preview.items;
                  final activeMaterials = activeItems.fold<int>(
                    0,
                    (sum, i) => sum + i.materials.length,
                  );
                  final activeBudget = activeItems.fold<double>(
                    0,
                    (sum, i) => sum + (i.budget ?? 0),
                  );
                  final allSelected =
                      preview.items.isNotEmpty &&
                      _selectedSheets.length == preview.items.length;
                  final noneSelected = _selectedSheets.isEmpty;
                  final projCats = preview.projectCategories;
                  final catsById = {for (final c in projCats) c.id: c};

                  int? resolvedCatId(DupaPreviewItem item) =>
                      _manualLinks[item.sheet] ?? item.matchedCategoryId;

                  final matchedProjectIds = <int>{};
                  for (final i in activeItems) {
                    final cid = resolvedCatId(i);
                    if (cid != null) matchedProjectIds.add(cid);
                  }
                  final missingCats = [
                    for (final c in projCats)
                      if (!c.hasDupa && !matchedProjectIds.contains(c.id)) c,
                  ];

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerLowest,
                          borderRadius: AppRadii.mdAll,
                          border: Border.all(color: cs.outlineVariant),
                        ),
                        child: Wrap(
                          spacing: AppSpacing.xl,
                          runSpacing: AppSpacing.sm,
                          children: [
                            _summaryMetric(
                              theme,
                              'Items of work',
                              isMulti
                                  ? '${activeItems.length} of ${preview.items.length}'
                                  : '${preview.totalItems}',
                            ),
                            _summaryMetric(
                              theme,
                              'Planned materials',
                              '$activeMaterials',
                            ),
                            _summaryMetric(
                              theme,
                              'Total DUPA budget',
                              Formatters.peso(activeBudget),
                            ),
                            if (isMulti && projCats.isNotEmpty)
                              _summaryMetric(
                                theme,
                                'Matched to Bar Chart',
                                '${matchedProjectIds.length} of ${projCats.length}',
                              ),
                          ],
                        ),
                      ),
                      if (isMulti && projCats.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.sm),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.md,
                            vertical: AppSpacing.sm,
                          ),
                          decoration: BoxDecoration(
                            color: missingCats.isEmpty
                                ? AppColors.successContainer
                                : AppColors.warningContainer,
                            borderRadius: AppRadii.mdAll,
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                missingCats.isEmpty
                                    ? Icons.verified_outlined
                                    : Icons.info_outline_rounded,
                                size: 18,
                                color: missingCats.isEmpty
                                    ? AppColors.success
                                    : AppColors.warning,
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(
                                child: Text(
                                  missingCats.isEmpty
                                      ? 'All ${projCats.length} Bar Chart Items of Work are matched to a DUPA sheet.'
                                      : '${missingCats.length} Bar Chart Item${missingCats.length == 1 ? '' : 's'} still without DUPA: '
                                            '${missingCats.take(4).map((c) => c.itemNo.isNotEmpty ? c.itemNo : c.name).join(', ')}'
                                            '${missingCats.length > 4 ? ' +${missingCats.length - 4} more' : ''}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: missingCats.isEmpty
                                        ? AppColors.success
                                        : AppColors.warning,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      if (isMulti) ...[
                        const SizedBox(height: AppSpacing.sm),
                        Row(
                          children: [
                            Checkbox(
                              tristate: true,
                              value: allSelected
                                  ? true
                                  : (noneSelected ? false : null),
                              onChanged: _importing
                                  ? null
                                  : (_) {
                                      setState(() {
                                        if (allSelected) {
                                          _selectedSheets = {};
                                        } else {
                                          _selectedSheets = {
                                            for (final i in preview.items)
                                              i.sheet,
                                          };
                                        }
                                      });
                                    },
                            ),
                            GestureDetector(
                              onTap: _importing
                                  ? null
                                  : () {
                                      setState(() {
                                        if (allSelected) {
                                          _selectedSheets = {};
                                        } else {
                                          _selectedSheets = {
                                            for (final i in preview.items)
                                              i.sheet,
                                          };
                                        }
                                      });
                                    },
                              child: Text(
                                allSelected
                                    ? 'Deselect all (${preview.items.length})'
                                    : 'Select all (${_selectedSheets.length} of ${preview.items.length} selected)',
                                style: theme.textTheme.labelMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ] else
                        const SizedBox(height: AppSpacing.md),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 360),
                        child:
                            preview.items.length == 1 &&
                                preview.items.first.dupaBreakdown != null
                            ? SingleChildScrollView(
                                child: DupaBreakdownBody(
                                  dupaBreakdown:
                                      preview.items.first.dupaBreakdown!,
                                  fallbackBudget: preview.items.first.budget,
                                ),
                              )
                            : ListView.separated(
                                shrinkWrap: true,
                                itemCount: preview.items.length,
                                separatorBuilder: (_, _) =>
                                    const Divider(height: 1),
                                itemBuilder: (context, index) {
                                  final item = preview.items[index];
                                  final checked = _selectedSheets.contains(
                                    item.sheet,
                                  );
                                  final targetId = resolvedCatId(item);
                                  final targetCat = targetId != null
                                      ? catsById[targetId]
                                      : null;
                                  final targetName =
                                      targetCat?.name ??
                                      item.matchedCategoryName;
                                  return ExpansionTile(
                                    tilePadding: const EdgeInsets.symmetric(
                                      horizontal: AppSpacing.xs,
                                    ),
                                    leading: isMulti
                                        ? Checkbox(
                                            value: checked,
                                            onChanged: _importing
                                                ? null
                                                : (v) {
                                                    setState(() {
                                                      if (v == true) {
                                                        _selectedSheets.add(
                                                          item.sheet,
                                                        );
                                                      } else {
                                                        _selectedSheets.remove(
                                                          item.sheet,
                                                        );
                                                      }
                                                    });
                                                  },
                                          )
                                        : null,
                                    title: Text(
                                      item.name,
                                      style: theme.textTheme.titleSmall
                                          ?.copyWith(
                                            color: (isMulti && !checked)
                                                ? cs.onSurfaceVariant
                                                : null,
                                          ),
                                    ),
                                    subtitle: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          [
                                            if (item.budget != null)
                                              'Total: ${Formatters.peso(item.budget!)}',
                                            if (item.laborBudget != null)
                                              'Labor: ${Formatters.peso(item.laborBudget!)}',
                                            if (item.equipmentBudget != null)
                                              'Equip: ${Formatters.peso(item.equipmentBudget!)}',
                                            if (item.materialBudget != null)
                                              'Mat: ${Formatters.peso(item.materialBudget!)}',
                                          ].join(' · '),
                                          style: theme.textTheme.bodySmall,
                                        ),
                                        if (isMulti && projCats.isNotEmpty) ...[
                                          const SizedBox(height: 4),
                                          Wrap(
                                            spacing: AppSpacing.sm,
                                            runSpacing: 4,
                                            crossAxisAlignment:
                                                WrapCrossAlignment.center,
                                            children: [
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 2,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: targetName != null
                                                      ? AppColors
                                                            .successContainer
                                                      : AppColors
                                                            .warningContainer,
                                                  borderRadius: AppRadii.smAll,
                                                ),
                                                child: Text(
                                                  targetName != null
                                                      ? 'Matched → $targetName'
                                                      : 'Unmatched (creates new)',
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w700,
                                                    color: targetName != null
                                                        ? AppColors.success
                                                        : AppColors.warning,
                                                  ),
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                              if (targetName == null && checked)
                                                DropdownButton<int?>(
                                                  value: _manualLinks[item.sheet],
                                                  isDense: true,
                                                  hint: const Text(
                                                    'Link to Item of Work…',
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                    ),
                                                  ),
                                                  underline:
                                                      const SizedBox.shrink(),
                                                  items: [
                                                    const DropdownMenuItem<int?>(
                                                      value: null,
                                                      child: Text(
                                                        'Create as new item',
                                                        style: TextStyle(
                                                          fontSize: 12,
                                                        ),
                                                      ),
                                                    ),
                                                    for (final c in projCats)
                                                      DropdownMenuItem<int?>(
                                                        value: c.id,
                                                        child: SizedBox(
                                                          width: 240,
                                                          child: Text(
                                                            c.name,
                                                            overflow: TextOverflow
                                                                .ellipsis,
                                                            style:
                                                                const TextStyle(
                                                                  fontSize: 12,
                                                                ),
                                                          ),
                                                        ),
                                                      ),
                                                  ],
                                                  onChanged: _importing
                                                      ? null
                                                      : (v) {
                                                          setState(() {
                                                            if (v == null) {
                                                              _manualLinks
                                                                  .remove(
                                                                    item.sheet,
                                                                  );
                                                            } else {
                                                              _manualLinks[item
                                                                      .sheet] =
                                                                  v;
                                                            }
                                                          });
                                                        },
                                                ),
                                            ],
                                          ),
                                        ],
                                      ],
                                    ),
                                    children: [
                                      if (item.dupaBreakdown != null)
                                        Padding(
                                          padding: const EdgeInsets.all(
                                            AppSpacing.sm,
                                          ),
                                          child: DupaBreakdownBody(
                                            dupaBreakdown: item.dupaBreakdown!,
                                            fallbackBudget: item.budget,
                                          ),
                                        )
                                      else if (item.materials.isEmpty)
                                        const ListTile(
                                          dense: true,
                                          title: Text(
                                            'No DUPA rows on this sheet.',
                                          ),
                                        )
                                      else
                                        for (final m in item.materials)
                                          ListTile(
                                            dense: true,
                                            title: Text(m.name),
                                            subtitle: Text(
                                              '${Formatters.number(m.plannedQty)} ${m.unit} × ${Formatters.peso(m.unitCost)}',
                                            ),
                                            trailing: Text(
                                              Formatters.peso(m.amount),
                                              style: theme.textTheme.bodySmall
                                                  ?.copyWith(
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                            ),
                                          ),
                                    ],
                                  );
                                },
                              ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _importing ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed:
              (preview == null ||
                  _importing ||
                  (widget.categoryId == null &&
                      preview.items.length > 1 &&
                      _selectedSheets.isEmpty))
              ? null
              : _confirmImport,
          icon: _importing
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.check_rounded, size: 18),
          label: Text(
            preview == null
                ? 'Import'
                : () {
                    final count =
                        (widget.categoryId == null && preview.items.length > 1)
                        ? _selectedSheets.length
                        : preview.totalItems;
                    return 'Import $count item${count == 1 ? '' : 's'}';
                  }(),
          ),
        ),
      ],
    );
  }

  Widget _summaryMetric(ThemeData theme, String label, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(label, style: theme.textTheme.labelSmall),
      Text(
        value,
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w700,
        ),
      ),
    ],
  );
}

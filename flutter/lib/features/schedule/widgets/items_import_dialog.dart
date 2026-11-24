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

/// Upload a DPWH SF-INFR-41 Bar Chart (`.xlsx`) or a simple 3-column Excel
/// (`Item of work | Weeks | Days`), preview the calculated Gantt dates, and
/// import all Items of Work in one click.
class ItemsImportDialog extends StatefulWidget {
  const ItemsImportDialog({super.key, required this.projectId});

  final int projectId;

  static Future<int?> show(
    BuildContext context, {
    required int projectId,
  }) => showDialog<int>(
    context: context,
    barrierDismissible: false,
    builder: (_) => ItemsImportDialog(projectId: projectId),
  );

  @override
  State<ItemsImportDialog> createState() => _ItemsImportDialogState();
}

class _ItemsImportDialogState extends State<ItemsImportDialog> {
  final _schedule = getIt<ScheduleRepository>();
  String? _fileName;
  Uint8List? _fileBytes;
  ItemsExcelPreview? _preview;
  String? _selectedSheet;
  bool _replaceExisting = false;
  String? _error;
  bool _loading = false;
  bool _importing = false;

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
      final preview = await _schedule.previewItemsExcel(
        widget.projectId,
        fileName: picked.name,
        bytes: picked.bytes,
      );
      if (!mounted) return;
      setState(() {
        _fileName = picked.name;
        _fileBytes = picked.bytes;
        _preview = preview;
        _selectedSheet = preview.sheet;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _preview = null;
        _selectedSheet = null;
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
      final preview = await _schedule.previewItemsExcel(
        widget.projectId,
        fileName: _fileName!,
        bytes: _fileBytes!,
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
      final count = await _schedule.importItemsExcel(
        widget.projectId,
        fileName: _fileName!,
        bytes: _fileBytes!,
        sheetName: _selectedSheet,
        replaceExisting: _replaceExisting,
      );
      if (!mounted) return;
      Navigator.of(context).pop(count);
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
    final rows = preview?.items;
    final hasBudget = rows != null && rows.any((r) => r.budget != null);

    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.table_chart_outlined, size: 22),
          SizedBox(width: AppSpacing.sm),
          Text('Import Items of Work (.xlsx)'),
        ],
      ),
      content: SizedBox(
        width: hasBudget ? 760 : 640,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Upload a DPWH SF-INFR-41 Bar Chart (.xlsx) or a simple 3-column '
              'Excel (Item of work, Weeks, Days). Start and end dates are '
              'computed from the project start date and plotted directly on '
              'the Gantt chart.',
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
            if (rows != null) ...[
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${rows.length} item${rows.length == 1 ? '' : 's'} ready to import'
                      '${preview?.format == 'bar_chart' ? ' (SF-INFR-41 Bar Chart)' : ''}',
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Checkbox(
                    value: _replaceExisting,
                    visualDensity: VisualDensity.compact,
                    onChanged: _importing
                        ? null
                        : (v) => setState(() => _replaceExisting = v ?? false),
                  ),
                  GestureDetector(
                    onTap: _importing
                        ? null
                        : () => setState(
                            () => _replaceExisting = !_replaceExisting,
                          ),
                    child: Text(
                      'Replace existing items',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 320),
                child: SingleChildScrollView(
                  child: DataTable(
                    headingRowHeight: 36,
                    dataRowMinHeight: 38,
                    dataRowMaxHeight: 48,
                    columnSpacing: 16,
                    columns: [
                      const DataColumn(label: Text('Item of work')),
                      if (hasBudget)
                        const DataColumn(label: Text('Budget'), numeric: true),
                      const DataColumn(label: Text('Weeks')),
                      const DataColumn(label: Text('Days'), numeric: true),
                      const DataColumn(label: Text('Gantt dates')),
                    ],
                    rows: [
                      for (final r in rows)
                        DataRow(
                          cells: [
                            DataCell(
                              ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 260,
                                ),
                                child: Text(
                                  r.name,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                            if (hasBudget)
                              DataCell(
                                Text(
                                  r.budget == null
                                      ? '—'
                                      : Formatters.peso(r.budget!),
                                ),
                              ),
                            DataCell(
                              Text(
                                r.plannedWeeks.isEmpty ? '—' : r.plannedWeeks,
                              ),
                            ),
                            DataCell(
                              Text(
                                r.plannedDays == null
                                    ? '—'
                                    : '${r.plannedDays}',
                              ),
                            ),
                            DataCell(
                              Text(
                                r.startDate != null && r.endDate != null
                                    ? Formatters.dateRange(
                                        r.startDate!,
                                        r.endDate!,
                                      )
                                    : '—',
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
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
          onPressed: (rows == null || rows.isEmpty || _importing || _loading)
              ? null
              : _confirmImport,
          icon: _importing
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.check_rounded, size: 18),
          label: Text(
            rows == null
                ? 'Import'
                : 'Import ${rows.length} item${rows.length == 1 ? '' : 's'}',
          ),
        ),
      ],
    );
  }
}

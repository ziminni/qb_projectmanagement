import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_radii.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/platform/desktop_files.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/models/json_utils.dart';
import '../../../data/repositories/billing_repository.dart';
import '../../schedule/widgets/dupa_breakdown_dialog.dart';

/// Displays a VO's revised Bar Chart diff (auto-flagged changes per Item of Work)
/// with sheet selection and per-item DUPA (A–J) import & preview.
///
/// When [editable] is true (on the VO form), the user can upload/switch sheets
/// on the revised Bar Chart `.xlsx` and attach a revised DUPA `.xlsx` (with
/// sheet selection) to any flagged item. When [editable] is false (on PM &
/// Client VO detail pages), it renders the read-only diff + `View DUPA (A–J)`.
class VoRevisedScheduleSection extends StatefulWidget {
  const VoRevisedScheduleSection({
    super.key,
    required this.projectId,
    required this.revisedSchedule,
    required this.showCosts,
    this.editable = false,
    this.onChanged,
  });

  final int projectId;
  final Map<String, dynamic>? revisedSchedule;
  final bool showCosts;
  final bool editable;
  final ValueChanged<Map<String, dynamic>?>? onChanged;

  @override
  State<VoRevisedScheduleSection> createState() =>
      _VoRevisedScheduleSectionState();
}

class _VoRevisedScheduleSectionState extends State<VoRevisedScheduleSection> {
  final _billing = getIt<BillingRepository>();
  String? _fileName;
  Uint8List? _fileBytes;
  bool _loadingBarChart = false;
  bool _showChangedOnly = true;
  String? _error;

  Future<void> _pickBarChart() async {
    setState(() {
      _error = null;
      _loadingBarChart = true;
    });
    try {
      final picked = await pickSpreadsheetFile();
      if (picked == null) {
        if (mounted) setState(() => _loadingBarChart = false);
        return;
      }
      final diff = await _billing.previewVoBarChart(
        widget.projectId,
        fileName: picked.name,
        bytes: picked.bytes,
      );
      if (!mounted) return;
      setState(() {
        _fileName = picked.name;
        _fileBytes = picked.bytes;
        _loadingBarChart = false;
      });
      widget.onChanged?.call(diff);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loadingBarChart = false;
      });
    }
  }

  Future<void> _switchBarChartSheet(String sheet) async {
    if (_fileBytes == null || _fileName == null) return;
    setState(() {
      _error = null;
      _loadingBarChart = true;
    });
    try {
      final diff = await _billing.previewVoBarChart(
        widget.projectId,
        fileName: _fileName!,
        bytes: _fileBytes!,
        sheetName: sheet,
      );
      if (!mounted) return;
      setState(() => _loadingBarChart = false);
      widget.onChanged?.call(diff);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loadingBarChart = false;
      });
    }
  }

  Future<void> _attachItemDupa(int itemIndex, Map<String, dynamic> item) async {
    final result = await _VoItemDupaDialog.show(
      context,
      billing: _billing,
      itemNo: '${item['item_no'] ?? ''}',
      itemName: '${item['name'] ?? ''}',
    );
    if (result == null || !mounted) return;

    final sched = Map<String, dynamic>.from(widget.revisedSchedule ?? {});
    final items = [
      for (final raw in (sched['items'] as List<dynamic>? ?? const []))
        if (raw is Map<String, dynamic>) Map<String, dynamic>.from(raw),
    ];
    if (itemIndex < 0 || itemIndex >= items.length) return;

    final updated = Map<String, dynamic>.from(items[itemIndex]);
    updated['dupa_breakdown'] = result['dupa_breakdown'];
    updated['dupa_materials'] = result['materials'] ?? const [];
    // If the DUPA carries an authoritative Total Adjusted Cost, sync new_budget & deltas.
    final dupaBudget = JsonUtils.toDoubleOrNull(result['budget']);
    if (dupaBudget != null) {
      updated['new_budget'] = dupaBudget.toStringAsFixed(2);
      final oldBudget = JsonUtils.toDoubleOrNull(updated['old_budget']) ?? 0;
      updated['cost_delta'] = (dupaBudget - oldBudget).toStringAsFixed(2);
      if (updated['status'] == 'unchanged' &&
          (dupaBudget - oldBudget).abs() >= 0.01) {
        updated['status'] = 'cost_changed';
      } else if (updated['status'] == 'schedule_changed' &&
          (dupaBudget - oldBudget).abs() >= 0.01) {
        updated['status'] = 'cost_and_schedule_changed';
      }
    }
    items[itemIndex] = updated;

    // Recompute totals so net_cost_impact stays 100% consistent.
    var additives = 0.0;
    var deductives = 0.0;
    var changedCount = 0;
    for (final row in items) {
      final st = '${row['status'] ?? 'unchanged'}';
      if (st != 'unchanged') changedCount++;
      final delta = JsonUtils.toDoubleOrNull(row['cost_delta']) ?? 0;
      if (delta > 0) {
        additives += delta;
      } else if (delta < 0) {
        deductives += delta.abs();
      }
    }
    sched['items'] = items;
    sched['total_additives'] = additives.toStringAsFixed(2);
    sched['total_deductives'] = deductives.toStringAsFixed(2);
    sched['net_cost_impact'] = (additives - deductives).toStringAsFixed(2);
    sched['changed_count'] = changedCount;
    widget.onChanged?.call(sched);
  }

  void _viewDupa(BuildContext context, Map<String, dynamic> item) {
    final dupa = item['dupa_breakdown'];
    if (dupa is! Map<String, dynamic>) return;
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.receipt_long_outlined, size: 22),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                '${item['name'] ?? item['item_no'] ?? 'DUPA (A–J)'}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 760,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 560),
            child: SingleChildScrollView(
              child: DupaBreakdownBody(
                dupaBreakdown: dupa,
                fallbackBudget: JsonUtils.toDoubleOrNull(item['new_budget']),
              ),
            ),
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final sched = widget.revisedSchedule;
    final items = [
      for (final raw in (sched?['items'] as List<dynamic>? ?? const []))
        if (raw is Map<String, dynamic>) raw,
    ];
    final sheets = [
      for (final s in (sched?['sheets'] as List<dynamic>? ?? const []))
        if (s is String && s.isNotEmpty) s,
    ];
    final selectedSheet = sched?['sheet'] as String?;

    final baselineDays = sched?['baseline_days'] as int? ?? 0;
    final revisedDays = sched?['revised_days'] as int? ?? 0;
    final daysImpact = sched?['days_impact'] as int? ?? 0;
    final additives = JsonUtils.toDoubleOrNull(sched?['total_additives']) ?? 0;
    final deductives =
        JsonUtils.toDoubleOrNull(sched?['total_deductives']) ?? 0;
    final netImpact = JsonUtils.toDoubleOrNull(sched?['net_cost_impact']) ?? 0;
    final changedCount =
        sched?['changed_count'] as int? ??
        items.where((i) => i['status'] != 'unchanged').length;
    final unchangedCount = items.length - changedCount;

    final visibleEntries = <MapEntry<int, Map<String, dynamic>>>[];
    for (var i = 0; i < items.length; i++) {
      if (!_showChangedOnly || items[i]['status'] != 'unchanged') {
        visibleEntries.add(MapEntry(i, items[i]));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.editable) ...[
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilledButton.tonalIcon(
                onPressed: _loadingBarChart ? null : _pickBarChart,
                icon: _loadingBarChart
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.upload_file_rounded, size: 18),
                label: Text(
                  items.isEmpty
                      ? 'Import revised Bar Chart (.xlsx)'
                      : 'Change Bar Chart',
                ),
              ),
              if (sheets.length > 1 && _fileBytes != null)
                DropdownButton<String>(
                  value: sheets.contains(selectedSheet)
                      ? selectedSheet
                      : sheets.first,
                  isDense: true,
                  underline: const SizedBox.shrink(),
                  items: [
                    for (final s in sheets)
                      DropdownMenuItem(value: s, child: Text('Sheet: $s')),
                  ],
                  onChanged: _loadingBarChart
                      ? null
                      : (v) {
                          if (v != null && v != selectedSheet) {
                            _switchBarChartSheet(v);
                          }
                        },
                ),
              if (selectedSheet != null && sheets.length <= 1)
                Text(
                  'Sheet: $selectedSheet',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.sm),
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
        ],
        if (items.isEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            widget.editable
                ? 'Upload the revised Bar Chart (.xlsx) and pick the revised sheet '
                      '(e.g. "REVISED +23cd"). The system will automatically flag '
                      'added, removed, cost-changed, and rescheduled items while '
                      'keeping unchanged items intact.'
                : 'No revised bar chart attached to this variation order.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
        ] else ...[
          const SizedBox(height: AppSpacing.md),
          // Auto-computed VO summary strip
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.surfaceMuted,
              borderRadius: AppRadii.mdAll,
              border: Border.all(color: cs.outlineVariant),
            ),
            child: Wrap(
              spacing: AppSpacing.xl,
              runSpacing: AppSpacing.sm,
              children: [
                _metric(
                  theme,
                  'Schedule',
                  '${baselineDays}d → ${revisedDays}d '
                      '(${daysImpact >= 0 ? '+$daysImpact' : '$daysImpact'}d)',
                ),
                _metric(
                  theme,
                  'Flagged items',
                  '$changedCount changed · $unchangedCount unchanged',
                ),
                if (widget.showCosts) ...[
                  _metric(theme, 'Additives', '+${Formatters.peso(additives)}'),
                  _metric(
                    theme,
                    'Deductives',
                    '-${Formatters.peso(deductives)}',
                  ),
                  _metric(
                    theme,
                    'Net impact',
                    netImpact.abs() < 0.01
                        ? '₱0.00 (Realignment)'
                        : '${netImpact >= 0 ? '+' : ''}${Formatters.peso(netImpact)}',
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: Text(
                  _showChangedOnly
                      ? 'Changed items ($changedCount)'
                      : 'All items (${items.length})',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              TextButton(
                onPressed: () =>
                    setState(() => _showChangedOnly = !_showChangedOnly),
                child: Text(
                  _showChangedOnly
                      ? 'Show all (${items.length})'
                      : 'Show changed only ($changedCount)',
                ),
              ),
            ],
          ),
          if (visibleEntries.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: Text(
                'No differences detected between this sheet and the current schedule.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: visibleEntries.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, idx) {
                  final entry = visibleEntries[idx];
                  final row = entry.value;
                  final status = '${row['status'] ?? 'unchanged'}';
                  final hasDupa = row['dupa_breakdown'] is Map<String, dynamic>;
                  final oldStart = row['old_day_to_start'];
                  final newStart = row['new_day_to_start'];
                  final oldDays = row['old_days'];
                  final newDays = row['new_days'];
                  final delta =
                      JsonUtils.toDoubleOrNull(row['cost_delta']) ?? 0;

                  final subParts = <String>[];
                  if (status == 'added') {
                    subParts.add('Day $newStart · ${newDays}d');
                  } else if (status == 'removed') {
                    subParts.add('Removed from revised schedule');
                  } else if (oldStart != newStart || oldDays != newDays) {
                    subParts.add(
                      'Day $oldStart (${oldDays}d) → Day $newStart (${newDays}d)',
                    );
                  } else {
                    subParts.add('Day $newStart · ${newDays}d (unchanged)');
                  }

                  if (widget.showCosts) {
                    final nb = JsonUtils.toDoubleOrNull(row['new_budget']);
                    if (nb != null) {
                      final deltaStr = delta.abs() >= 0.01
                          ? ' (${delta > 0 ? '+' : ''}${Formatters.peso(delta)})'
                          : '';
                      subParts.add('Cost: ${Formatters.peso(nb)}$deltaStr');
                    }
                  }

                  return ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xs,
                      vertical: 2,
                    ),
                    title: Row(
                      children: [
                        _statusBadge(status),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            '${row['name'] ?? row['item_no'] ?? ''}',
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: status == 'unchanged'
                                  ? FontWeight.w400
                                  : FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    subtitle: Text(
                      subParts.join(' · '),
                      style: theme.textTheme.bodySmall,
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (hasDupa && widget.showCosts)
                          TextButton.icon(
                            onPressed: () => _viewDupa(context, row),
                            icon: const Icon(
                              Icons.receipt_long_outlined,
                              size: 16,
                            ),
                            label: const Text('DUPA (A–J)'),
                          ),
                        if (widget.editable &&
                            widget.showCosts &&
                            status != 'removed')
                          TextButton.icon(
                            onPressed: () => _attachItemDupa(entry.key, row),
                            icon: const Icon(
                              Icons.table_chart_outlined,
                              size: 16,
                            ),
                            label: Text(hasDupa ? 'Update DUPA' : 'Import DUPA'),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ],
    );
  }

  Widget _metric(ThemeData theme, String label, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(label, style: theme.textTheme.labelSmall),
      Text(
        value,
        style: theme.textTheme.bodyMedium
            ?.merge(AppTextStyles.numeric)
            .copyWith(fontWeight: FontWeight.w700),
      ),
    ],
  );

  Widget _statusBadge(String status) {
    final (label, bg, fg) = switch (status) {
      'added' => ('Added', AppColors.successContainer, AppColors.success),
      'removed' => ('Removed', AppColors.errorContainer, AppColors.error),
      'cost_changed' => (
        'Cost changed',
        AppColors.warningContainer,
        AppColors.warning,
      ),
      'cost_and_schedule_changed' => (
        'Cost + Schedule',
        AppColors.warningContainer,
        AppColors.warning,
      ),
      'schedule_changed' => (
        'Schedule',
        AppColors.primaryContainer,
        AppColors.primary,
      ),
      _ => ('Unchanged', AppColors.surfaceMuted, AppColors.textSecondary),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: AppRadii.smAll),
      child: Text(
        label,
        style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w700),
      ),
    );
  }
}

/// Per-item DUPA `.xlsx` picker with Sheet dropdown + full Sections A–J preview
/// for a flagged item inside a Variation Order.
class _VoItemDupaDialog extends StatefulWidget {
  const _VoItemDupaDialog({
    required this.billing,
    required this.itemNo,
    required this.itemName,
  });

  final BillingRepository billing;
  final String itemNo;
  final String itemName;

  static Future<Map<String, dynamic>?> show(
    BuildContext context, {
    required BillingRepository billing,
    required String itemNo,
    required String itemName,
  }) => showDialog<Map<String, dynamic>>(
    context: context,
    barrierDismissible: false,
    builder: (_) =>
        _VoItemDupaDialog(billing: billing, itemNo: itemNo, itemName: itemName),
  );

  @override
  State<_VoItemDupaDialog> createState() => _VoItemDupaDialogState();
}

class _VoItemDupaDialogState extends State<_VoItemDupaDialog> {
  String? _fileName;
  Uint8List? _fileBytes;
  String? _selectedSheet;
  List<String> _sheets = const [];
  Map<String, dynamic>? _item;
  String? _error;
  bool _loading = false;

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
      final resp = await widget.billing.previewVoDupa(
        fileName: picked.name,
        bytes: picked.bytes,
        itemNo: widget.itemNo,
      );
      if (!mounted) return;
      setState(() {
        _fileName = picked.name;
        _fileBytes = picked.bytes;
        _selectedSheet = resp['sheet'] as String?;
        _sheets = [
          for (final s in (resp['sheets'] as List<dynamic>? ?? const []))
            if (s is String && s.isNotEmpty) s,
        ];
        _item = resp['item'] as Map<String, dynamic>?;
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

  Future<void> _switchSheet(String sheet) async {
    if (_fileBytes == null || _fileName == null || sheet == _selectedSheet) {
      return;
    }
    setState(() {
      _error = null;
      _loading = true;
    });
    try {
      final resp = await widget.billing.previewVoDupa(
        fileName: _fileName!,
        bytes: _fileBytes!,
        itemNo: widget.itemNo,
        sheetName: sheet,
      );
      if (!mounted) return;
      setState(() {
        _selectedSheet = resp['sheet'] as String? ?? sheet;
        _item = resp['item'] as Map<String, dynamic>?;
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

  @override
  Widget build(BuildContext context) {
    final dupa = _item?['dupa_breakdown'] as Map<String, dynamic>?;

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.table_chart_outlined, size: 22),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'Attach DUPA — ${widget.itemName.isEmpty ? widget.itemNo : widget.itemName}',
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
            Row(
              children: [
                FilledButton.tonalIcon(
                  onPressed: _loading ? null : _pickFile,
                  icon: _loading
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.upload_file_rounded, size: 18),
                  label: Text(
                    _fileName == null ? 'Choose DUPA .xlsx' : 'Change file',
                  ),
                ),
                if (_sheets.length > 1) ...[
                  const SizedBox(width: AppSpacing.md),
                  DropdownButton<String>(
                    value: _sheets.contains(_selectedSheet)
                        ? _selectedSheet
                        : _sheets.first,
                    isDense: true,
                    underline: const SizedBox.shrink(),
                    items: [
                      for (final s in _sheets)
                        DropdownMenuItem(value: s, child: Text('Sheet: $s')),
                    ],
                    onChanged: _loading
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
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                _error!,
                style: const TextStyle(color: AppColors.error, fontSize: 13),
              ),
            ],
            if (dupa != null) ...[
              const SizedBox(height: AppSpacing.md),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 400),
                child: SingleChildScrollView(
                  child: DupaBreakdownBody(
                    dupaBreakdown: dupa,
                    fallbackBudget: JsonUtils.toDoubleOrNull(_item?['budget']),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: (_item == null || _loading)
              ? null
              : () => Navigator.of(context).pop(_item),
          icon: const Icon(Icons.check_rounded, size: 18),
          label: const Text('Attach DUPA'),
        ),
      ],
    );
  }
}

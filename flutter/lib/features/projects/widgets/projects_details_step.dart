import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_radii.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/models/client.dart';
import '../../../data/models/planned_material.dart';
import '../../../data/models/user.dart';
import '../../../shared/widgets/app_date_field.dart';

/// Wizard step 1: what the project is, who it is for, who runs the site and
/// when it happens — plus optional Bar Chart (`.xlsx`) import with live preview.
class ProjectsDetailsStep extends StatelessWidget {
  const ProjectsDetailsStep({
    super.key,
    required this.code,
    required this.name,
    required this.isNew,
    required this.clients,
    required this.clientId,
    required this.onClient,
    required this.validateClient,
    required this.siteEngineers,
    required this.siteEngineerId,
    required this.onSiteEngineer,
    required this.start,
    required this.end,
    required this.dateError,
    required this.onPickStart,
    required this.onPickEnd,
    this.barChartFileName,
    this.barChartPreview,
    this.barChartSheet,
    this.barChartLoading = false,
    this.barChartError,
    this.onPickBarChart,
    this.onSwitchBarChartSheet,
    this.onClearBarChart,
  });

  final TextEditingController code;
  final TextEditingController name;
  final bool isNew;
  final List<Client> clients;
  final int? clientId;
  final ValueChanged<int?> onClient;
  final String? Function(int?) validateClient;
  final List<User> siteEngineers;
  final int? siteEngineerId;
  final ValueChanged<int?> onSiteEngineer;
  final DateTime? start;
  final DateTime? end;
  final String? dateError;
  final VoidCallback onPickStart;
  final VoidCallback onPickEnd;
  final String? barChartFileName;
  final ItemsExcelPreview? barChartPreview;
  final String? barChartSheet;
  final bool barChartLoading;
  final String? barChartError;
  final VoidCallback? onPickBarChart;
  final ValueChanged<String>? onSwitchBarChartSheet;
  final VoidCallback? onClearBarChart;

  String? _required(String? v, String label) =>
      (v == null || v.trim().isEmpty) ? 'Enter the $label.' : null;

  @override
  Widget build(BuildContext context) {
    const gap = SizedBox(height: AppSpacing.lg, width: AppSpacing.lg);
    Widget pair(Widget a, Widget b) => LayoutBuilder(
      builder: (context, c) => c.maxWidth < 520
          ? Column(children: [a, gap, b])
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: a),
                gap,
                Expanded(child: b),
              ],
            ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        pair(
          TextFormField(
            controller: code,
            decoration: const InputDecoration(
              labelText: 'Code',
              hintText: 'QB-2026-040',
              prefixIcon: Icon(Icons.tag_rounded),
            ),
            textCapitalization: TextCapitalization.characters,
            validator: (v) => _required(v, 'project code'),
          ),
          TextFormField(
            controller: name,
            decoration: const InputDecoration(
              labelText: 'Project name',
              hintText: 'Two-storey residence',
              prefixIcon: Icon(Icons.apartment_rounded),
            ),
            validator: (v) => _required(v, 'project name'),
          ),
        ),
        gap,
        pair(
          DropdownButtonFormField<int>(
            initialValue: clientId,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Client',
              prefixIcon: Icon(Icons.person_outline_rounded),
            ),
            items: [
              for (final c in clients)
                DropdownMenuItem(value: c.id, child: Text(c.name)),
            ],
            validator: validateClient,
            onChanged: isNew ? onClient : null,
          ),
          isNew
              ? DropdownButtonFormField<int>(
                  initialValue: siteEngineerId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Foreman',
                    prefixIcon: Icon(Icons.engineering_outlined),
                  ),
                  items: [
                    for (final u in siteEngineers)
                      DropdownMenuItem(value: u.id, child: Text(u.fullName)),
                  ],
                  validator: (v) =>
                      v == null ? 'Choose the site engineer.' : null,
                  onChanged: onSiteEngineer,
                )
              : const SizedBox.shrink(),
        ),
        gap,
        pair(
          AppDateField(
            label: 'Start date',
            value: start,
            hasError: dateError != null,
            onTap: onPickStart,
          ),
          AppDateField(
            label: 'Target end date',
            value: end,
            hasError: dateError != null,
            enabled: !isNew,
            helperText: isNew ? 'Auto-filled from Bar Chart' : null,
            onTap: isNew ? null : onPickEnd,
          ),
        ),
        if (dateError != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Text(
              dateError!,
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontSize: 12,
              ),
            ),
          ),
        if (isNew && onPickBarChart != null) ...[
          const SizedBox(height: AppSpacing.xl),
          const Divider(),
          const SizedBox(height: AppSpacing.lg),
          _BarChartImportBox(
            hasStartDate: start != null,
            fileName: barChartFileName,
            preview: barChartPreview,
            selectedSheet: barChartSheet,
            loading: barChartLoading,
            error: barChartError,
            onPick: onPickBarChart!,
            onSwitchSheet: onSwitchBarChartSheet,
            onClear: onClearBarChart,
          ),
        ],
      ],
    );
  }
}

class _BarChartImportBox extends StatelessWidget {
  const _BarChartImportBox({
    required this.hasStartDate,
    required this.fileName,
    required this.preview,
    required this.selectedSheet,
    required this.loading,
    required this.error,
    required this.onPick,
    required this.onSwitchSheet,
    required this.onClear,
  });

  final bool hasStartDate;
  final String? fileName;
  final ItemsExcelPreview? preview;
  final String? selectedSheet;
  final bool loading;
  final String? error;
  final VoidCallback onPick;
  final ValueChanged<String>? onSwitchSheet;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final rows = preview?.items;
    final hasBudget = rows != null && rows.any((r) => r.budget != null);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Import Bar Chart / Gantt (.xlsx)', style: theme.textTheme.titleSmall),
        const SizedBox(height: 2),
        Text(
          hasStartDate
              ? 'Upload your DPWH SF-INFR-41 Bar Chart (.xlsx) and choose the sheet. '
                    'Target end date and Contract amount (Step 3) will auto-fill from the file.'
              : 'Select a Start date above first to unlock Bar Chart import.',
          style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: AppSpacing.md),
        Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FilledButton.tonalIcon(
              onPressed: (!hasStartDate || loading) ? null : onPick,
              icon: loading
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.upload_file_rounded, size: 18),
              label: Text(
                fileName == null ? 'Choose Bar Chart (.xlsx)' : 'Change file',
              ),
            ),
            if (preview != null && preview!.sheets.length > 1)
              DropdownButton<String>(
                value: preview!.sheets.contains(selectedSheet)
                    ? selectedSheet
                    : preview!.sheets.first,
                isDense: true,
                underline: const SizedBox.shrink(),
                items: [
                  for (final s in preview!.sheets)
                    DropdownMenuItem(value: s, child: Text('Sheet: $s')),
                ],
                onChanged: loading
                    ? null
                    : (v) {
                        if (v != null) onSwitchSheet?.call(v);
                      },
              ),
            if (fileName != null)
              Text(
                fileName!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            if (preview != null && onClear != null)
              TextButton.icon(
                onPressed: loading ? null : onClear,
                icon: const Icon(Icons.close_rounded, size: 16),
                label: const Text('Remove'),
              ),
          ],
        ),
        if (error != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: const BoxDecoration(
              color: AppColors.errorContainer,
              borderRadius: AppRadii.mdAll,
            ),
            child: Text(
              error!,
              style: const TextStyle(color: AppColors.error, fontSize: 13),
            ),
          ),
        ],
        if (preview != null && rows != null && rows.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
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
                _metric(theme, 'Items of work', '${rows.length}'),
                if (preview!.totalDays != null)
                  _metric(theme, 'Duration', '${preview!.totalDays} calendar days'),
                if (preview!.targetEndDate != null)
                  _metric(
                    theme,
                    'Auto-filled end date',
                    Formatters.date(preview!.targetEndDate!),
                  ),
                if (preview!.totalBudget != null)
                  _metric(
                    theme,
                    'Auto-filled contract amount',
                    Formatters.peso(preview!.totalBudget!),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Container(
            decoration: BoxDecoration(
              borderRadius: AppRadii.mdAll,
              border: Border.all(color: cs.outlineVariant),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 260),
              child: SingleChildScrollView(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    headingRowHeight: 34,
                    dataRowMinHeight: 34,
                    dataRowMaxHeight: 44,
                    columnSpacing: 16,
                    columns: [
                      const DataColumn(label: Text('Item of work')),
                      if (hasBudget)
                        const DataColumn(label: Text('Planned cost'), numeric: true),
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
                                constraints: const BoxConstraints(maxWidth: 260),
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
                              Text(r.plannedWeeks.isEmpty ? '—' : r.plannedWeeks),
                            ),
                            DataCell(
                              Text(r.plannedDays == null ? '—' : '${r.plannedDays}'),
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
}

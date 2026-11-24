import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_radii.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/models/category.dart';
import '../../../data/models/json_utils.dart';

/// Reusable DPWH DUPA Sections A–J cost sheet body (Labor, Equipment,
/// Materials, and D–J Cost Summary). Used both in [DupaBreakdownDialog] and
/// in [DupaImportDialog] preview.
class DupaBreakdownBody extends StatelessWidget {
  const DupaBreakdownBody({
    super.key,
    required this.dupaBreakdown,
    this.fallbackBudget,
  });

  final Map<String, dynamic> dupaBreakdown;
  final double? fallbackBudget;

  List<Map<String, dynamic>> _rows(String key) => [
    for (final raw in (dupaBreakdown[key] as List<dynamic>? ?? const []))
      if (raw is Map<String, dynamic>) raw,
  ];

  String _peso(Object? raw) {
    final v = JsonUtils.toDoubleOrNull(raw);
    return v == null ? '—' : Formatters.peso(v);
  }

  String _num(Object? raw) {
    final v = JsonUtils.toDoubleOrNull(raw);
    return v == null ? '—' : Formatters.number(v);
  }

  String _pctSuffix(Object? raw) {
    final s = (raw as String?)?.trim() ?? '';
    return s.isEmpty ? '' : ' ($s)';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final labor = _rows('labor');
    final equipment = _rows('equipment');
    final materials = _rows('materials');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Section A — Labor
        _sectionHeader(context, 'A. Labor', _peso(dupaBreakdown['sub_total_a'])),
        if (labor.isEmpty)
          _emptyRow(context, 'No labor entries.')
        else
          _table(
            context,
            columns: const [
              DataColumn(label: Text('Designation')),
              DataColumn(label: Text('Persons'), numeric: true),
              DataColumn(label: Text('Hrs'), numeric: true),
              DataColumn(label: Text('Rate / Hr'), numeric: true),
              DataColumn(label: Text('Amount'), numeric: true),
            ],
            rows: [
              for (final r in labor)
                DataRow(
                  cells: [
                    DataCell(Text('${r['designation'] ?? ''}')),
                    DataCell(Text(_num(r['persons']))),
                    DataCell(Text(_num(r['hours']))),
                    DataCell(Text(_peso(r['rate']))),
                    DataCell(Text(_peso(r['amount']))),
                  ],
                ),
            ],
          ),
        const SizedBox(height: AppSpacing.md),

        // Section B — Equipment
        _sectionHeader(
          context,
          'B. Equipment',
          _peso(dupaBreakdown['sub_total_b']),
        ),
        if (equipment.isEmpty)
          _emptyRow(context, 'No equipment entries.')
        else
          _table(
            context,
            columns: const [
              DataColumn(label: Text('Name & Capacity')),
              DataColumn(label: Text('Units'), numeric: true),
              DataColumn(label: Text('Hrs'), numeric: true),
              DataColumn(label: Text('Rate / Hr'), numeric: true),
              DataColumn(label: Text('Amount'), numeric: true),
            ],
            rows: [
              for (final r in equipment)
                DataRow(
                  cells: [
                    DataCell(Text('${r['name'] ?? ''}')),
                    DataCell(Text(_num(r['units']))),
                    DataCell(Text(_num(r['hours']))),
                    DataCell(Text(_peso(r['rate']))),
                    DataCell(Text(_peso(r['amount']))),
                  ],
                ),
            ],
          ),
        const SizedBox(height: AppSpacing.md),

        // Section C — Materials
        _sectionHeader(
          context,
          'C. Materials',
          _peso(dupaBreakdown['sub_total_c']),
        ),
        if (materials.isEmpty)
          _emptyRow(context, 'No material entries.')
        else
          _table(
            context,
            columns: const [
              DataColumn(label: Text('Name & Specification')),
              DataColumn(label: Text('Unit')),
              DataColumn(label: Text('Qty'), numeric: true),
              DataColumn(label: Text('Unit Cost'), numeric: true),
              DataColumn(label: Text('Amount'), numeric: true),
            ],
            rows: [
              for (final r in materials)
                DataRow(
                  cells: [
                    DataCell(Text('${r['name'] ?? ''}')),
                    DataCell(Text('${r['unit'] ?? ''}')),
                    DataCell(Text(_num(r['qty']))),
                    DataCell(Text(_peso(r['unit_cost']))),
                    DataCell(Text(_peso(r['amount']))),
                  ],
                ),
            ],
          ),
        const SizedBox(height: AppSpacing.md),

        // Sections D–J — Cost Summary
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.surfaceMuted,
            borderRadius: AppRadii.mdAll,
            border: Border.all(color: cs.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Cost Summary (D–J)',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              _summaryRow(
                context,
                'D. Estimated Direct Cost (A + B + C)',
                _peso(dupaBreakdown['direct_cost']),
              ),
              if (dupaBreakdown['unit_cost'] != null)
                _summaryRow(
                  context,
                  'E. Unit Cost',
                  _peso(dupaBreakdown['unit_cost']),
                ),
              _summaryRow(
                context,
                'F. OCM${_pctSuffix(dupaBreakdown['ocm_pct'])}',
                _peso(dupaBreakdown['ocm_amount']),
              ),
              _summaryRow(
                context,
                'G. Contractor\'s Profit (CP)${_pctSuffix(dupaBreakdown['profit_pct'])}',
                _peso(dupaBreakdown['profit_amount']),
              ),
              _summaryRow(
                context,
                'H. VAT${_pctSuffix(dupaBreakdown['vat_pct'])}',
                _peso(dupaBreakdown['vat_amount']),
              ),
              const Divider(height: AppSpacing.md),
              _summaryRow(
                context,
                'I. Total Adjusted Cost',
                _peso(dupaBreakdown['total_adjusted_cost'] ?? fallbackBudget),
                bold: true,
              ),
              if (dupaBreakdown['adjusted_unit_cost'] != null)
                _summaryRow(
                  context,
                  'J. Adjusted Unit Cost',
                  _peso(dupaBreakdown['adjusted_unit_cost']),
                  bold: true,
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _sectionHeader(BuildContext context, String title, String subtotal) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs + 2,
      ),
      decoration: const BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: AppRadii.smAll,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text(
            'Sub Total: $subtotal',
            style: theme.textTheme.labelMedium
                ?.merge(AppTextStyles.numeric)
                .copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  Widget _emptyRow(BuildContext context, String label) => Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.md,
      vertical: AppSpacing.sm,
    ),
    child: Text(
      label,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );

  Widget _table(
    BuildContext context, {
    required List<DataColumn> columns,
    required List<DataRow> rows,
  }) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: DataTable(
      headingRowHeight: 34,
      dataRowMinHeight: 34,
      dataRowMaxHeight: 44,
      columnSpacing: 20,
      columns: columns,
      rows: rows,
    ),
  );

  Widget _summaryRow(
    BuildContext context,
    String label,
    String value, {
    bool bold = false,
  }) {
    final style = Theme.of(context).textTheme.bodyMedium?.copyWith(
      fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(value, style: style?.merge(AppTextStyles.numeric)),
        ],
      ),
    );
  }
}

/// Full DPWH DUPA Sections A–J cost sheet viewer for one Item of Work.
class DupaBreakdownDialog extends StatelessWidget {
  const DupaBreakdownDialog({super.key, required this.category});

  final Category category;

  static Future<void> show(
    BuildContext context, {
    required Category category,
  }) => showDialog<void>(
    context: context,
    builder: (_) => DupaBreakdownDialog(category: category),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final d = category.dupaBreakdown ?? const <String, dynamic>{};
    final uom = (d['unit_of_measurement'] as String?) ?? '';

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.receipt_long_outlined, size: 22),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  category.name,
                  style: theme.textTheme.titleMedium,
                  overflow: TextOverflow.ellipsis,
                ),
                if (uom.isNotEmpty)
                  Text(
                    'Unit of Measurement: $uom',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
              ],
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
              dupaBreakdown: d,
              fallbackBudget: category.budget,
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
    );
  }
}

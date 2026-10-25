import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../viewmodels/expense_reports_viewmodel.dart';

/// Budget vs. actual material cost per category, then labor and equipment.
class BillingCostTable extends StatelessWidget {
  const BillingCostTable({super.key, required this.report});

  final CostReport report;

  @override
  Widget build(BuildContext context) {
    String p(double v) => Formatters.pesoWhole(v);
    Text variance(double? v) => Text(
      v == null ? '—' : p(v),
      style: TextStyle(color: v != null && v < 0 ? AppColors.error : null),
    );
    final c = report.costs;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: const [
          DataColumn(label: Text('Cost item')),
          DataColumn(label: Text('Budget'), numeric: true),
          DataColumn(label: Text('Actual'), numeric: true),
          DataColumn(label: Text('Remaining'), numeric: true),
        ],
        rows: [
          for (final cat in report.categories)
            DataRow(
              cells: [
                DataCell(Text('${cat.category.name} (materials)')),
                DataCell(Text(cat.budget == null ? '—' : p(cat.budget!))),
                DataCell(Text(p(cat.actual))),
                DataCell(variance(cat.variance)),
              ],
            ),
          DataRow(
            cells: [
              const DataCell(Text('Labor (processed payroll)')),
              const DataCell(Text('—')),
              DataCell(Text(p(c.labor))),
              const DataCell(Text('—')),
            ],
          ),
          DataRow(
            cells: [
              const DataCell(Text('Equipment')),
              const DataCell(Text('—')),
              DataCell(Text(p(c.equipment))),
              const DataCell(Text('—')),
            ],
          ),
          DataRow(
            cells: [
              const DataCell(
                Text('Total', style: TextStyle(fontWeight: FontWeight.w600)),
              ),
              DataCell(Text(p(report.totalBudget))),
              DataCell(
                Text(
                  p(c.total),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              DataCell(variance(report.totalBudget - c.total)),
            ],
          ),
        ],
      ),
    );
  }
}

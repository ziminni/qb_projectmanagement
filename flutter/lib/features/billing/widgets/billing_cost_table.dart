import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/utils/finance_access.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/services/session_service.dart';
import '../../../shared/widgets/app_budget_bar.dart';
import '../viewmodels/expense_reports_viewmodel.dart';

/// Budget vs. actual material cost per category, then labor and equipment.
class BillingCostTable extends StatelessWidget {
  const BillingCostTable({super.key, required this.report});

  final CostReport report;

  @override
  Widget build(BuildContext context) {
    if (getIt.isRegistered<SessionService>() &&
        getIt<SessionService>().isSignedIn &&
        !canSeeFinance()) {
      return const SizedBox.shrink();
    }

    String p(double v) => Formatters.pesoWhole(v);
    final numStyle = Theme.of(
      context,
    ).textTheme.bodyMedium?.merge(AppTextStyles.numeric);
    final boldNumStyle = numStyle?.copyWith(fontWeight: FontWeight.w700);
    Text variance(double? v, {bool bold = false}) {
      final isOver = v != null && v < 0;
      final base = bold ? boldNumStyle : numStyle;
      return Text(
        v == null ? '—' : p(v),
        style: base?.copyWith(
          color: isOver ? AppColors.error : null,
          fontWeight: bold
              ? FontWeight.w700
              : isOver
              ? FontWeight.w600
              : null,
        ),
      );
    }

    final c = report.costs;
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: constraints.maxWidth),
          child: DataTable(
            headingRowColor: const WidgetStatePropertyAll(
              AppColors.tableHeader,
            ),
            columnSpacing: AppSpacing.xl,
            columns: const [
              DataColumn(label: Text('Cost item')),
              DataColumn(label: Text('Budget'), numeric: true),
              DataColumn(label: Text('Actual'), numeric: true),
              DataColumn(label: Text('Remaining'), numeric: true),
              DataColumn(label: Text('Utilization')),
            ],
            rows: [
              for (final cat in report.categories)
                DataRow(
                  cells: [
                    DataCell(Text('${cat.category.name} (materials)')),
                    DataCell(
                      Text(
                        cat.budget == null ? '—' : p(cat.budget!),
                        style: numStyle,
                      ),
                    ),
                    DataCell(Text(p(cat.actual), style: numStyle)),
                    DataCell(variance(cat.variance)),
                    DataCell(
                      SizedBox(
                        width: 130,
                        child: AppBudgetBar(
                          budget: cat.budget,
                          actual: cat.actual,
                        ),
                      ),
                    ),
                  ],
                ),
              // The store's charge: one line with no category budget (decision
              // 2026-11-15), so category rows are outside purchases only.
              if (c.storeMaterials != 0)
                DataRow(
                  cells: [
                    const DataCell(Text('Materials from our store')),
                    const DataCell(Text('—')),
                    DataCell(Text(p(c.storeMaterials), style: numStyle)),
                    const DataCell(Text('—')),
                    const DataCell(Text('—')),
                  ],
                ),
              DataRow(
                cells: [
                  const DataCell(Text('Labor (processed payroll)')),
                  const DataCell(Text('—')),
                  DataCell(Text(p(c.labor), style: numStyle)),
                  const DataCell(Text('—')),
                  const DataCell(Text('—')),
                ],
              ),
              DataRow(
                cells: [
                  const DataCell(Text('Equipment')),
                  const DataCell(Text('—')),
                  DataCell(Text(p(c.equipment), style: numStyle)),
                  const DataCell(Text('—')),
                  const DataCell(Text('—')),
                ],
              ),
              DataRow(
                color: const WidgetStatePropertyAll(AppColors.surfaceSunken),
                cells: [
                  const DataCell(
                    Text(
                      'Total',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  DataCell(Text(p(report.totalBudget), style: boldNumStyle)),
                  DataCell(Text(p(c.total), style: boldNumStyle)),
                  DataCell(
                    variance(report.totalBudget - c.total, bold: true),
                  ),
                  DataCell(
                    SizedBox(
                      width: 130,
                      child: AppBudgetBar(
                        budget: report.totalBudget,
                        actual: c.total,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

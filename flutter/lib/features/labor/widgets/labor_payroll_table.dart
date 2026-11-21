import 'package:flutter/material.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/utils/finance_access.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/input_parsers.dart';
import '../../../data/models/payroll_line.dart';
import '../../../data/services/session_service.dart';
import '../../../shared/widgets/app_empty_state.dart';

/// Pay per worker: days worked, cash advance, net pay, and payslip export.
class LaborPayrollTable extends StatelessWidget {
  const LaborPayrollTable({
    super.key,
    required this.lines,
    required this.workerName,
    this.onCashAdvance,
    this.onExportPayslip,
  });

  final List<PayrollLine> lines;
  final String Function(int id) workerName;

  /// Set while cash advances can still be changed.
  final ValueChanged<PayrollLine>? onCashAdvance;

  /// Optional per-worker payslip PDF export action.
  final ValueChanged<PayrollLine>? onExportPayslip;

  @override
  Widget build(BuildContext context) {
    if (getIt.isRegistered<SessionService>() &&
        getIt<SessionService>().isSignedIn &&
        !canSeeFinance()) {
      return const SizedBox.shrink();
    }
    if (lines.isEmpty) {
      return const AppEmptyState(
        icon: Icons.payments_outlined,
        message: 'No attendance recorded in this period.',
      );
    }

    String p(double v) => Formatters.peso(v);
    double sum(double Function(PayrollLine l) f) =>
        lines.fold(0, (s, l) => s + f(l));

    final scheme = Theme.of(context).colorScheme;
    final numStyle = Theme.of(
      context,
    ).textTheme.bodyMedium?.merge(AppTextStyles.numeric);
    final boldNumStyle = numStyle?.copyWith(fontWeight: FontWeight.w700);

    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: constraints.maxWidth),
          child: DataTable(
            headingRowColor: WidgetStatePropertyAll(
              scheme.surfaceContainerHighest.withValues(alpha: 0.6),
            ),
            columnSpacing: AppSpacing.lg,
            columns: [
              const DataColumn(label: Text('Worker')),
              const DataColumn(label: Text('Days'), numeric: true),
              const DataColumn(label: Text('Cash adv.'), numeric: true),
              const DataColumn(label: Text('Net pay'), numeric: true),
              if (onExportPayslip != null)
                const DataColumn(label: Text('Payslip')),
            ],
            rows: [
              for (final l in lines)
                DataRow(
                  cells: [
                    DataCell(Text(workerName(l.workerId))),
                    DataCell(
                      Text(
                        InputParsers.amountText(l.daysWorked),
                        style: numStyle,
                      ),
                    ),
                    DataCell(
                      Text(p(l.cashAdvance), style: numStyle),
                      showEditIcon: onCashAdvance != null,
                      onTap: onCashAdvance == null
                          ? null
                          : () => onCashAdvance!(l),
                    ),
                    DataCell(
                      Text(
                        p(l.netPay),
                        style: numStyle?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                    if (onExportPayslip != null)
                      DataCell(
                        IconButton(
                          tooltip: 'Export payslip PDF',
                          icon: const Icon(Icons.receipt_outlined, size: 18),
                          onPressed: () => onExportPayslip!(l),
                        ),
                      ),
                  ],
                ),
              DataRow(
                color: WidgetStatePropertyAll(scheme.surfaceContainerLowest),
                cells: [
                  const DataCell(
                    Text(
                      'Total',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  DataCell(
                    Text(
                      InputParsers.amountText(sum((l) => l.daysWorked)),
                      style: boldNumStyle,
                    ),
                  ),
                  DataCell(
                    Text(p(sum((l) => l.cashAdvance)), style: boldNumStyle),
                  ),
                  DataCell(Text(p(sum((l) => l.netPay)), style: boldNumStyle)),
                  if (onExportPayslip != null) const DataCell(SizedBox.shrink()),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

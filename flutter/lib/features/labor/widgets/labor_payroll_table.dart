import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/utils/finance_access.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/input_parsers.dart';
import '../../../data/models/payroll_line.dart';
import '../../../data/services/session_service.dart';
import '../../../shared/widgets/app_empty_state.dart';

/// Pay per worker: days, overtime, gross, contributions, cash advance, net.
class LaborPayrollTable extends StatelessWidget {
  const LaborPayrollTable({
    super.key,
    required this.lines,
    required this.workerName,
    this.onCashAdvance,
    this.showContributions = true,
  });

  final List<PayrollLine> lines;
  final String Function(int id) workerName;

  /// False for basic payroll: no government contributions are applied, so the
  /// three zero columns are left out instead of looking computed.
  final bool showContributions;

  /// Set while cash advances can still be changed.
  final ValueChanged<PayrollLine>? onCashAdvance;

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
            headingRowColor: const WidgetStatePropertyAll(
              AppColors.tableHeader,
            ),
            columnSpacing: AppSpacing.lg,
            columns: [
              const DataColumn(label: Text('Worker')),
              const DataColumn(label: Text('Days'), numeric: true),
              const DataColumn(label: Text('OT pay'), numeric: true),
              const DataColumn(label: Text('Gross'), numeric: true),
              if (showContributions) ...[
                const DataColumn(label: Text('SSS'), numeric: true),
                const DataColumn(label: Text('PhilHealth'), numeric: true),
                const DataColumn(label: Text('Pag-IBIG'), numeric: true),
              ],
              const DataColumn(label: Text('Cash adv.'), numeric: true),
              const DataColumn(label: Text('Net pay'), numeric: true),
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
                    DataCell(Text(p(l.overtimePay), style: numStyle)),
                    DataCell(Text(p(l.grossPay), style: numStyle)),
                    if (showContributions) ...[
                      DataCell(Text(p(l.sss), style: numStyle)),
                      DataCell(Text(p(l.philhealth), style: numStyle)),
                      DataCell(Text(p(l.pagibig), style: numStyle)),
                    ],
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
                  DataCell(
                    Text(
                      InputParsers.amountText(sum((l) => l.daysWorked)),
                      style: boldNumStyle,
                    ),
                  ),
                  DataCell(
                    Text(p(sum((l) => l.overtimePay)), style: boldNumStyle),
                  ),
                  DataCell(
                    Text(p(sum((l) => l.grossPay)), style: boldNumStyle),
                  ),
                  if (showContributions) ...[
                    DataCell(Text(p(sum((l) => l.sss)), style: boldNumStyle)),
                    DataCell(
                      Text(p(sum((l) => l.philhealth)), style: boldNumStyle),
                    ),
                    DataCell(
                      Text(p(sum((l) => l.pagibig)), style: boldNumStyle),
                    ),
                  ],
                  DataCell(
                    Text(p(sum((l) => l.cashAdvance)), style: boldNumStyle),
                  ),
                  DataCell(Text(p(sum((l) => l.netPay)), style: boldNumStyle)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

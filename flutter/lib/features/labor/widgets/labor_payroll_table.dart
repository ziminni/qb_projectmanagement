import 'package:flutter/material.dart';

import '../../../core/utils/formatters.dart';
import '../../../core/utils/input_parsers.dart';
import '../../../data/models/payroll_line.dart';

/// Pay per worker: days, overtime, gross, contributions, cash advance, net.
class LaborPayrollTable extends StatelessWidget {
  const LaborPayrollTable({
    super.key,
    required this.lines,
    required this.workerName,
    this.onCashAdvance,
  });

  final List<PayrollLine> lines;
  final String Function(int id) workerName;

  /// Set while cash advances can still be changed.
  final ValueChanged<PayrollLine>? onCashAdvance;

  @override
  Widget build(BuildContext context) {
    if (lines.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('No attendance recorded in this period.'),
      );
    }
    String p(double v) => Formatters.peso(v);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: const [
          DataColumn(label: Text('Worker')),
          DataColumn(label: Text('Days'), numeric: true),
          DataColumn(label: Text('OT pay'), numeric: true),
          DataColumn(label: Text('Gross'), numeric: true),
          DataColumn(label: Text('SSS'), numeric: true),
          DataColumn(label: Text('PhilHealth'), numeric: true),
          DataColumn(label: Text('Pag-IBIG'), numeric: true),
          DataColumn(label: Text('Cash adv.'), numeric: true),
          DataColumn(label: Text('Net pay'), numeric: true),
        ],
        rows: [
          for (final l in lines)
            DataRow(
              cells: [
                DataCell(Text(workerName(l.workerId))),
                DataCell(Text(InputParsers.amountText(l.daysWorked))),
                DataCell(Text(p(l.overtimePay))),
                DataCell(Text(p(l.grossPay))),
                DataCell(Text(p(l.sss))),
                DataCell(Text(p(l.philhealth))),
                DataCell(Text(p(l.pagibig))),
                DataCell(
                  Text(p(l.cashAdvance)),
                  showEditIcon: onCashAdvance != null,
                  onTap: onCashAdvance == null ? null : () => onCashAdvance!(l),
                ),
                DataCell(
                  Text(
                    p(l.netPay),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

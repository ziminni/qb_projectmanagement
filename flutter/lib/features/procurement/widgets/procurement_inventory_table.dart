import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/utils/input_parsers.dart';
import '../../../data/services/inventory_calculator.dart';
import '../../../shared/widgets/app_empty_state.dart';

/// Site inventory: received, damaged, used on approved reports, on hand.
class ProcurementInventoryTable extends StatelessWidget {
  const ProcurementInventoryTable({super.key, required this.lines});

  final List<InventoryLine> lines;

  @override
  Widget build(BuildContext context) {
    if (lines.isEmpty) {
      return const AppEmptyState(
        icon: Icons.inventory_2_outlined,
        message: 'Nothing delivered to this site yet.',
      );
    }
    String q(double v) => InputParsers.amountText(v);
    final numStyle = Theme.of(
      context,
    ).textTheme.bodyMedium?.merge(AppTextStyles.numeric);
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
              DataColumn(label: Text('Material')),
              DataColumn(label: Text('Received'), numeric: true),
              DataColumn(label: Text('Damaged'), numeric: true),
              DataColumn(label: Text('Used'), numeric: true),
              DataColumn(label: Text('On hand'), numeric: true),
            ],
            rows: [
              for (final l in lines)
                DataRow(
                  cells: [
                    DataCell(Text(l.name)),
                    DataCell(Text(q(l.received), style: numStyle)),
                    DataCell(Text(q(l.damaged), style: numStyle)),
                    DataCell(Text(q(l.used), style: numStyle)),
                    DataCell(
                      Text(
                        '${q(l.onHand)} ${l.unit}',
                        style: numStyle?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: l.onHand < 0 ? AppColors.error : null,
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

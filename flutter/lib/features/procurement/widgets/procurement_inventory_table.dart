import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/utils/input_parsers.dart';
import '../../../data/services/inventory_calculator.dart';

/// Site inventory: received, damaged, used on approved reports, on hand.
class ProcurementInventoryTable extends StatelessWidget {
  const ProcurementInventoryTable({
    super.key,
    required this.lines,
    required this.materialName,
    required this.unit,
  });

  final List<InventoryLine> lines;
  final String Function(int id) materialName;
  final String Function(int id) unit;

  @override
  Widget build(BuildContext context) {
    if (lines.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('Nothing delivered to this site yet.'),
      );
    }
    String q(double v) => InputParsers.amountText(v);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
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
                DataCell(Text(materialName(l.materialId))),
                DataCell(Text(q(l.received))),
                DataCell(Text(q(l.damaged))),
                DataCell(Text(q(l.used))),
                DataCell(
                  Text(
                    '${q(l.onHand)} ${unit(l.materialId)}',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: l.onHand < 0 ? AppColors.error : null,
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

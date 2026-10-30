import 'package:flutter/material.dart';

import '../../../core/utils/finance_access.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/models/material_source.dart';
import '../../../data/models/purchase_order.dart';
import 'procurement_po_status_chip.dart';

class ProcurementPoTile extends StatelessWidget {
  const ProcurementPoTile({
    super.key,
    required this.order,
    required this.projectCode,
    required this.supplierName,
    required this.onTap,
    this.trailing,
  });

  final PurchaseOrder order;
  final String projectCode;
  final String supplierName;
  final VoidCallback onTap;

  /// Replaces the status chip, e.g. with a Confirm delivery button.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: Icon(
        order.source == MaterialSource.ownStore
            ? Icons.storefront_outlined
            : Icons.local_shipping_outlined,
      ),
      title: Text('${order.poNo} · $projectCode'),
      subtitle: Text(
        '$supplierName · ${order.source.label}'
        '${canSeeFinance() ? ' · ${Formatters.peso(order.totalAmount)}' : ''}',
      ),
      trailing: trailing ?? ProcurementPoStatusChip(status: order.status),
    );
  }
}

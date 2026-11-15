import 'package:flutter/material.dart';

import '../../../core/utils/formatters.dart';
import '../../../data/models/purchase_order.dart';
import '../../../data/repositories/procurement_repository.dart';

class ProcurementDeliveryTile extends StatelessWidget {
  const ProcurementDeliveryTile({
    super.key,
    required this.delivery,
    required this.order,
    required this.receivedBy,
    required this.onTap,
  });

  final DeliveryDetail delivery;
  final PurchaseOrder order;
  final String receivedBy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final damaged = delivery.items.fold<double>(0, (s, i) => s + i.qtyDamaged);
    return ListTile(
      onTap: onTap,
      leading: const Icon(Icons.inventory_outlined),
      title: Text(
        '${order.poNo} · ${Formatters.date(delivery.delivery.receivedAt)}',
      ),
      subtitle: Text(
        'Received by $receivedBy · ${delivery.items.length} line(s)'
        '${damaged > 0 ? ' · some damaged' : ''}'
        '${delivery.delivery.receiptPhotoUrl != null ? ' · receipt photo' : ''}',
      ),
      trailing: const Icon(Icons.chevron_right),
    );
  }
}

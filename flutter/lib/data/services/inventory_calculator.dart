import '../models/delivery_item.dart';
import '../models/purchase_order_item.dart';
import '../models/report_material_usage.dart';

/// One material's stock on a site.
class InventoryLine {
  const InventoryLine({
    required this.materialId,
    required this.received,
    required this.damaged,
    required this.used,
  });

  final int materialId;
  final double received;
  final double damaged;

  /// From approved daily reports.
  final double used;

  /// Deliveries received − damaged − materials used. Negative means more
  /// was reported used than was delivered.
  double get onHand => received - damaged - used;
}

/// Site inventory is computed, never stored: deliveries received minus
/// materials used on approved daily reports.
List<InventoryLine> computeSiteInventory({
  required List<PurchaseOrderItem> orderItems,
  required List<DeliveryItem> deliveryItems,
  required List<ReportMaterialUsage> usage,
}) {
  final materialOf = {for (final i in orderItems) i.id: i.materialId};
  final received = <int, double>{};
  final damaged = <int, double>{};
  final used = <int, double>{};
  for (final d in deliveryItems) {
    final m = materialOf[d.purchaseOrderItemId];
    if (m == null) continue;
    received[m] = (received[m] ?? 0) + d.qtyReceived;
    damaged[m] = (damaged[m] ?? 0) + d.qtyDamaged;
  }
  for (final u in usage) {
    used[u.materialId] = (used[u.materialId] ?? 0) + u.quantity;
  }
  final ids = {...received.keys, ...used.keys};
  return [
    for (final id in ids)
      InventoryLine(
        materialId: id,
        received: received[id] ?? 0,
        damaged: damaged[id] ?? 0,
        used: used[id] ?? 0,
      ),
  ];
}

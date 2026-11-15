import '../models/delivery_item.dart';
import '../models/material_item.dart';
import '../models/purchase_order_item.dart';
import '../models/report_material_usage.dart';

/// One material's stock on a site. Price-list materials are tracked by
/// [materialId]; anything bought outside the price list by its name.
class InventoryLine {
  const InventoryLine({
    this.materialId,
    required this.name,
    required this.unit,
    required this.received,
    required this.damaged,
    required this.used,
  });

  final int? materialId;
  final String name;
  final String unit;
  final double received;
  final double damaged;

  /// From approved daily reports.
  final double used;

  /// Deliveries received − damaged − materials used. Negative means more
  /// was reported used than was delivered.
  double get onHand => received - damaged - used;

  /// The site engineer must count it before a new material request.
  bool get needsCount => onHand != 0;

  /// Identifies the material across orders and counts.
  String get key => inventoryKey(materialId, name);
}

String inventoryKey(int? materialId, String name) =>
    materialId != null ? 'm$materialId' : 'n:${name.trim().toLowerCase()}';

/// Site inventory is computed, never stored: deliveries received minus
/// materials used on approved daily reports.
List<InventoryLine> computeSiteInventory({
  required List<PurchaseOrderItem> orderItems,
  required List<DeliveryItem> deliveryItems,
  required List<ReportMaterialUsage> usage,
  required Map<int, MaterialItem> materials,
}) {
  final itemById = {for (final i in orderItems) i.id: i};
  final names = <String, ({int? materialId, String name, String unit})>{};
  final received = <String, double>{};
  final damaged = <String, double>{};
  final used = <String, double>{};
  String keyFor(int? materialId, String name, String unit) {
    final m = materialId == null ? null : materials[materialId];
    final key = inventoryKey(materialId, name);
    names.putIfAbsent(
      key,
      () => (
        materialId: materialId,
        name: m?.name ?? name.trim(),
        unit: m?.unit ?? unit,
      ),
    );
    return key;
  }

  for (final d in deliveryItems) {
    final item = itemById[d.purchaseOrderItemId];
    if (item == null) continue;
    final k = keyFor(item.materialId, item.description, item.unit);
    received[k] = (received[k] ?? 0) + d.qtyReceived;
    damaged[k] = (damaged[k] ?? 0) + d.qtyDamaged;
  }
  for (final u in usage) {
    final m = materials[u.materialId];
    final k = keyFor(u.materialId, m?.name ?? 'Material #${u.materialId}', '');
    used[k] = (used[k] ?? 0) + u.quantity;
  }
  return [
    for (final e in names.entries)
      InventoryLine(
        materialId: e.value.materialId,
        name: e.value.name,
        unit: e.value.unit,
        received: received[e.key] ?? 0,
        damaged: damaged[e.key] ?? 0,
        used: used[e.key] ?? 0,
      ),
  ]..sort((a, b) => a.name.compareTo(b.name));
}

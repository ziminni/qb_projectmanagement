import 'json_utils.dart';

/// A row in `delivery_items`. [qtyDamaged] is part of [qtyReceived].
class DeliveryItem {
  const DeliveryItem({
    required this.id,
    required this.deliveryId,
    required this.purchaseOrderItemId,
    required this.qtyReceived,
    this.qtyDamaged = 0,
    this.createdAt,
    this.updatedAt,
  });

  final int id;
  final int deliveryId;
  final int purchaseOrderItemId;
  final double qtyReceived;
  final double qtyDamaged;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Usable quantity that goes into site inventory.
  double get qtyGood => qtyReceived - qtyDamaged;

  factory DeliveryItem.fromJson(Map<String, dynamic> json) => DeliveryItem(
    id: json['id'] as int,
    deliveryId: json['delivery_id'] as int,
    purchaseOrderItemId: json['purchase_order_item_id'] as int,
    qtyReceived: JsonUtils.toDouble(json['qty_received']),
    qtyDamaged: JsonUtils.toDouble(json['qty_damaged'] ?? 0),
    createdAt: JsonUtils.toDateOrNull(json['created_at']),
    updatedAt: JsonUtils.toDateOrNull(json['updated_at']),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'delivery_id': deliveryId,
    'purchase_order_item_id': purchaseOrderItemId,
    'qty_received': qtyReceived,
    'qty_damaged': qtyDamaged,
    'created_at': JsonUtils.fromDateTimeOrNull(createdAt),
    'updated_at': JsonUtils.fromDateTimeOrNull(updatedAt),
  };
}

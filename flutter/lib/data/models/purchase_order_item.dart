import 'json_utils.dart';

/// A row in `purchase_order_items`.
class PurchaseOrderItem {
  const PurchaseOrderItem({
    required this.id,
    required this.purchaseOrderId,
    required this.materialRequestItemId,
    required this.materialId,
    required this.quantity,
    required this.unitPrice,
    this.createdAt,
    this.updatedAt,
  });

  final int id;
  final int purchaseOrderId;
  final int materialRequestItemId;
  final int materialId;
  final double quantity;
  final double unitPrice;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  double get amount => quantity * unitPrice;

  factory PurchaseOrderItem.fromJson(Map<String, dynamic> json) =>
      PurchaseOrderItem(
        id: json['id'] as int,
        purchaseOrderId: json['purchase_order_id'] as int,
        materialRequestItemId: json['material_request_item_id'] as int,
        materialId: json['material_id'] as int,
        quantity: JsonUtils.toDouble(json['quantity']),
        unitPrice: JsonUtils.toDouble(json['unit_price']),
        createdAt: JsonUtils.toDateOrNull(json['created_at']),
        updatedAt: JsonUtils.toDateOrNull(json['updated_at']),
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'purchase_order_id': purchaseOrderId,
    'material_request_item_id': materialRequestItemId,
    'material_id': materialId,
    'quantity': quantity,
    'unit_price': unitPrice,
    'created_at': JsonUtils.fromDateTimeOrNull(createdAt),
    'updated_at': JsonUtils.fromDateTimeOrNull(updatedAt),
  };
}

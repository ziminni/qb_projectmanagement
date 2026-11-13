import 'json_utils.dart';

/// A row in `material_request_items`: what the site engineer needs, typed
/// in their own words. The owner picks the actual materials when ordering
/// and ticks the item off against the order that covers it.
class MaterialRequestItem {
  const MaterialRequestItem({
    required this.id,
    required this.materialRequestId,
    required this.description,
    required this.unit,
    required this.quantity,
    this.purchaseOrderId,
    this.createdAt,
    this.updatedAt,
  });

  final int id;
  final int materialRequestId;
  final String description;
  final String unit;
  final double quantity;

  /// The order that covers this item, once the owner ticks it off.
  final int? purchaseOrderId;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isCovered => purchaseOrderId != null;

  MaterialRequestItem coveredBy(int? orderId) => MaterialRequestItem(
    id: id,
    materialRequestId: materialRequestId,
    description: description,
    unit: unit,
    quantity: quantity,
    purchaseOrderId: orderId,
    createdAt: createdAt,
    updatedAt: DateTime.now(),
  );

  factory MaterialRequestItem.fromJson(Map<String, dynamic> json) =>
      MaterialRequestItem(
        id: json['id'] as int,
        materialRequestId: json['material_request_id'] as int,
        description: json['description'] as String,
        unit: json['unit'] as String? ?? '',
        quantity: JsonUtils.toDouble(json['quantity']),
        purchaseOrderId: json['purchase_order_id'] as int?,
        createdAt: JsonUtils.toDateOrNull(json['created_at']),
        updatedAt: JsonUtils.toDateOrNull(json['updated_at']),
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'material_request_id': materialRequestId,
    'description': description,
    'unit': unit,
    'quantity': quantity,
    'purchase_order_id': purchaseOrderId,
    'created_at': JsonUtils.fromDateTimeOrNull(createdAt),
    'updated_at': JsonUtils.fromDateTimeOrNull(updatedAt),
  };
}

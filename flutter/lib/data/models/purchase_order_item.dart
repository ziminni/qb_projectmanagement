import 'json_utils.dart';

/// A row in `purchase_order_items`. Own-store lines always carry the
/// [materialId] of the price-list item picked from the store catalog; an
/// other-store line has one only when its name matches the price list.
class PurchaseOrderItem {
  const PurchaseOrderItem({
    required this.id,
    required this.purchaseOrderId,
    this.materialId,
    required this.description,
    required this.unit,
    required this.quantity,
    required this.unitPrice,
    this.createdAt,
    this.updatedAt,
  });

  final int id;
  final int purchaseOrderId;
  final int? materialId;
  final String description;
  final String unit;
  final double quantity;
  final double unitPrice;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  double get amount => quantity * unitPrice;

  /// [financeKeysOmitted] is what a role without finance access receives: the
  /// server drops `unit_price` rather than sending a fictional zero (decision
  /// 06, ruling 1).
  factory PurchaseOrderItem.fromJson(
    Map<String, dynamic> json, {
    bool financeKeysOmitted = false,
  }) => PurchaseOrderItem(
    id: json['id'] as int,
    purchaseOrderId: json['purchase_order_id'] as int,
    materialId: json['material_id'] as int?,
    description: json['description'] as String,
    unit: json['unit'] as String? ?? '',
    quantity: JsonUtils.toDouble(json['quantity']),
    unitPrice: JsonUtils.toFinanceDouble(
      json['unit_price'],
      omitted: financeKeysOmitted,
    ),
    createdAt: JsonUtils.toDateOrNull(json['created_at']),
    updatedAt: JsonUtils.toDateOrNull(json['updated_at']),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'purchase_order_id': purchaseOrderId,
    'material_id': materialId,
    'description': description,
    'unit': unit,
    'quantity': quantity,
    'unit_price': unitPrice,
    'created_at': JsonUtils.fromDateTimeOrNull(createdAt),
    'updated_at': JsonUtils.fromDateTimeOrNull(updatedAt),
  };
}

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
    this.plannedMaterialId,
    this.plannedQty,
    this.isUnplanned = false,
    this.overPlanReason = '',
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

  /// Linked DUPA Section C planned material row, when picked from plan.
  final int? plannedMaterialId;
  final double? plannedQty;
  final bool isUnplanned;
  final String overPlanReason;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isCovered => purchaseOrderId != null;
  bool get isPlanned => plannedMaterialId != null;
  bool get isOverPlan =>
      plannedQty != null && quantity > plannedQty! + 0.0001;

  MaterialRequestItem coveredBy(int? orderId) => MaterialRequestItem(
    id: id,
    materialRequestId: materialRequestId,
    description: description,
    unit: unit,
    quantity: quantity,
    purchaseOrderId: orderId,
    plannedMaterialId: plannedMaterialId,
    plannedQty: plannedQty,
    isUnplanned: isUnplanned,
    overPlanReason: overPlanReason,
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
        plannedMaterialId: json['planned_material_id'] as int?,
        plannedQty: JsonUtils.toDoubleOrNull(json['planned_qty']),
        isUnplanned: json['is_unplanned'] as bool? ?? false,
        overPlanReason: (json['over_plan_reason'] as String?) ?? '',
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
    'planned_material_id': plannedMaterialId,
    'planned_qty': plannedQty,
    'is_unplanned': isUnplanned,
    'over_plan_reason': overPlanReason,
    'created_at': JsonUtils.fromDateTimeOrNull(createdAt),
    'updated_at': JsonUtils.fromDateTimeOrNull(updatedAt),
  };
}

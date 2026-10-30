import 'json_utils.dart';
import 'material_source.dart';

enum PurchaseOrderStatus implements JsonEnum {
  released('released', 'Released'),
  partiallyDelivered('partially_delivered', 'Partially delivered'),
  delivered('delivered', 'Delivered'),
  cancelled('cancelled', 'Cancelled');

  const PurchaseOrderStatus(this.apiValue, this.label);

  @override
  final String apiValue;
  final String label;

  /// Released to the supplier and still expecting deliveries.
  bool get awaitsDelivery =>
      this == PurchaseOrderStatus.released ||
      this == PurchaseOrderStatus.partiallyDelivered;

  static PurchaseOrderStatus fromJson(Object? raw) => enumFromApi(values, raw);

  String toJson() => apiValue;
}

/// A row in `purchase_orders`.
class PurchaseOrder {
  const PurchaseOrder({
    required this.id,
    required this.poNo,
    required this.projectId,
    required this.supplierId,
    required this.source,
    required this.status,
    required this.totalAmount,
    this.approvedBy,
    this.createdAt,
    this.updatedAt,
  });

  final int id;
  final String poNo;
  final int projectId;
  final int supplierId;
  final MaterialSource source;
  final PurchaseOrderStatus status;
  final double totalAmount;

  /// The owner who placed the order.
  final int? approvedBy;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  PurchaseOrder copyWith({
    PurchaseOrderStatus? status,
    int? Function()? approvedBy,
  }) => PurchaseOrder(
    id: id,
    poNo: poNo,
    projectId: projectId,
    supplierId: supplierId,
    source: source,
    status: status ?? this.status,
    totalAmount: totalAmount,
    approvedBy: approvedBy != null ? approvedBy() : this.approvedBy,
    createdAt: createdAt,
    updatedAt: DateTime.now(),
  );

  factory PurchaseOrder.fromJson(Map<String, dynamic> json) => PurchaseOrder(
    id: json['id'] as int,
    poNo: json['po_no'] as String,
    projectId: json['project_id'] as int,
    supplierId: json['supplier_id'] as int,
    source: MaterialSource.fromJson(json['source']),
    status: PurchaseOrderStatus.fromJson(json['status']),
    totalAmount: JsonUtils.toDouble(json['total_amount']),
    approvedBy: json['approved_by'] as int?,
    createdAt: JsonUtils.toDateOrNull(json['created_at']),
    updatedAt: JsonUtils.toDateOrNull(json['updated_at']),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'po_no': poNo,
    'project_id': projectId,
    'supplier_id': supplierId,
    'source': source.toJson(),
    'status': status.toJson(),
    'total_amount': totalAmount,
    'approved_by': approvedBy,
    'created_at': JsonUtils.fromDateTimeOrNull(createdAt),
    'updated_at': JsonUtils.fromDateTimeOrNull(updatedAt),
  };
}

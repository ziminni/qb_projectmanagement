import 'json_utils.dart';

/// A row in `deliveries`: one delivery receipt against a purchase order.
class Delivery {
  const Delivery({
    required this.id,
    required this.purchaseOrderId,
    required this.receivedBy,
    required this.receivedAt,
    this.receiptPhotoUrl,
    this.createdAt,
    this.updatedAt,
  });

  final int id;
  final int purchaseOrderId;
  final int receivedBy;
  final DateTime receivedAt;
  final String? receiptPhotoUrl;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory Delivery.fromJson(Map<String, dynamic> json) => Delivery(
    id: json['id'] as int,
    purchaseOrderId: json['purchase_order_id'] as int,
    receivedBy: json['received_by'] as int,
    receivedAt: JsonUtils.toDate(json['received_at']),
    receiptPhotoUrl: json['receipt_photo_url'] as String?,
    createdAt: JsonUtils.toDateOrNull(json['created_at']),
    updatedAt: JsonUtils.toDateOrNull(json['updated_at']),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'purchase_order_id': purchaseOrderId,
    'received_by': receivedBy,
    'received_at': JsonUtils.fromDateTime(receivedAt),
    'receipt_photo_url': receiptPhotoUrl,
    'created_at': JsonUtils.fromDateTimeOrNull(createdAt),
    'updated_at': JsonUtils.fromDateTimeOrNull(updatedAt),
  };
}

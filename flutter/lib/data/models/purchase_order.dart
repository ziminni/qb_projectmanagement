import 'json_utils.dart';
import 'material_source.dart';

enum PurchaseOrderStatus implements JsonEnum {
  /// Own-store order sent to the hardware store.
  released('released', 'Released'),

  /// Bought and paid at another store; waiting to arrive on site.
  purchased('purchased', 'Bought'),
  partiallyDelivered('partially_delivered', 'Partially delivered'),
  delivered('delivered', 'Delivered'),
  cancelled('cancelled', 'Cancelled');

  const PurchaseOrderStatus(this.apiValue, this.label);

  @override
  final String apiValue;
  final String label;

  /// Still expecting deliveries on site.
  bool get awaitsDelivery =>
      this == PurchaseOrderStatus.released ||
      this == PurchaseOrderStatus.purchased ||
      this == PurchaseOrderStatus.partiallyDelivered;

  static PurchaseOrderStatus fromJson(Object? raw) => enumFromApi(values, raw);

  String toJson() => apiValue;
}

/// A row in `purchase_orders`: the owner's answer to a material request.
/// An own-store order goes to the company's hardware store ([supplierId])
/// with a [deliveryAddress]; an other-store purchase is logged after paying,
/// with the store's name, its official receipt number and a receipt photo.
class PurchaseOrder {
  const PurchaseOrder({
    required this.id,
    required this.poNo,
    required this.projectId,
    this.materialRequestId,
    this.categoryId,
    this.supplierId,
    this.storeName,
    required this.source,
    required this.status,
    required this.totalAmount,
    this.deliveryAddress,
    this.orNumber,
    this.receiptPhotoUrl,
    this.approvedBy,
    this.createdAt,
    this.updatedAt,
    this.financeKeysOmitted = false,
  });

  final int id;
  final String poNo;
  final int projectId;
  final int? materialRequestId;

  /// The budget category the owner charged this order to.
  final int? categoryId;

  /// A supplier from the master list (always the own store for own-store
  /// orders).
  final int? supplierId;

  /// Typed in for other-store purchases.
  final String? storeName;
  final MaterialSource source;
  final PurchaseOrderStatus status;
  final double totalAmount;
  final String? deliveryAddress;

  /// Official receipt number of an other-store purchase.
  final String? orNumber;
  final String? receiptPhotoUrl;

  /// The owner who placed the order.
  final int? approvedBy;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// True when the server withheld the finance keys for this row.
  final bool financeKeysOmitted;

  /// Paid at the counter when bought, so it is never a payable. `or_number`
  /// is finance-only, so a role it was redacted from decides by the source,
  /// which the server never hides.
  bool get paidOnPurchase =>
      source == MaterialSource.external &&
      (financeKeysOmitted || orNumber != null);

  PurchaseOrder copyWith({
    PurchaseOrderStatus? status,
    int? Function()? approvedBy,
  }) => PurchaseOrder(
    id: id,
    poNo: poNo,
    projectId: projectId,
    materialRequestId: materialRequestId,
    categoryId: categoryId,
    supplierId: supplierId,
    storeName: storeName,
    source: source,
    status: status ?? this.status,
    totalAmount: totalAmount,
    deliveryAddress: deliveryAddress,
    orNumber: orNumber,
    receiptPhotoUrl: receiptPhotoUrl,
    approvedBy: approvedBy != null ? approvedBy() : this.approvedBy,
    createdAt: createdAt,
    updatedAt: DateTime.now(),
    financeKeysOmitted: financeKeysOmitted,
  );

  /// [financeKeysOmitted] is what a role without finance access receives: the
  /// server drops `total_amount` rather than sending a fictional zero
  /// (decision 06, ruling 1).
  factory PurchaseOrder.fromJson(
    Map<String, dynamic> json, {
    bool financeKeysOmitted = false,
  }) => PurchaseOrder(
    id: json['id'] as int,
    poNo: json['po_no'] as String,
    projectId: json['project_id'] as int,
    materialRequestId: json['material_request_id'] as int?,
    categoryId: json['category_id'] as int?,
    supplierId: json['supplier_id'] as int?,
    storeName: json['store_name'] as String?,
    source: MaterialSource.fromJson(json['source']),
    status: PurchaseOrderStatus.fromJson(json['status']),
    totalAmount: JsonUtils.toFinanceDouble(
      json['total_amount'],
      omitted: financeKeysOmitted,
    ),
    deliveryAddress: json['delivery_address'] as String?,
    orNumber: json['or_number'] as String?,
    receiptPhotoUrl: json['receipt_photo_url'] as String?,
    approvedBy: json['approved_by'] as int?,
    createdAt: JsonUtils.toDateOrNull(json['created_at']),
    updatedAt: JsonUtils.toDateOrNull(json['updated_at']),
    financeKeysOmitted: financeKeysOmitted,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'po_no': poNo,
    'project_id': projectId,
    'material_request_id': materialRequestId,
    'category_id': categoryId,
    'supplier_id': supplierId,
    'store_name': storeName,
    'source': source.toJson(),
    'status': status.toJson(),
    'total_amount': totalAmount,
    'delivery_address': deliveryAddress,
    'or_number': orNumber,
    'receipt_photo_url': receiptPhotoUrl,
    'approved_by': approvedBy,
    'created_at': JsonUtils.fromDateTimeOrNull(createdAt),
    'updated_at': JsonUtils.fromDateTimeOrNull(updatedAt),
  };
}

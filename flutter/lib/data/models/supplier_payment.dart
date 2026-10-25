import 'json_utils.dart';
import 'payment_method.dart';

/// A row in `supplier_payments`. Not in the design document's table list
/// (its `payments` table is for client billings); it records the
/// accountant's supplier payments against a purchase order.
class SupplierPayment {
  const SupplierPayment({
    required this.id,
    required this.purchaseOrderId,
    required this.amount,
    required this.paidOn,
    required this.method,
    this.referenceNo,
    this.createdAt,
    this.updatedAt,
  });

  final int id;
  final int purchaseOrderId;
  final double amount;
  final DateTime paidOn;
  final PaymentMethod method;
  final String? referenceNo;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory SupplierPayment.fromJson(Map<String, dynamic> json) =>
      SupplierPayment(
        id: json['id'] as int,
        purchaseOrderId: json['purchase_order_id'] as int,
        amount: JsonUtils.toDouble(json['amount']),
        paidOn: JsonUtils.toDate(json['paid_on']),
        method: PaymentMethod.fromJson(json['method']),
        referenceNo: json['reference_no'] as String?,
        createdAt: JsonUtils.toDateOrNull(json['created_at']),
        updatedAt: JsonUtils.toDateOrNull(json['updated_at']),
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'purchase_order_id': purchaseOrderId,
    'amount': amount,
    'paid_on': JsonUtils.fromDate(paidOn),
    'method': method.toJson(),
    'reference_no': referenceNo,
    'created_at': JsonUtils.fromDateTimeOrNull(createdAt),
    'updated_at': JsonUtils.fromDateTimeOrNull(updatedAt),
  };
}

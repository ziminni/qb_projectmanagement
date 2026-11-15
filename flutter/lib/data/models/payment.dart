import 'json_utils.dart';
import 'payment_method.dart';

/// A row in `payments`: the client's payment against a progress billing.
class Payment {
  const Payment({
    required this.id,
    required this.progressBillingId,
    required this.amount,
    required this.paidOn,
    required this.method,
    this.referenceNo,
    this.createdAt,
    this.updatedAt,
  });

  final int id;
  final int progressBillingId;
  final double amount;
  final DateTime paidOn;
  final PaymentMethod method;
  final String? referenceNo;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory Payment.fromJson(Map<String, dynamic> json) => Payment(
    id: json['id'] as int,
    progressBillingId: json['progress_billing_id'] as int,
    amount: JsonUtils.toDouble(json['amount']),
    paidOn: JsonUtils.toDate(json['paid_on']),
    method: PaymentMethod.fromJson(json['method']),
    referenceNo: json['reference_no'] as String?,
    createdAt: JsonUtils.toDateOrNull(json['created_at']),
    updatedAt: JsonUtils.toDateOrNull(json['updated_at']),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'progress_billing_id': progressBillingId,
    'amount': amount,
    'paid_on': JsonUtils.fromDate(paidOn),
    'method': method.toJson(),
    'reference_no': referenceNo,
    'created_at': JsonUtils.fromDateTimeOrNull(createdAt),
    'updated_at': JsonUtils.fromDateTimeOrNull(updatedAt),
  };
}

import 'json_utils.dart';
import 'payment_method.dart';

/// A row in `retention_releases`. Not in the design document's table list;
/// it records retention paid back to the contractor after completion.
class RetentionRelease {
  const RetentionRelease({
    required this.id,
    required this.projectId,
    required this.amount,
    required this.releasedOn,
    required this.method,
    this.referenceNo,
    this.createdAt,
    this.updatedAt,
  });

  final int id;
  final int projectId;
  final double amount;
  final DateTime releasedOn;
  final PaymentMethod method;
  final String? referenceNo;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory RetentionRelease.fromJson(Map<String, dynamic> json) =>
      RetentionRelease(
        id: json['id'] as int,
        projectId: json['project_id'] as int,
        amount: JsonUtils.toDouble(json['amount']),
        releasedOn: JsonUtils.toDate(json['released_on']),
        method: PaymentMethod.fromJson(json['method']),
        referenceNo: json['reference_no'] as String?,
        createdAt: JsonUtils.toDateOrNull(json['created_at']),
        updatedAt: JsonUtils.toDateOrNull(json['updated_at']),
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'project_id': projectId,
    'amount': amount,
    'released_on': JsonUtils.fromDate(releasedOn),
    'method': method.toJson(),
    'reference_no': referenceNo,
    'created_at': JsonUtils.fromDateTimeOrNull(createdAt),
    'updated_at': JsonUtils.fromDateTimeOrNull(updatedAt),
  };
}

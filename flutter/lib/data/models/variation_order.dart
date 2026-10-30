import 'json_utils.dart';

enum VariationOrderType implements JsonEnum {
  additive('additive', 'Added work'),
  deductive('deductive', 'Deleted work'),
  change('change', 'Design change');

  const VariationOrderType(this.apiValue, this.label);

  @override
  final String apiValue;
  final String label;

  static VariationOrderType fromJson(Object? raw) => enumFromApi(values, raw);

  String toJson() => apiValue;
}

enum VariationOrderStatus implements JsonEnum {
  proposed('proposed', 'Proposed'),
  pendingClient('pending_client', 'Waiting for client'),
  approved('approved', 'Approved'),
  rejected('rejected', 'Rejected');

  const VariationOrderStatus(this.apiValue, this.label);

  @override
  final String apiValue;
  final String label;

  static VariationOrderStatus fromJson(Object? raw) => enumFromApi(values, raw);

  String toJson() => apiValue;
}

/// A row in `variation_orders`. [amount] is signed: negative for deleted
/// work.
class VariationOrder {
  const VariationOrder({
    required this.id,
    required this.projectId,
    required this.voNo,
    required this.type,
    required this.description,
    required this.amount,
    required this.daysImpact,
    required this.status,
    this.approvedByOwner,
    this.approvedByClient,
    this.createdAt,
    this.updatedAt,
  });

  final int id;
  final int projectId;
  final String voNo;
  final VariationOrderType type;
  final String description;
  final double amount;
  final int daysImpact;
  final VariationOrderStatus status;
  final int? approvedByOwner;
  final int? approvedByClient;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  VariationOrder copyWith({
    int? id,
    String? voNo,
    VariationOrderType? type,
    String? description,
    double? amount,
    int? daysImpact,
    VariationOrderStatus? status,
    int? Function()? approvedByOwner,
    int? Function()? approvedByClient,
  }) => VariationOrder(
    id: id ?? this.id,
    projectId: projectId,
    voNo: voNo ?? this.voNo,
    type: type ?? this.type,
    description: description ?? this.description,
    amount: amount ?? this.amount,
    daysImpact: daysImpact ?? this.daysImpact,
    status: status ?? this.status,
    approvedByOwner: approvedByOwner != null
        ? approvedByOwner()
        : this.approvedByOwner,
    approvedByClient: approvedByClient != null
        ? approvedByClient()
        : this.approvedByClient,
    createdAt: createdAt,
    updatedAt: DateTime.now(),
  );

  factory VariationOrder.fromJson(Map<String, dynamic> json) => VariationOrder(
    id: json['id'] as int,
    projectId: json['project_id'] as int,
    voNo: json['vo_no'] as String,
    type: VariationOrderType.fromJson(json['type']),
    description: json['description'] as String,
    amount: JsonUtils.toDouble(json['amount']),
    daysImpact: json['days_impact'] as int,
    status: VariationOrderStatus.fromJson(json['status']),
    approvedByOwner: json['approved_by_owner'] as int?,
    approvedByClient: json['approved_by_client'] as int?,
    createdAt: JsonUtils.toDateOrNull(json['created_at']),
    updatedAt: JsonUtils.toDateOrNull(json['updated_at']),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'project_id': projectId,
    'vo_no': voNo,
    'type': type.toJson(),
    'description': description,
    'amount': amount,
    'days_impact': daysImpact,
    'status': status.toJson(),
    'approved_by_owner': approvedByOwner,
    'approved_by_client': approvedByClient,
    'created_at': JsonUtils.fromDateTimeOrNull(createdAt),
    'updated_at': JsonUtils.fromDateTimeOrNull(updatedAt),
  };
}

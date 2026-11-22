import 'json_utils.dart';

enum VariationOrderType implements JsonEnum {
  additive('additive', 'Added work'),
  deductive('deductive', 'Removed work'),
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
    this.workStartDate,
    this.workEndDate,
    this.primaryAttachments = const [],
    this.secondaryAttachments = const [],
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
  final DateTime? workStartDate;
  final DateTime? workEndDate;

  /// Files or photos attached to the variation order (images, PDFs, CAD, etc.):
  /// - [VariationOrderType.additive]: evidence of what is to be added.
  /// - [VariationOrderType.deductive]: what is to be removed.
  /// - [VariationOrderType.change]: current / existing condition.
  final List<String> primaryAttachments;

  /// Second group of files/photos for [VariationOrderType.change]: the new /
  /// proposed design.
  final List<String> secondaryAttachments;

  final int? approvedByOwner;
  final int? approvedByClient;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get hasAttachments =>
      primaryAttachments.isNotEmpty || secondaryAttachments.isNotEmpty;

  VariationOrder copyWith({
    int? id,
    String? voNo,
    VariationOrderType? type,
    String? description,
    double? amount,
    int? daysImpact,
    VariationOrderStatus? status,
    DateTime? Function()? workStartDate,
    DateTime? Function()? workEndDate,
    List<String>? primaryAttachments,
    List<String>? secondaryAttachments,
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
    workStartDate: workStartDate != null ? workStartDate() : this.workStartDate,
    workEndDate: workEndDate != null ? workEndDate() : this.workEndDate,
    primaryAttachments: primaryAttachments ?? this.primaryAttachments,
    secondaryAttachments: secondaryAttachments ?? this.secondaryAttachments,
    approvedByOwner: approvedByOwner != null
        ? approvedByOwner()
        : this.approvedByOwner,
    approvedByClient: approvedByClient != null
        ? approvedByClient()
        : this.approvedByClient,
    createdAt: createdAt,
    updatedAt: DateTime.now(),
  );

  static List<String> _parseAttachments(Object? listRaw, Object? singleRaw) {
    if (listRaw is List) {
      return listRaw
          .whereType<String>()
          .where((s) => s.trim().isNotEmpty)
          .toList();
    }
    if (singleRaw is String && singleRaw.trim().isNotEmpty) {
      return [singleRaw];
    }
    return const [];
  }

  factory VariationOrder.fromJson(Map<String, dynamic> json) => VariationOrder(
    id: json['id'] as int,
    projectId: json['project_id'] as int,
    voNo: json['vo_no'] as String,
    type: VariationOrderType.fromJson(json['type']),
    description: json['description'] as String,
    amount: JsonUtils.toDouble(json['amount']),
    daysImpact: json['days_impact'] as int,
    status: VariationOrderStatus.fromJson(json['status']),
    workStartDate: JsonUtils.toDateOrNull(json['work_start_date']),
    workEndDate: JsonUtils.toDateOrNull(json['work_end_date']),
    primaryAttachments: _parseAttachments(
      json['primary_attachments'],
      json['primary_photo_url'],
    ),
    secondaryAttachments: _parseAttachments(
      json['secondary_attachments'],
      json['secondary_photo_url'],
    ),
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
    'work_start_date': JsonUtils.fromDateOrNull(workStartDate),
    'work_end_date': JsonUtils.fromDateOrNull(workEndDate),
    if (primaryAttachments.isNotEmpty)
      'primary_attachments': primaryAttachments,
    if (secondaryAttachments.isNotEmpty)
      'secondary_attachments': secondaryAttachments,
    'approved_by_owner': approvedByOwner,
    'approved_by_client': approvedByClient,
    'created_at': JsonUtils.fromDateTimeOrNull(createdAt),
    'updated_at': JsonUtils.fromDateTimeOrNull(updatedAt),
  };
}

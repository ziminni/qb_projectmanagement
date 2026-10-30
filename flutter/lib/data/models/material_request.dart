import 'json_utils.dart';

enum MaterialRequestStatus implements JsonEnum {
  pending('pending', 'Waiting for owner'),
  approved('approved', 'Approved'),
  rejected('rejected', 'Rejected'),
  ordered('ordered', 'Ordered');

  const MaterialRequestStatus(this.apiValue, this.label);

  @override
  final String apiValue;
  final String label;

  static MaterialRequestStatus fromJson(Object? raw) =>
      enumFromApi(values, raw);

  String toJson() => apiValue;
}

/// A row in `material_requests`.
class MaterialRequest {
  const MaterialRequest({
    required this.id,
    required this.projectId,
    required this.categoryId,
    required this.requestedBy,
    required this.neededBy,
    required this.status,
    this.approvedBy,
    this.createdAt,
    this.updatedAt,
  });

  final int id;
  final int projectId;
  final int categoryId;
  final int requestedBy;
  final DateTime neededBy;
  final MaterialRequestStatus status;
  final int? approvedBy;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  String get number => 'MR-${id.toString().padLeft(4, '0')}';

  MaterialRequest copyWith({
    MaterialRequestStatus? status,
    int? Function()? approvedBy,
    DateTime? updatedAt,
  }) => MaterialRequest(
    id: id,
    projectId: projectId,
    categoryId: categoryId,
    requestedBy: requestedBy,
    neededBy: neededBy,
    status: status ?? this.status,
    approvedBy: approvedBy != null ? approvedBy() : this.approvedBy,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  factory MaterialRequest.fromJson(Map<String, dynamic> json) =>
      MaterialRequest(
        id: json['id'] as int,
        projectId: json['project_id'] as int,
        categoryId: json['category_id'] as int,
        requestedBy: json['requested_by'] as int,
        neededBy: JsonUtils.toDate(json['needed_by']),
        status: MaterialRequestStatus.fromJson(json['status']),
        approvedBy: json['approved_by'] as int?,
        createdAt: JsonUtils.toDateOrNull(json['created_at']),
        updatedAt: JsonUtils.toDateOrNull(json['updated_at']),
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'project_id': projectId,
    'category_id': categoryId,
    'requested_by': requestedBy,
    'needed_by': JsonUtils.fromDate(neededBy),
    'status': status.toJson(),
    'approved_by': approvedBy,
    'created_at': JsonUtils.fromDateTimeOrNull(createdAt),
    'updated_at': JsonUtils.fromDateTimeOrNull(updatedAt),
  };
}

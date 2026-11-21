import 'json_utils.dart';

enum ProjectWorkerRequestStatus implements JsonEnum {
  pending('pending', 'Pending PM approval'),
  approved('approved', 'Approved'),
  rejected('rejected', 'Rejected');

  const ProjectWorkerRequestStatus(this.apiValue, this.label);

  @override
  final String apiValue;
  final String label;

  static ProjectWorkerRequestStatus fromJson(Object? raw) =>
      enumFromApi(values, raw);

  String toJson() => apiValue;
}

/// A request submitted by a Foreman to add a laborer to a project, waiting for
/// the Project Manager's approval.
class ProjectWorkerRequest {
  const ProjectWorkerRequest({
    required this.id,
    required this.projectId,
    required this.fullName,
    required this.address,
    required this.phone,
    required this.status,
    required this.requestedById,
    this.requestedByName,
    this.reviewedById,
    this.reviewedByName,
    this.rejectionReason,
    this.workerId,
    this.createdAt,
    this.updatedAt,
  });

  final int id;
  final int projectId;
  final String fullName;
  final String address;
  final String phone;
  final ProjectWorkerRequestStatus status;
  final int requestedById;
  final String? requestedByName;
  final int? reviewedById;
  final String? reviewedByName;
  final String? rejectionReason;
  final int? workerId;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  ProjectWorkerRequest copyWith({
    int? id,
    ProjectWorkerRequestStatus? status,
    int? Function()? reviewedById,
    String? Function()? reviewedByName,
    String? Function()? rejectionReason,
    int? Function()? workerId,
  }) => ProjectWorkerRequest(
    id: id ?? this.id,
    projectId: projectId,
    fullName: fullName,
    address: address,
    phone: phone,
    status: status ?? this.status,
    requestedById: requestedById,
    requestedByName: requestedByName,
    reviewedById: reviewedById != null ? reviewedById() : this.reviewedById,
    reviewedByName:
        reviewedByName != null ? reviewedByName() : this.reviewedByName,
    rejectionReason:
        rejectionReason != null ? rejectionReason() : this.rejectionReason,
    workerId: workerId != null ? workerId() : this.workerId,
    createdAt: createdAt,
    updatedAt: DateTime.now(),
  );

  factory ProjectWorkerRequest.fromJson(Map<String, dynamic> json) =>
      ProjectWorkerRequest(
        id: json['id'] as int,
        projectId: json['project_id'] as int,
        fullName: json['full_name'] as String,
        address: (json['address'] as String?) ?? '',
        phone: (json['phone'] as String?) ?? '',
        status: ProjectWorkerRequestStatus.fromJson(json['status']),
        requestedById: json['requested_by_id'] as int,
        requestedByName: json['requested_by_name'] as String?,
        reviewedById: json['reviewed_by_id'] as int?,
        reviewedByName: json['reviewed_by_name'] as String?,
        rejectionReason: json['rejection_reason'] as String?,
        workerId: json['worker_id'] as int?,
        createdAt: JsonUtils.toDateOrNull(json['created_at']),
        updatedAt: JsonUtils.toDateOrNull(json['updated_at']),
      );
}

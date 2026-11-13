import 'app_role.dart';
import 'json_utils.dart';

/// Where a site engineer's or client's project request stands. The owner's
/// own assignment is always accepted.
enum RequestResponse implements JsonEnum {
  /// Chosen, but held back until the client accepts (site engineers).
  notSent('not_sent', 'Sent after the client accepts'),
  pending('pending', 'Waiting for reply'),
  accepted('accepted', 'Accepted'),

  /// The client asked the owner to revise the project.
  changesRequested('changes_requested', 'Asked for changes'),
  declined('declined', 'Declined');

  const RequestResponse(this.apiValue, this.label);

  @override
  final String apiValue;
  final String label;

  static RequestResponse fromJson(Object? raw) => enumFromApi(values, raw);

  String toJson() => apiValue;
}

/// A row in `project_assignments`. Limits owners, site engineers and clients
/// to their own projects. A site engineer or client joins a project only
/// after accepting its request.
class ProjectAssignment {
  const ProjectAssignment({
    required this.id,
    required this.projectId,
    required this.userId,
    required this.roleOnProject,
    this.response = RequestResponse.accepted,
    this.note,
    this.respondedAt,
    this.createdAt,
    this.updatedAt,
  });

  final int id;
  final int projectId;
  final int userId;
  final AppRole roleOnProject;
  final RequestResponse response;

  /// The reason for declining, or the changes the client asked for.
  final String? note;
  final DateTime? respondedAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isActive => response == RequestResponse.accepted;

  ProjectAssignment copyWith({
    RequestResponse? response,
    String? Function()? note,
    DateTime? Function()? respondedAt,
  }) => ProjectAssignment(
    id: id,
    projectId: projectId,
    userId: userId,
    roleOnProject: roleOnProject,
    response: response ?? this.response,
    note: note != null ? note() : this.note,
    respondedAt: respondedAt != null ? respondedAt() : this.respondedAt,
    createdAt: createdAt,
    updatedAt: DateTime.now(),
  );

  factory ProjectAssignment.fromJson(Map<String, dynamic> json) =>
      ProjectAssignment(
        id: json['id'] as int,
        projectId: json['project_id'] as int,
        userId: json['user_id'] as int,
        roleOnProject: AppRole.fromJson(json['role_on_project']),
        response: json['response'] == null
            ? RequestResponse.accepted
            : RequestResponse.fromJson(json['response']),
        note: json['note'] as String?,
        respondedAt: JsonUtils.toDateOrNull(json['responded_at']),
        createdAt: JsonUtils.toDateOrNull(json['created_at']),
        updatedAt: JsonUtils.toDateOrNull(json['updated_at']),
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'project_id': projectId,
    'user_id': userId,
    'role_on_project': roleOnProject.toJson(),
    'response': response.toJson(),
    'note': note,
    'responded_at': JsonUtils.fromDateTimeOrNull(respondedAt),
    'created_at': JsonUtils.fromDateTimeOrNull(createdAt),
    'updated_at': JsonUtils.fromDateTimeOrNull(updatedAt),
  };
}

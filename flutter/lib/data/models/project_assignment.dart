import 'app_role.dart';
import 'json_utils.dart';

/// A row in `project_assignments`. Limits PMs, site engineers and clients to
/// their own projects.
class ProjectAssignment {
  const ProjectAssignment({
    required this.id,
    required this.projectId,
    required this.userId,
    required this.roleOnProject,
    this.createdAt,
    this.updatedAt,
  });

  final int id;
  final int projectId;
  final int userId;
  final AppRole roleOnProject;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory ProjectAssignment.fromJson(Map<String, dynamic> json) =>
      ProjectAssignment(
        id: json['id'] as int,
        projectId: json['project_id'] as int,
        userId: json['user_id'] as int,
        roleOnProject: AppRole.fromJson(json['role_on_project']),
        createdAt: JsonUtils.toDateOrNull(json['created_at']),
        updatedAt: JsonUtils.toDateOrNull(json['updated_at']),
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'project_id': projectId,
    'user_id': userId,
    'role_on_project': roleOnProject.toJson(),
    'created_at': JsonUtils.fromDateTimeOrNull(createdAt),
    'updated_at': JsonUtils.fromDateTimeOrNull(updatedAt),
  };
}

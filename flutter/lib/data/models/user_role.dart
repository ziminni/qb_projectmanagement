import 'app_role.dart';
import 'json_utils.dart';

/// A row in `user_roles`. A user can hold several roles.
class UserRole {
  const UserRole({
    required this.id,
    required this.userId,
    required this.role,
    this.createdAt,
    this.updatedAt,
  });

  final int id;
  final int userId;
  final AppRole role;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory UserRole.fromJson(Map<String, dynamic> json) => UserRole(
    id: json['id'] as int,
    userId: json['user_id'] as int,
    role: AppRole.fromJson(json['role']),
    createdAt: JsonUtils.toDateOrNull(json['created_at']),
    updatedAt: JsonUtils.toDateOrNull(json['updated_at']),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'user_id': userId,
    'role': role.toJson(),
    'created_at': JsonUtils.fromDateTimeOrNull(createdAt),
    'updated_at': JsonUtils.fromDateTimeOrNull(updatedAt),
  };
}

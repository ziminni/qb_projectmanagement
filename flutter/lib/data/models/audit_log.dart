import 'json_utils.dart';

/// A row in `audit_logs`. Every approval, rejection, verification and status
/// change is written here.
class AuditLog {
  const AuditLog({
    required this.id,
    required this.userId,
    required this.action,
    required this.entity,
    required this.entityId,
    this.details = const {},
    required this.createdAt,
    this.updatedAt,
  });

  final int id;
  final int userId;
  final String action;
  final String entity;
  final int entityId;
  final Map<String, dynamic> details;
  final DateTime createdAt;
  final DateTime? updatedAt;

  factory AuditLog.fromJson(Map<String, dynamic> json) => AuditLog(
    id: json['id'] as int,
    userId: json['user_id'] as int,
    action: json['action'] as String,
    entity: json['entity'] as String,
    entityId: json['entity_id'] as int,
    details: (json['details'] as Map<String, dynamic>?) ?? const {},
    createdAt: JsonUtils.toDate(json['created_at']),
    updatedAt: JsonUtils.toDateOrNull(json['updated_at']),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'user_id': userId,
    'action': action,
    'entity': entity,
    'entity_id': entityId,
    'details': details,
    'created_at': JsonUtils.fromDateTime(createdAt),
    'updated_at': JsonUtils.fromDateTimeOrNull(updatedAt),
  };
}

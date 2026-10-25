import '../models/audit_log.dart';

abstract interface class AuditLogRepository {
  Future<AuditLog> record({
    required int userId,
    required String action,
    required String entity,
    required int entityId,
    Map<String, dynamic> details,
  });

  Future<List<AuditLog>> getFor(String entity, int entityId);
}

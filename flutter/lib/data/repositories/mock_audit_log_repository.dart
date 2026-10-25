import '../models/audit_log.dart';
import 'audit_log_repository.dart';

class MockAuditLogRepository implements AuditLogRepository {
  final _logs = <AuditLog>[];

  @override
  Future<AuditLog> record({
    required int userId,
    required String action,
    required String entity,
    required int entityId,
    Map<String, dynamic> details = const {},
  }) async {
    final log = AuditLog(
      id: _logs.length + 1,
      userId: userId,
      action: action,
      entity: entity,
      entityId: entityId,
      details: details,
      createdAt: DateTime.now(),
    );
    _logs.add(log);
    return log;
  }

  @override
  Future<List<AuditLog>> getFor(String entity, int entityId) async => [
    for (final l in _logs)
      if (l.entity == entity && l.entityId == entityId) l,
  ];
}

import '../models/audit_log.dart';
import 'audit_log_repository.dart';

class MockAuditLogRepository implements AuditLogRepository {
  final _logs = <AuditLog>[
    AuditLog(
      id: 1,
      userId: 3,
      action: 'purchase_order_created',
      entity: 'purchase_order',
      entityId: 5,
      details: const {'request_id': 2, 'total': 53650},
      createdAt: DateTime(2026, 8, 29, 10, 12),
    ),
    AuditLog(
      id: 2,
      userId: 4,
      action: 'delivery_confirmed',
      entity: 'purchase_order',
      entityId: 5,
      details: const {'delivery_id': 5},
      createdAt: DateTime(2026, 10, 18, 11, 4),
    ),
    AuditLog(
      id: 3,
      userId: 6,
      action: 'supplier_payment_recorded',
      entity: 'purchase_order',
      entityId: 3,
      details: const {'amount': 20000},
      createdAt: DateTime(2026, 8, 20, 15, 30),
    ),
    AuditLog(
      id: 4,
      userId: 4,
      action: 'material_request_created',
      entity: 'material_request',
      entityId: 5,
      details: const {'items': 1, 'counted': 0},
      createdAt: DateTime(2026, 10, 23, 11),
    ),
  ];

  @override
  Future<AuditLog> record({
    required int userId,
    required String action,
    required String entity,
    required int entityId,
    Map<String, dynamic> details = const {},
  }) async {
    final log = AuditLog(
      id: _logs.fold(0, (m, l) => l.id > m ? l.id : m) + 1,
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

  @override
  Future<List<AuditLog>> getAll() async =>
      [..._logs]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
}

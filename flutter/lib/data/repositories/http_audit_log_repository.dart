import '../../core/network/api_client.dart';
import '../models/audit_log.dart';
import 'audit_log_repository.dart';

/// Audit rows are written by the server, inside the same transaction as the
/// change (contract: audit rows), so this repository never POSTs one — the
/// desktop cannot forge an entry.
class HttpAuditLogRepository implements AuditLogRepository {
  HttpAuditLogRepository(this._client);

  final ApiClient _client;

  /// Deliberately no request. Returns the row that would have been written so
  /// a caller awaiting a value keeps working; the real row comes back from
  /// [getFor] / [getAll].
  @override
  Future<AuditLog> record({
    required int userId,
    required String action,
    required String entity,
    required int entityId,
    Map<String, dynamic> details = const {},
  }) async => AuditLog(
    id: 0,
    userId: userId,
    action: action,
    entity: entity,
    entityId: entityId,
    details: details,
    createdAt: DateTime.now(),
  );

  @override
  Future<List<AuditLog>> getFor(String entity, int entityId) async => [
    for (final row in await _client.getRows(
      'audit-logs/',
      query: {'entity': entity, 'entity_id': entityId},
    ))
      AuditLog.fromJson(row),
  ];

  @override
  Future<List<AuditLog>> getAll() async => [
    for (final row in await _client.getRows('audit-logs/'))
      AuditLog.fromJson(row),
  ];
}

import '../../../core/di/service_locator.dart';
import '../../../data/repositories/audit_log_repository.dart';
import '../../../data/services/session_service.dart';

/// Writes the admin's own changes (users, settings, company profile, master
/// lists) to the audit log as the signed-in user, so the log covers
/// administration as well as project work.
class AdminAudit {
  AdminAudit({
    required AuditLogRepository auditLog,
    required SessionService session,
  }) : _auditLog = auditLog,
       _session = session;

  /// Uses the app's registered services.
  factory AdminAudit.fromLocator() =>
      AdminAudit(auditLog: getIt(), session: getIt());

  final AuditLogRepository _auditLog;
  final SessionService _session;

  /// Records [action]. Never throws: a logging failure must not undo or
  /// block the change it describes.
  Future<void> record(
    String action, {
    required String entity,
    required int entityId,
    Map<String, dynamic> details = const {},
  }) async {
    final userId = _session.user?.id;
    if (userId == null) return;
    try {
      await _auditLog.record(
        userId: userId,
        action: action,
        entity: entity,
        entityId: entityId,
        details: details,
      );
    } catch (_) {}
  }
}

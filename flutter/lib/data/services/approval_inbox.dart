import '../models/app_role.dart';

/// Kinds of work that wait for someone's approval.
enum ApprovalKind {
  todoVerification('To-do verification'),
  dailyReport('Daily reports'),
  materialRequest('Material requests'),
  payroll('Attendance verification'),
  laborerRequest('Laborer requests'),
  variationOrder('Variation orders');

  const ApprovalKind(this.label);

  final String label;
}

/// One pending item in an approvals inbox.
class ApprovalItem {
  const ApprovalItem({
    required this.kind,
    required this.title,
    required this.subtitle,
    required this.route,
    this.entityId,
    this.entityIds = const [],
    this.projectId,
    this.projectCode,
    this.projectName,
    this.requesterName,
    this.badgeText,
    this.amount,
    this.date,
  });

  final ApprovalKind kind;
  final String title;
  final String subtitle;

  /// Fallback route if opened outside the approvals modal.
  final String route;

  /// Primary record ID (todoId, reportId, requestId, workerRequestId, voId, periodId).
  final int? entityId;

  /// Batch of record IDs when multiple requests are grouped into a single inbox row.
  final List<int> entityIds;

  List<int> get effectiveIds =>
      entityIds.isNotEmpty ? entityIds : [?entityId];

  bool get isBulk => effectiveIds.length > 1;
  final int? projectId;
  final String? projectCode;
  final String? projectName;
  final String? requesterName;
  final String? badgeText;
  final double? amount;
  final DateTime? date;
}

/// A module's contribution to the approvals inbox. Each module that adds an
/// approval step registers a source in the service locator.
abstract interface class ApprovalSource {
  Future<List<ApprovalItem>> pendingFor(int userId, AppRole role);
}

/// Collects pending items from every registered [ApprovalSource].
class ApprovalInbox {
  ApprovalInbox(this._sources);

  final List<ApprovalSource> _sources;

  Future<List<ApprovalItem>> pendingFor(int userId, AppRole role) async {
    final items = <ApprovalItem>[];
    for (final s in _sources) {
      try {
        items.addAll(await s.pendingFor(userId, role));
      } catch (_) {
        // One failing source must never blank out the dashboard or inbox.
      }
    }
    items.sort(
      (a, b) => (a.date ?? DateTime(0)).compareTo(b.date ?? DateTime(0)),
    );
    return items;
  }
}

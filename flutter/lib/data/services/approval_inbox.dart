import '../models/app_role.dart';

/// Kinds of work that wait for someone's approval.
enum ApprovalKind {
  todoVerification('To-do verification'),
  dailyReport('Daily reports'),
  materialRequest('Material requests'),
  payroll('Attendance verification'),
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
    this.amount,
    this.date,
  });

  final ApprovalKind kind;
  final String title;
  final String subtitle;

  /// Where to review and act on the item.
  final String route;
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
    final items = <ApprovalItem>[
      for (final s in _sources) ...await s.pendingFor(userId, role),
    ];
    items.sort(
      (a, b) => (a.date ?? DateTime(0)).compareTo(b.date ?? DateTime(0)),
    );
    return items;
  }
}

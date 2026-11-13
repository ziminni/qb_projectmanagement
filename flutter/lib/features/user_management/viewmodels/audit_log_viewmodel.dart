import 'package:flutter/foundation.dart' show ChangeNotifier;

import '../../../data/models/audit_log.dart';
import '../../../data/repositories/audit_log_repository.dart';
import '../../../data/repositories/user_repository.dart';

/// How far back the audit log looks.
enum AuditPeriod {
  all('All time', null),
  today('Today', 0),
  week('Last 7 days', 7),
  month('Last 30 days', 30);

  const AuditPeriod(this.label, this.days);
  final String label;

  /// Days before today to include; null for everything.
  final int? days;
}

/// The admin's read-only audit log: who did what, and when.
class AuditLogViewModel extends ChangeNotifier {
  AuditLogViewModel({
    required AuditLogRepository auditLog,
    required UserRepository users,
    DateTime Function()? now,
  }) : _auditLog = auditLog,
       _users = users,
       _now = now ?? DateTime.now;

  final AuditLogRepository _auditLog;
  final UserRepository _users;
  final DateTime Function() _now;
  AuditPeriod period = AuditPeriod.all;

  bool _loading = true;
  String? _error;
  List<AuditLog> _all = const [];
  Map<int, String> userNames = const {};
  String query = '';
  int? userFilter;
  String? entityFilter;

  bool get isLoading => _loading;
  String? get error => _error;

  List<String> get entities =>
      {for (final l in _all) l.entity}.toList()..sort();

  bool get hasFilters =>
      query.trim().isNotEmpty ||
      userFilter != null ||
      entityFilter != null ||
      period != AuditPeriod.all;

  DateTime? get _since {
    final days = period.days;
    if (days == null) return null;
    final now = _now();
    return DateTime(now.year, now.month, now.day - days);
  }

  List<AuditLog> get items {
    final q = query.trim().toLowerCase();
    final since = _since;
    return [
      for (final l in _all)
        if ((since == null || !l.createdAt.isBefore(since)) &&
            (userFilter == null || l.userId == userFilter) &&
            (entityFilter == null || l.entity == entityFilter) &&
            (q.isEmpty ||
                actionLabel(l.action).toLowerCase().contains(q) ||
                userName(l.userId).toLowerCase().contains(q) ||
                visibleDetails(
                  l.details,
                ).values.any((v) => '$v'.toLowerCase().contains(q))))
          l,
    ];
  }

  Future<void> load() async {
    try {
      _all = await _auditLog.getAll();
      userNames = {for (final u in await _users.getUsers()) u.id: u.fullName};
    } catch (e) {
      _error = 'Could not load the audit log. $e';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// [items] grouped by calendar day, newest day first.
  List<(DateTime, List<AuditLog>)> get itemsByDay {
    final groups = <(DateTime, List<AuditLog>)>[];
    for (final l in items) {
      final day = DateTime(
        l.createdAt.year,
        l.createdAt.month,
        l.createdAt.day,
      );
      if (groups.isEmpty || groups.last.$1 != day) groups.add((day, []));
      groups.last.$2.add(l);
    }
    return groups;
  }

  void setPeriod(AuditPeriod p) {
    period = p;
    notifyListeners();
  }

  void clearFilters() {
    query = '';
    userFilter = null;
    entityFilter = null;
    period = AuditPeriod.all;
    notifyListeners();
  }

  /// The filtered entries as CSV, for pasting into a spreadsheet.
  String toCsv() {
    String cell(Object? v) {
      final text = '${v ?? ''}';
      return RegExp(r'[",\n]').hasMatch(text)
          ? '"${text.replaceAll('"', '""')}"'
          : text;
    }

    final rows = [
      ['Date', 'Person', 'Action', 'Record', 'Record ID', 'Details'],
      for (final l in items)
        [
          l.createdAt.toIso8601String(),
          userName(l.userId),
          actionLabel(l.action),
          entityLabel(l.entity),
          l.entityId,
          visibleDetails(
            l.details,
          ).entries.map((e) => '${e.key}=${e.value}').join('; '),
        ],
    ];
    return rows.map((r) => r.map(cell).join(',')).join('\n');
  }

  void setQuery(String q) {
    query = q;
    notifyListeners();
  }

  void setUser(int? id) {
    userFilter = id;
    notifyListeners();
  }

  void setEntity(String? e) {
    entityFilter = e;
    notifyListeners();
  }

  String userName(int id) => userNames[id] ?? 'User #$id';

  static final _financialKey = RegExp(
    r'amount|total|cost|price|rate|pay|salary|wage|budget|balance|fee',
  );

  /// [details] without money fields: the admin role sees no company
  /// finances, and the audit log is an admin screen.
  static Map<String, dynamic> visibleDetails(Map<String, dynamic> details) => {
    for (final e in details.entries)
      if (!_financialKey.hasMatch(e.key.toLowerCase())) e.key: e.value,
  };

  /// `material_request_created` → "Material request created".
  static String actionLabel(String action) {
    final words = action.replaceAll('_', ' ');
    return words.isEmpty ? words : words[0].toUpperCase() + words.substring(1);
  }

  static String entityLabel(String entity) => actionLabel(entity);
}

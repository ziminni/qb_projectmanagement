import '../../../../data/models/audit_log.dart';
import '../../../../data/models/user.dart';
import '../../../../data/repositories/audit_log_repository.dart';
import '../../../../data/repositories/user_repository.dart';
import 'admin_tab_viewmodel.dart';

/// The Activity tab: who changed what, and when, from the audit log.
class AdminActivityViewModel extends AdminTabViewModel {
  AdminActivityViewModel({
    required AuditLogRepository auditLog,
    required UserRepository users,
    super.now,
  }) : _auditLog = auditLog,
       _users = users;

  final AuditLogRepository _auditLog;
  final UserRepository _users;

  /// Days shown in the daily chart.
  static const chartDays = 14;

  /// Days the breakdowns cover.
  static const breakdownDays = 30;

  List<AuditLog> _log = const [];
  Map<int, String> _names = const {};

  @override
  String get subject => 'the activity';

  List<AuditLog> _since(int days) {
    final from = today.subtract(Duration(days: days - 1));
    return _log.where((l) => !l.createdAt.isBefore(from)).toList();
  }

  int get todayCount => _since(1).length;
  int get weekCount => _since(7).length;
  int get monthCount => _since(breakdownDays).length;

  /// People who did anything in the last 7 days.
  int get activeUsersThisWeek => {for (final l in _since(7)) l.userId}.length;

  /// Entries per day, oldest first, for the last [chartDays] days.
  List<({DateTime day, int count})> get daily {
    final counts = <DateTime, int>{};
    for (final l in _since(chartDays)) {
      final d = DateTime(l.createdAt.year, l.createdAt.month, l.createdAt.day);
      counts[d] = (counts[d] ?? 0) + 1;
    }
    return [
      for (var i = chartDays - 1; i >= 0; i--)
        (
          day: today.subtract(Duration(days: i)),
          count: counts[today.subtract(Duration(days: i))] ?? 0,
        ),
    ];
  }

  static List<MapEntry<K, int>> _ranked<K>(Iterable<K> keys) {
    final out = <K, int>{};
    for (final k in keys) {
      out[k] = (out[k] ?? 0) + 1;
    }
    return out.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  }

  /// Entries per record type over [breakdownDays] days, most first.
  List<MapEntry<String, int>> get byEntity =>
      _ranked(_since(breakdownDays).map((l) => l.entity));

  /// Entries per person over [breakdownDays] days, most first.
  List<MapEntry<int, int>> get byUser =>
      _ranked(_since(breakdownDays).map((l) => l.userId)).take(6).toList();

  /// Entries per action over [breakdownDays] days, most first.
  List<MapEntry<String, int>> get byAction =>
      _ranked(_since(breakdownDays).map((l) => l.action)).take(8).toList();

  List<AuditLog> get recent => _log.take(12).toList();

  String userName(int id) => _names[id] ?? 'User #$id';

  @override
  Future<void> fetch() async {
    final (log, users) = await (_auditLog.getAll(), _users.getUsers()).wait;
    _log = [...log]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    _names = {for (final User u in users) u.id: u.fullName};
  }
}

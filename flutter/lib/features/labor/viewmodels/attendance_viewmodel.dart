import 'package:flutter/foundation.dart' show ChangeNotifier;

import '../../../core/utils/action_runner.dart';
import '../../../data/models/app_role.dart';
import '../../../data/models/attendance.dart';
import '../../../data/models/project.dart';
import '../../../data/models/worker.dart';
import '../../../data/repositories/labor_repository.dart';
import '../../../data/repositories/project_repository.dart';
import '../../../data/services/labor_rules.dart';
import '../../../data/services/session_service.dart';

class AttendanceRow {
  AttendanceRow(
    this.worker, {
    AttendanceStatus? status,
    double overtimeHours = 0,
  }) : _isPresent =
           status == AttendanceStatus.present ||
           status == AttendanceStatus.halfDay,
       _isAbsent = status == AttendanceStatus.absent,
       hoursWorked = switch (status) {
         AttendanceStatus.present => 8 + overtimeHours,
         AttendanceStatus.halfDay => 4,
         AttendanceStatus.absent || null => 0,
       };

  final Worker worker;

  bool _isPresent;
  bool _isAbsent;

  /// Total hours worked when marked Present (e.g. 8 for a full shift, 4 for
  /// half shift, 10 for 8h regular + 2h overtime).
  double hoursWorked;

  /// UI status: only Present, Absent, or unmarked (null).
  AttendanceStatus? get uiStatus {
    if (_isPresent) return AttendanceStatus.present;
    if (_isAbsent) return AttendanceStatus.absent;
    return null;
  }

  /// Storage status mapped for the backend & payroll calculator:
  /// - Present with <= 4 hrs -> halfDay (0.5 day)
  /// - Present with > 4 hrs  -> present (1.0 day, with overtime = max(0, hrs - 8))
  /// - Absent                -> absent
  AttendanceStatus? get status {
    if (_isAbsent) return AttendanceStatus.absent;
    if (_isPresent) {
      return hoursWorked > 0 && hoursWorked <= 4
          ? AttendanceStatus.halfDay
          : AttendanceStatus.present;
    }
    return null;
  }

  double get overtimeHours {
    if (!_isPresent) return 0;
    return hoursWorked > 8 ? hoursWorked - 8 : 0;
  }

  void setStatus(AttendanceStatus? next) {
    if (next == AttendanceStatus.present || next == AttendanceStatus.halfDay) {
      _isPresent = true;
      _isAbsent = false;
      if (hoursWorked <= 0) {
        hoursWorked = next == AttendanceStatus.halfDay ? 4 : 8;
      }
    } else if (next == AttendanceStatus.absent) {
      _isPresent = false;
      _isAbsent = true;
      hoursWorked = 0;
    } else {
      _isPresent = false;
      _isAbsent = false;
      hoursWorked = 0;
    }
  }
}

/// The site engineer's daily attendance sheet for one site.
class AttendanceViewModel extends ChangeNotifier with ActionRunner {
  AttendanceViewModel({
    this.initialProjectId,
    required SessionService session,
    required ProjectRepository projects,
    required LaborRepository labor,
  }) : _session = session,
       _projects = projects,
       _labor = labor;

  final int? initialProjectId;
  final SessionService _session;
  final ProjectRepository _projects;
  final LaborRepository _labor;

  bool _loading = true;
  String? _error;
  List<Project> _projectOptions = const [];
  List<AttendanceRow> rows = const [];
  String? _lockedReason;

  int? projectId;
  DateTime date = DateTime.now();

  bool get isLoading => _loading;
  String? get error => _error;
  List<Project> get projectOptions => _projectOptions;

  /// Set when the day falls in a processed payroll period.
  String? get lockedReason => _lockedReason;

  int get marked => rows.where((r) => r.status != null).length;
  double get presentDays =>
      rows.fold(0, (s, r) => s + (r.status?.dayFraction ?? 0));
  double get totalHours => rows.fold(0, (s, r) => s + r.hoursWorked);

  Future<void> load() async {
    try {
      if (_session.activeRole != AppRole.siteEngineer) {
        _error = 'Attendance is recorded by the site engineer.';
        return;
      }
      _projectOptions = (await _projects.getProjectsFor(
        _session.user!.id,
        AppRole.siteEngineer,
      )).where((p) => p.status == ProjectStatus.ongoing).toList();
      if (_projectOptions.isEmpty) {
        _error = 'You have no ongoing site.';
        return;
      }
      projectId = _projectOptions.any((p) => p.id == initialProjectId)
          ? initialProjectId
          : _projectOptions.first.id;
      await _refresh();
    } catch (e) {
      _error = 'Could not load attendance. $e';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> _refresh() async {
    final workers = await _labor.getWorkers(activeOnly: true);
    final existing = {
      for (final a in await _labor.getAttendance(
        projectId: projectId!,
        from: date,
        to: date,
      ))
        a.workerId: a,
    };
    rows = [
      for (final w in workers)
        AttendanceRow(
          w,
          status: existing[w.id]?.status,
          overtimeHours: existing[w.id]?.overtimeHours ?? 0,
        ),
    ];
    // No payroll routes yet: there is no processed period to lock a day to.
    if (!_labor.supportsPayroll) {
      _lockedReason = null;
      notifyListeners();
      return;
    }
    final periods = await _labor.getPeriods(projectIds: [projectId!]);
    final period = periods.where((p) => p.contains(date)).firstOrNull;
    _lockedReason = LaborRules.canEditAttendance(period);
    notifyListeners();
  }

  Future<void> setProject(int? id) async {
    projectId = id;
    await _refresh();
  }

  Future<void> setDate(DateTime d) async {
    date = d;
    await _refresh();
  }

  void markAll(AttendanceStatus status) {
    for (final r in rows) {
      r.setStatus(status);
    }
    notifyListeners();
  }

  /// Unmarks everyone, e.g. after a mistaken "Mark all present".
  void clearAll() {
    for (final r in rows) {
      r.setStatus(null);
    }
    notifyListeners();
  }

  void changed() => notifyListeners();

  Future<String?> save() => runAction(() async {
    await _labor.saveAttendance(projectId!, date, [
      for (final r in rows)
        if (r.status != null)
          (
            workerId: r.worker.id,
            status: r.status!,
            overtimeHours: r.overtimeHours,
          ),
    ], userId: _session.user!.id);
    await _refresh();
  });
}

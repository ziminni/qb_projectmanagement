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
  AttendanceRow(this.worker, {this.status, this.overtimeHours = 0});

  final Worker worker;

  /// Null until the site engineer marks the worker.
  AttendanceStatus? status;
  double overtimeHours;
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
      r.status = status;
    }
    notifyListeners();
  }

  /// Unmarks everyone, e.g. after a mistaken "Mark all present".
  void clearAll() {
    for (final r in rows) {
      r.status = null;
      r.overtimeHours = 0;
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

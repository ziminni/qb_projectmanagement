import 'package:flutter/foundation.dart' show ChangeNotifier;

import '../../../data/models/attendance.dart';
import '../../../data/models/payroll_period.dart';
import '../../../data/models/worker.dart';
import '../../../data/repositories/labor_repository.dart';

class DayHeadcount {
  const DayHeadcount(this.date, this.present, this.halfDay, this.absent);

  final DateTime date;
  final int present;
  final int halfDay;
  final int absent;
}

/// Project "Labor" tab: workers on site, recent attendance, payroll, cost.
class ProjectLaborViewModel extends ChangeNotifier {
  ProjectLaborViewModel({
    required this.projectId,
    required LaborRepository labor,
  }) : _labor = labor;

  final int projectId;
  final LaborRepository _labor;

  bool _loading = true;
  List<Worker> workers = const [];
  List<DayHeadcount> recentDays = const [];
  List<PayrollPeriod> periods = const [];
  double laborCost = 0;

  bool get isLoading => _loading;

  Future<void> load() async {
    final attendance = await _labor.getAttendance(projectId: projectId);
    final workerIds = attendance.map((a) => a.workerId).toSet();
    workers = (await _labor.getWorkers())
        .where((w) => workerIds.contains(w.id))
        .toList();
    final byDate = <DateTime, List<Attendance>>{};
    for (final a in attendance) {
      byDate.putIfAbsent(a.workDate, () => []).add(a);
    }
    final dates = byDate.keys.toList()..sort((a, b) => b.compareTo(a));
    recentDays = [
      for (final d in dates.take(7))
        DayHeadcount(
          d,
          byDate[d]!.where((a) => a.status == AttendanceStatus.present).length,
          byDate[d]!.where((a) => a.status == AttendanceStatus.halfDay).length,
          byDate[d]!.where((a) => a.status == AttendanceStatus.absent).length,
        ),
    ];
    periods = await _labor.getPeriods(projectIds: [projectId]);
    laborCost = await _labor.laborCost(projectId);
    _loading = false;
    notifyListeners();
  }
}

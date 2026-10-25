import '../models/attendance.dart';
import '../models/payroll_line.dart';
import '../models/payroll_period.dart';
import '../models/worker.dart';

/// One worker's attendance entry when saving a day's sheet.
typedef AttendanceEntry = ({
  int workerId,
  AttendanceStatus status,
  double overtimeHours,
});

abstract interface class LaborRepository {
  Future<List<Worker>> getWorkers({bool activeOnly = false});

  /// Creates the worker when its id is 0.
  Future<Worker> saveWorker(Worker worker);

  Future<List<Attendance>> getAttendance({
    required int projectId,
    DateTime? from,
    DateTime? to,
  });

  /// Saves a day's attendance sheet, replacing the day's entries for the
  /// listed workers.
  Future<void> saveAttendance(
    int projectId,
    DateTime date,
    List<AttendanceEntry> entries, {
    required int userId,
  });

  Future<List<PayrollPeriod>> getPeriods({List<int>? projectIds});

  Future<PayrollPeriod?> getPeriod(int id);

  Future<PayrollPeriod> createPeriod(
    int projectId,
    DateTime start,
    DateTime end, {
    required int userId,
  });

  /// PM verification at cut-off.
  Future<PayrollPeriod> verifyPeriod(int id, {required int userId});

  /// Stored lines once processed; otherwise computed from attendance.
  Future<List<PayrollLine>> getLines(int periodId);

  Future<void> setCashAdvance(
    int periodId,
    int workerId,
    double amount, {
    required int userId,
  });

  /// Accountant computes and locks the period's pay.
  Future<PayrollPeriod> processPeriod(int id, {required int userId});

  /// Gross pay of processed periods, posted to the project's actual cost.
  Future<double> laborCost(int projectId);
}

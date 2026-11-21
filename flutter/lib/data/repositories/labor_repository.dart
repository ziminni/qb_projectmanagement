import '../models/attendance.dart';
import '../models/payroll_line.dart';
import '../models/payroll_period.dart';
import '../models/project_worker_request.dart';
import '../models/worker.dart';

/// One worker's attendance entry when saving a day's sheet.
typedef AttendanceEntry = ({
  int workerId,
  AttendanceStatus status,
  double overtimeHours,
});

abstract interface class LaborRepository {
  /// Payroll periods, processing, advances and labor cost are not built yet on
  /// the CPMS backend (phase-4 contract, slice A): the HTTP repository refuses
  /// them, and the screens leave them out instead of showing a fake figure.
  bool get supportsPayroll;

  Future<List<Worker>> getWorkers({bool activeOnly = false});

  /// Creates the worker when its id is 0.
  Future<Worker> saveWorker(Worker worker);

  /// Records a cash advance (vale) on a worker's running balance so it
  /// auto-deducts across upcoming paydays until paid off.
  Future<Worker> addWorkerCashAdvance(int workerId, double amount);

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

  /// Foreman requests to add laborers to a project, reviewed by the PM.
  Future<List<ProjectWorkerRequest>> getWorkerRequests({
    int? projectId,
    List<int>? projectIds,
    ProjectWorkerRequestStatus? status,
  });

  Future<ProjectWorkerRequest> requestProjectWorker({
    required int projectId,
    int? workerId,
    String fullName = '',
    String address = '',
    String phone = '',
    required int userId,
  });

  Future<ProjectWorkerRequest> approveWorkerRequest(
    int id, {
    required int userId,
  });

  Future<ProjectWorkerRequest> rejectWorkerRequest(
    int id, {
    required int userId,
    required String reason,
  });
}

import '../../core/network/api_client.dart';
import '../models/attendance.dart';
import '../models/json_utils.dart';
import '../models/payroll_line.dart';
import '../models/payroll_period.dart';
import '../models/worker.dart';
import 'labor_repository.dart';

/// Workers and attendance against the CPMS backend (Phase 4, slice A).
///
/// Scope, role and redaction are the server's: the active role (sent as
/// `X-Active-Role`) decides which projects and rows come back and whether a
/// worker row carries a wage at all, so the `userId`s in the interface are
/// never sent as a claim. Refusals arrive as the server's own `detail` text
/// and surface as `BusinessRuleException` unchanged.
///
/// Payroll has no endpoints yet (phase-4 contract, slice A), so every payroll
/// method refuses: an invented period, advance or labor cost would be a figure
/// nobody computed.
class HttpLaborRepository implements LaborRepository {
  HttpLaborRepository(this._client);

  final ApiClient _client;

  @override
  bool get supportsPayroll => false;

  // ---- Workers

  @override
  Future<List<Worker>> getWorkers({bool activeOnly = false}) async => [
    for (final row in await _client.getRows(
      'workers/',
      query: {if (activeOnly) 'active_only': 'true'},
    ))
      _worker(row),
  ];

  /// Creates the worker when its id is 0, updates it by `PATCH` otherwise.
  @override
  Future<Worker> saveWorker(Worker worker) async {
    final hidesMoney = worker.dailyRateHidden;
    final body = {
      'full_name': worker.fullName.trim(),
      'trade': worker.trade.trim(),
      'is_active': worker.isActive,
      // A redacted role never received a rate: sending 0 would invent a wage.
      if (!hidesMoney) 'daily_rate': worker.dailyRate,
      if (!hidesMoney) 'sss_no': worker.sssNo,
      if (!hidesMoney) 'philhealth_no': worker.philhealthNo,
      if (!hidesMoney) 'pagibig_no': worker.pagibigNo,
    };
    final data = worker.id == 0
        ? await _client.post('workers/', body: body)
        : await _client.patch('workers/${worker.id}/', body: body);
    return _worker(jsonObject(data));
  }

  // ---- Attendance

  @override
  Future<List<Attendance>> getAttendance({
    required int projectId,
    DateTime? from,
    DateTime? to,
  }) async => [
    for (final row in await _client.getRows(
      'attendance/',
      query: {
        'project': '$projectId',
        if (from != null) 'from': JsonUtils.fromDate(from),
        if (to != null) 'to': JsonUtils.fromDate(to),
      },
    ))
      Attendance.fromJson(row),
  ];

  /// One atomic sheet: the server replaces the listed workers' rows only and
  /// refuses the whole save if any entry breaks a rule.
  @override
  Future<void> saveAttendance(
    int projectId,
    DateTime date,
    List<AttendanceEntry> entries, {
    required int userId,
  }) async {
    await _client.post(
      'attendance/save-day/',
      body: {
        'project_id': projectId,
        'work_date': JsonUtils.fromDate(date),
        'entries': [
          for (final e in entries)
            {
              'worker_id': e.workerId,
              'status': e.status.apiValue,
              'overtime_hours': e.overtimeHours,
            },
        ],
      },
    );
  }

  // ---- Payroll (no routes yet: phase-4 contract, slice A)

  @override
  Future<List<PayrollPeriod>> getPeriods({List<int>? projectIds}) async =>
      throw UnsupportedError(_noPayroll);

  @override
  Future<PayrollPeriod?> getPeriod(int id) async => throw UnsupportedError(
    _noPayroll,
  );

  @override
  Future<PayrollPeriod> createPeriod(
    int projectId,
    DateTime start,
    DateTime end, {
    required int userId,
  }) async => throw UnsupportedError(_noPayroll);

  @override
  Future<PayrollPeriod> verifyPeriod(int id, {required int userId}) async =>
      throw UnsupportedError(_noPayroll);

  @override
  Future<List<PayrollLine>> getLines(int periodId) async =>
      throw UnsupportedError(_noPayroll);

  @override
  Future<void> setCashAdvance(
    int periodId,
    int workerId,
    double amount, {
    required int userId,
  }) async => throw UnsupportedError(_noPayroll);

  @override
  Future<PayrollPeriod> processPeriod(int id, {required int userId}) async =>
      throw UnsupportedError(_noPayroll);

  @override
  Future<double> laborCost(int projectId) async => throw UnsupportedError(
    'Labor cost needs processed payroll, which the CPMS backend does not have '
    'yet (phase-4 contract, slice A).',
  );

  static const String _noPayroll =
      'Payroll periods are not available yet: the CPMS backend has workers and '
      'attendance only so far (phase-4 contract, slice A).';

  /// A worker row, told whether this role is sent the money keys: an omitted
  /// `daily_rate` is a hidden wage for a redacted role and a broken response
  /// for a finance one, never a zero.
  Worker _worker(Map<String, dynamic> row) =>
      Worker.fromJson(row, rateHidden: !_client.seesFinance);
}

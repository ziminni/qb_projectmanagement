import '../../core/network/api_client.dart';
import '../models/attendance.dart';
import '../models/json_utils.dart';
import '../models/payroll_line.dart';
import '../models/payroll_period.dart';
import '../models/worker.dart';
import 'labor_repository.dart';

/// Workers and attendance against the CPMS backend (Phase 4, slice A), and
/// payroll periods against the slice C routes.
///
/// Scope, role and redaction are the server's: the active role (sent as
/// `X-Active-Role`) decides which projects and rows come back and whether a
/// worker row carries a wage at all, so the `userId`s in the interface are
/// never sent as a claim. Refusals arrive as the server's own `detail` text
/// and surface as `BusinessRuleException` unchanged.
///
/// Payroll money is computed by the server: every amount on a line (`gross_pay`,
/// `cash_advance`, `statutory_deductions`, `net_pay`) is read as sent and never
/// recalculated here, which is why `payroll_calculator.dart` stays mock-only.
/// The statutory total is `0.00` with `deductions_policy: 'unconfigured'` until
/// a contribution table exists, and that flag reaches the screens.
class HttpLaborRepository implements LaborRepository {
  HttpLaborRepository(this._client);

  final ApiClient _client;

  @override
  bool get supportsPayroll => true;

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

  // ---- Payroll

  @override
  Future<List<PayrollPeriod>> getPeriods({List<int>? projectIds}) async {
    final rows = await _client.getRows(
      'payroll-periods/',
      // The route filters one project; a longer list is filtered here.
      query: {
        if (projectIds != null && projectIds.length == 1)
          'project': '${projectIds.single}',
      },
    );
    return [
      for (final row in rows)
        if (PayrollPeriod.fromJson(row) case final period
            when projectIds == null || projectIds.contains(period.projectId))
          period,
    ];
  }

  @override
  Future<PayrollPeriod?> getPeriod(int id) async {
    final data = await _client.get(
      'payroll-periods/$id/',
      notFoundAsNull: true,
    );
    return data == null ? null : PayrollPeriod.fromJson(jsonObject(data));
  }

  /// The period is created open: its status is the server's to move.
  @override
  Future<PayrollPeriod> createPeriod(
    int projectId,
    DateTime start,
    DateTime end, {
    required int userId,
  }) async => PayrollPeriod.fromJson(
    jsonObject(
      await _client.post(
        'payroll-periods/',
        body: {
          'project_id': projectId,
          'period_start': JsonUtils.fromDate(start),
          'period_end': JsonUtils.fromDate(end),
        },
      ),
    ),
  );

  @override
  Future<PayrollPeriod> verifyPeriod(int id, {required int userId}) async =>
      _move(id, 'verify');

  @override
  Future<List<PayrollLine>> getLines(int periodId) async => [
    for (final row in await _client.getRows(
      'payroll-periods/$periodId/lines/',
    ))
      PayrollLine.fromJson(row),
  ];

  /// The route answers with the affected line, which the screens re-read from
  /// `lines/`; nothing is computed from it here.
  @override
  Future<void> setCashAdvance(
    int periodId,
    int workerId,
    double amount, {
    required int userId,
  }) async {
    await _client.post(
      'payroll-periods/$periodId/cash-advance/',
      body: {'worker_id': workerId, 'amount': amount},
    );
  }

  @override
  Future<PayrollPeriod> processPeriod(int id, {required int userId}) async =>
      _move(id, 'process');

  /// Finance-only on the server, so an omitted figure is a broken response and
  /// a refused role is an error — neither reads as a zero cost.
  @override
  Future<double> laborCost(int projectId) async {
    final data = jsonObject(
      await _client.get('labor-cost/', query: {'project': '$projectId'}),
    );
    return JsonUtils.toFinanceDouble(
      data['labor_cost'],
      omitted: !_client.seesFinance,
    );
  }

  /// A period move: each transition is its own audited server transaction.
  Future<PayrollPeriod> _move(int id, String move) async =>
      PayrollPeriod.fromJson(
        jsonObject(await _client.post('payroll-periods/$id/$move/')),
      );

  /// A worker row, told whether this role is sent the money keys: an omitted
  /// `daily_rate` is a hidden wage for a redacted role and a broken response
  /// for a finance one, never a zero.
  Worker _worker(Map<String, dynamic> row) =>
      Worker.fromJson(row, rateHidden: !_client.seesFinance);
}

import '../../core/layout/project_tabs.dart';
import '../../routes/routes.dart';
import '../models/app_role.dart';
import '../models/attendance.dart';
import '../models/payroll_line.dart';
import '../models/payroll_period.dart';
import '../models/project_worker_request.dart';
import '../models/worker.dart';
import '../services/business_rule_exception.dart';
import '../services/labor_rules.dart';
import '../services/notification_service.dart';
import '../services/payroll_calculator.dart';
import 'audit_log_repository.dart';
import 'labor_repository.dart';
import 'mock_labor_data.dart';
import 'project_repository.dart';
import 'user_repository.dart';

class MockLaborRepository implements LaborRepository {
  MockLaborRepository({
    required ProjectRepository projects,
    required UserRepository users,
    required AuditLogRepository auditLog,
    NotificationService? notifications,
    DateTime Function()? clock,
  }) : _projects = projects,
       _users = users,
       _auditLog = auditLog,
       _notifications = notifications,
       _clock = clock ?? DateTime.now {
    // Period 1 was processed before the app's data starts.
    _lines.addAll(_compute(_periods.first));
  }

  final ProjectRepository _projects;
  final UserRepository _users;
  final AuditLogRepository _auditLog;
  final NotificationService? _notifications;
  final DateTime Function() _clock;

  @override
  bool get supportsPayroll => true;

  final _workers = [...MockLaborData.workers];
  final _attendance = MockLaborData.attendance();
  final _periods = [...MockLaborData.periods];
  final _lines = <PayrollLine>[];
  final _workerRequests = <ProjectWorkerRequest>[];

  /// Cash advances entered before processing: (period, worker) → amount.
  final _cashAdvances = <(int, int), double>{};

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  static int _next(Iterable<int> ids) =>
      ids.fold(0, (m, id) => id > m ? id : m) + 1;

  @override
  Future<List<Worker>> getWorkers({bool activeOnly = false}) async =>
      _workers.where((w) => !activeOnly || w.isActive).toList()
        ..sort((a, b) => a.fullName.compareTo(b.fullName));

  @override
  Future<Worker> saveWorker(Worker worker) async {
    if (worker.fullName.trim().isEmpty) {
      throw const BusinessRuleException('Enter the worker\'s name.');
    }
    if (worker.trade.trim().isEmpty) {
      throw const BusinessRuleException('Choose the worker\'s trade.');
    }
    LaborRules.enforce(LaborRules.validateDailyRate(worker.dailyRate));
    final saved = worker.copyWith(
      id: worker.id == 0 ? _next(_workers.map((w) => w.id)) : null,
      fullName: worker.fullName.trim(),
    );
    final i = _workers.indexWhere((w) => w.id == saved.id);
    if (i < 0) {
      _workers.add(saved);
    } else {
      _workers[i] = saved;
    }
    return saved;
  }

  @override
  Future<List<Attendance>> getAttendance({
    required int projectId,
    DateTime? from,
    DateTime? to,
  }) async => _attendance
      .where(
        (a) =>
            a.projectId == projectId &&
            (from == null || !a.workDate.isBefore(_day(from))) &&
            (to == null || !a.workDate.isAfter(_day(to))),
      )
      .toList();

  PayrollPeriod? _periodFor(int projectId, DateTime date) {
    for (final p in _periods) {
      if (p.projectId == projectId && p.contains(date)) return p;
    }
    return null;
  }

  @override
  Future<void> saveAttendance(
    int projectId,
    DateTime date,
    List<AttendanceEntry> entries, {
    required int userId,
  }) async {
    if (!await _projects.isAssigned(projectId, userId, AppRole.siteEngineer)) {
      throw const BusinessRuleException(
        'Only the site engineer on this project records its attendance.',
      );
    }
    final day = _day(date);
    LaborRules.enforce(LaborRules.validateWorkDate(day, _clock()));
    LaborRules.enforce(
      LaborRules.canEditAttendance(_periodFor(projectId, day)),
    );
    for (final e in entries) {
      LaborRules.enforce(LaborRules.validateOvertime(e.overtimeHours));
      if (e.status != AttendanceStatus.absent &&
          _attendance.any(
            (a) =>
                a.workerId == e.workerId &&
                a.workDate == day &&
                a.projectId != projectId &&
                a.status != AttendanceStatus.absent,
          )) {
        final name = _workers.firstWhere((w) => w.id == e.workerId).fullName;
        throw BusinessRuleException(
          '$name is already marked present on another project that day.',
        );
      }
    }
    final ids = entries.map((e) => e.workerId).toSet();
    _attendance.removeWhere(
      (a) =>
          a.projectId == projectId &&
          a.workDate == day &&
          ids.contains(a.workerId),
    );
    var next = _next(_attendance.map((a) => a.id));
    for (final e in entries) {
      _attendance.add(
        Attendance(
          id: next++,
          projectId: projectId,
          workerId: e.workerId,
          workDate: day,
          status: e.status,
          overtimeHours: e.status == AttendanceStatus.absent
              ? 0
              : e.overtimeHours,
          recordedBy: userId,
          createdAt: _clock(),
        ),
      );
    }
  }

  @override
  Future<List<PayrollPeriod>> getPeriods({List<int>? projectIds}) async =>
      _periods
          .where((p) => projectIds == null || projectIds.contains(p.projectId))
          .toList()
        ..sort((a, b) => b.periodStart.compareTo(a.periodStart));

  @override
  Future<PayrollPeriod?> getPeriod(int id) async {
    for (final p in _periods) {
      if (p.id == id) return p;
    }
    return null;
  }

  @override
  Future<PayrollPeriod> createPeriod(
    int projectId,
    DateTime start,
    DateTime end, {
    required int userId,
  }) async {
    LaborRules.enforce(LaborRules.validatePeriod(start, end));
    final s = _day(start);
    final e = _day(end);
    if (_periods.any(
      (p) =>
          p.projectId == projectId &&
          !e.isBefore(p.periodStart) &&
          !s.isAfter(p.periodEnd),
    )) {
      throw const BusinessRuleException(
        'This overlaps an existing payroll period for the project.',
      );
    }
    final period = PayrollPeriod(
      id: _next(_periods.map((p) => p.id)),
      projectId: projectId,
      periodStart: s,
      periodEnd: e,
      status: PayrollStatus.open,
      createdAt: _clock(),
    );
    _periods.add(period);
    return period;
  }

  @override
  Future<PayrollPeriod> verifyPeriod(int id, {required int userId}) async {
    final i = _indexOf(id);
    final p = _periods[i];
    LaborRules.enforce(LaborRules.canVerify(p, _clock()));
    if (!await _projects.isAssigned(p.projectId, userId, AppRole.owner)) {
      throw const BusinessRuleException(
        'Only the owner of this project verifies its attendance.',
      );
    }
    final updated = p.copyWith(status: PayrollStatus.verified);
    _periods[i] = updated;
    await _auditLog.record(
      userId: userId,
      action: 'attendance_verified',
      entity: 'payroll_period',
      entityId: id,
    );
    final accountants = await _users.getUsersWithRole(AppRole.accountant);
    await _notifications?.notify(
      accountants.map((u) => u.id),
      type: 'payroll',
      message: 'Attendance verified; payroll period is ready to process.',
      link: AppRoutes.payrollPeriod(id),
    );
    return updated;
  }

  @override
  Future<Worker> addWorkerCashAdvance(int workerId, double amount) async {
    if (amount <= 0) {
      throw const BusinessRuleException(
        'Cash advance amount must be greater than zero.',
      );
    }
    final i = _workers.indexWhere((w) => w.id == workerId);
    if (i < 0) {
      throw const BusinessRuleException('Worker not found.');
    }
    final updated = _workers[i].copyWith(
      cashAdvanceBalance: _workers[i].cashAdvanceBalance + amount,
    );
    _workers[i] = updated;
    return updated;
  }

  List<PayrollLine> _compute(PayrollPeriod p) {
    final rows = _attendance.where(
      (a) => a.projectId == p.projectId && p.contains(a.workDate),
    );
    final byWorker = <int, List<Attendance>>{};
    for (final a in rows) {
      byWorker.putIfAbsent(a.workerId, () => []).add(a);
    }
    var next = _next(_lines.map((l) => l.id));
    final result = <PayrollLine>[];
    for (final e in byWorker.entries) {
      final worker = _workers.firstWhere((w) => w.id == e.key);
      final key = (p.id, e.key);
      double advance;
      if (_cashAdvances.containsKey(key)) {
        advance = _cashAdvances[key]!;
      } else if (worker.cashAdvanceBalance > 0) {
        final base = computePayrollLine(
          payrollPeriodId: p.id,
          worker: worker,
          attendance: e.value,
          cashAdvance: 0,
        );
        advance = worker.cashAdvanceBalance < base.grossPay
            ? worker.cashAdvanceBalance
            : base.grossPay;
      } else {
        advance = 0;
      }
      result.add(
        computePayrollLine(
          id: next++,
          payrollPeriodId: p.id,
          worker: worker,
          attendance: e.value,
          cashAdvance: advance,
        ),
      );
    }
    return result..sort((a, b) => a.workerId.compareTo(b.workerId));
  }

  @override
  Future<List<PayrollLine>> getLines(int periodId) async {
    final p = (await getPeriod(periodId))!;
    if (p.status == PayrollStatus.processed) {
      return _lines.where((l) => l.payrollPeriodId == periodId).toList();
    }
    return _compute(p);
  }

  @override
  Future<void> setCashAdvance(
    int periodId,
    int workerId,
    double amount, {
    required int userId,
  }) async {
    final p = (await getPeriod(periodId))!;
    if (p.status == PayrollStatus.processed) {
      throw const BusinessRuleException('This period is already processed.');
    }
    final line = (await getLines(periodId)).firstWhere(
      (l) => l.workerId == workerId,
      orElse: () => throw const BusinessRuleException(
        'This worker has no attendance in the period.',
      ),
    );
    LaborRules.enforce(LaborRules.validateCashAdvance(amount, line.grossPay));
    _cashAdvances[(periodId, workerId)] = amount;
  }

  @override
  Future<PayrollPeriod> processPeriod(int id, {required int userId}) async {
    final i = _indexOf(id);
    final p = _periods[i];
    LaborRules.enforce(LaborRules.canProcess(p));
    final computed = _compute(p);
    _lines
      ..removeWhere((l) => l.payrollPeriodId == id)
      ..addAll(computed);
    for (final line in computed) {
      if (line.cashAdvance > 0) {
        final wi = _workers.indexWhere((w) => w.id == line.workerId);
        if (wi >= 0 && _workers[wi].cashAdvanceBalance > 0) {
          final remaining = _workers[wi].cashAdvanceBalance - line.cashAdvance;
          _workers[wi] = _workers[wi].copyWith(
            cashAdvanceBalance: remaining > 0 ? remaining : 0,
          );
        }
      }
    }
    final updated = p.copyWith(status: PayrollStatus.processed);
    _periods[i] = updated;
    await _auditLog.record(
      userId: userId,
      action: 'payroll_processed',
      entity: 'payroll_period',
      entityId: id,
    );
    return updated;
  }

  @override
  Future<double> laborCost(int projectId) async {
    final processed = {
      for (final p in _periods)
        if (p.projectId == projectId && p.status == PayrollStatus.processed)
          p.id,
    };
    return _lines
        .where((l) => processed.contains(l.payrollPeriodId))
        .fold<double>(0, (s, l) => s + l.grossPay);
  }

  @override
  Future<List<ProjectWorkerRequest>> getWorkerRequests({
    int? projectId,
    List<int>? projectIds,
    ProjectWorkerRequestStatus? status,
  }) async => _workerRequests
      .where(
        (r) =>
            (projectId == null || r.projectId == projectId) &&
            (projectIds == null || projectIds.contains(r.projectId)) &&
            (status == null || r.status == status),
      )
      .toList();

  @override
  Future<ProjectWorkerRequest> requestProjectWorker({
    required int projectId,
    int? workerId,
    String fullName = '',
    String address = '',
    String phone = '',
    required int userId,
  }) async {
    Worker? existing;
    if (workerId != null) {
      existing = _workers.where((w) => w.id == workerId).firstOrNull;
      if (existing == null) {
        throw const BusinessRuleException('Selected worker was not found.');
      }
    }
    final name = existing?.fullName ?? fullName.trim();
    if (name.isEmpty) {
      throw const BusinessRuleException('Enter the laborer\'s full name.');
    }
    final requester = await _users.getUser(userId);
    final req = ProjectWorkerRequest(
      id: _next(_workerRequests.map((r) => r.id)),
      projectId: projectId,
      fullName: name,
      address: existing?.address ?? address.trim(),
      phone: existing?.phone ?? phone.trim(),
      status: ProjectWorkerRequestStatus.pending,
      requestedById: userId,
      requestedByName: requester?.fullName,
      workerId: existing?.id,
      createdAt: _clock(),
      updatedAt: _clock(),
    );
    _workerRequests.insert(0, req);
    await _notifications?.notifyProjectRole(
      projectId,
      AppRole.owner,
      type: 'laborer_request',
      message: 'New laborer request: ${req.fullName}.',
      link: AppRoutes.projectTab(projectId, ProjectTab.laborers),
    );
    return req;
  }

  @override
  Future<ProjectWorkerRequest> approveWorkerRequest(
    int id, {
    required int userId,
  }) async {
    final idx = _workerRequests.indexWhere((r) => r.id == id);
    if (idx < 0) {
      throw const BusinessRuleException('Laborer request not found.');
    }
    final req = _workerRequests[idx];
    if (req.status != ProjectWorkerRequestStatus.pending) {
      throw const BusinessRuleException(
        'This laborer request has already been reviewed.',
      );
    }
    final reviewer = await _users.getUser(userId);
    final workerId =
        req.workerId ??
        (await saveWorker(
          Worker(
            id: 0,
            fullName: req.fullName,
            address: req.address,
            phone: req.phone,
            trade: 'Laborer',
            dailyRate: 500,
            isActive: true,
          ),
        )).id;
    final updated = req.copyWith(
      status: ProjectWorkerRequestStatus.approved,
      reviewedById: () => userId,
      reviewedByName: () => reviewer?.fullName,
      workerId: () => workerId,
    );
    _workerRequests[idx] = updated;
    await _notifications?.notifyProjectRole(
      req.projectId,
      AppRole.siteEngineer,
      type: 'laborer_request',
      message: '${req.fullName} was approved for the project.',
      link: AppRoutes.projectTab(req.projectId, ProjectTab.laborers),
    );
    return updated;
  }

  @override
  Future<ProjectWorkerRequest> rejectWorkerRequest(
    int id, {
    required int userId,
    required String reason,
  }) async {
    final idx = _workerRequests.indexWhere((r) => r.id == id);
    if (idx < 0) {
      throw const BusinessRuleException('Laborer request not found.');
    }
    final req = _workerRequests[idx];
    if (req.status != ProjectWorkerRequestStatus.pending) {
      throw const BusinessRuleException(
        'This laborer request has already been reviewed.',
      );
    }
    final cleanReason = reason.trim();
    if (cleanReason.isEmpty) {
      throw const BusinessRuleException(
        'Enter a reason for rejecting this request.',
      );
    }
    final reviewer = await _users.getUser(userId);
    final updated = req.copyWith(
      status: ProjectWorkerRequestStatus.rejected,
      reviewedById: () => userId,
      reviewedByName: () => reviewer?.fullName,
      rejectionReason: () => cleanReason,
    );
    _workerRequests[idx] = updated;
    await _notifications?.notifyProjectRole(
      req.projectId,
      AppRole.siteEngineer,
      type: 'laborer_request',
      message: 'Laborer request for ${req.fullName} was rejected: $cleanReason',
      link: AppRoutes.projectTab(req.projectId, ProjectTab.laborers),
    );
    return updated;
  }

  int _indexOf(int id) {
    final i = _periods.indexWhere((p) => p.id == id);
    if (i < 0) throw const BusinessRuleException('Payroll period not found.');
    return i;
  }
}

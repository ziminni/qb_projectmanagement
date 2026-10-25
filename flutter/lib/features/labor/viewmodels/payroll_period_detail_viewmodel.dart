import 'package:flutter/foundation.dart' show ChangeNotifier;

import '../../../core/utils/action_runner.dart';
import '../../../data/models/app_role.dart';
import '../../../data/models/payroll_line.dart';
import '../../../data/models/payroll_period.dart';
import '../../../data/models/project.dart';
import '../../../data/repositories/labor_repository.dart';
import '../../../data/repositories/project_repository.dart';
import '../../../data/services/labor_rules.dart';
import '../../../data/services/session_service.dart';

class PayrollPeriodDetailViewModel extends ChangeNotifier with ActionRunner {
  PayrollPeriodDetailViewModel({
    required this.periodId,
    required SessionService session,
    required ProjectRepository projects,
    required LaborRepository labor,
  }) : _session = session,
       _projects = projects,
       _labor = labor;

  final int periodId;
  final SessionService _session;
  final ProjectRepository _projects;
  final LaborRepository _labor;

  bool _loading = true;
  String? _error;
  PayrollPeriod? _period;
  Project? _project;
  List<PayrollLine> _lines = const [];
  Map<int, String> _workerNames = const {};
  bool _isPm = false;

  bool get isLoading => _loading;
  String? get error => _error;
  PayrollPeriod? get period => _period;
  Project? get project => _project;
  List<PayrollLine> get lines => _lines;
  String workerName(int id) => _workerNames[id] ?? 'Worker #$id';
  AppRole get role => _session.activeRole!;

  double get totalGross => _lines.fold(0, (s, l) => s + l.grossPay);
  double get totalNet => _lines.fold(0, (s, l) => s + l.netPay);

  String? get verifyBlocker =>
      _period == null ? null : LaborRules.canVerify(_period!, DateTime.now());

  bool get canVerify => _isPm && _period?.status == PayrollStatus.open;
  bool get isAccountant => role == AppRole.accountant;
  bool get canEditCashAdvance =>
      isAccountant && _period?.status != PayrollStatus.processed;
  bool get canProcess =>
      isAccountant && _period?.status == PayrollStatus.verified;

  Future<void> load() async {
    try {
      _period = await _labor.getPeriod(periodId);
      if (_period == null) {
        _error = 'Payroll period not found.';
        return;
      }
      final visible = await _projects.getProjectsFor(_session.user!.id, role);
      _project = visible.where((p) => p.id == _period!.projectId).firstOrNull;
      if (_project == null) {
        _error = 'You cannot see this payroll period.';
        return;
      }
      _isPm =
          role == AppRole.pm &&
          await _projects.isAssigned(
            _project!.id,
            _session.user!.id,
            AppRole.pm,
          );
      _workerNames = {
        for (final w in await _labor.getWorkers()) w.id: w.fullName,
      };
      _lines = await _labor.getLines(periodId);
    } catch (e) {
      _error = 'Could not load payroll. $e';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> _refresh() async {
    _period = await _labor.getPeriod(periodId);
    _lines = await _labor.getLines(periodId);
  }

  Future<String?> verify() => runAction(() async {
    await _labor.verifyPeriod(periodId, userId: _session.user!.id);
    await _refresh();
  });

  Future<String?> setCashAdvance(PayrollLine line, double amount) =>
      runAction(() async {
        await _labor.setCashAdvance(
          periodId,
          line.workerId,
          amount,
          userId: _session.user!.id,
        );
        await _refresh();
      });

  Future<String?> process() => runAction(() async {
    await _labor.processPeriod(periodId, userId: _session.user!.id);
    await _refresh();
  });
}

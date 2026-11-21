import 'package:flutter/foundation.dart' show ChangeNotifier;

import '../../../core/utils/action_runner.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/input_parsers.dart';
import '../../../data/models/app_role.dart';
import '../../../data/models/payroll_line.dart';
import '../../../data/models/payroll_period.dart';
import '../../../data/models/project.dart';
import '../../../data/repositories/labor_repository.dart';
import '../../../data/repositories/project_repository.dart';
import '../../../data/services/labor_rules.dart';
import '../../../data/services/session_service.dart';
import '../../../shared/pdf/pdf_report.dart';

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
  Map<int, String> _workerTrades = const {};
  bool _isPm = false;

  bool get isLoading => _loading;
  String? get error => _error;
  PayrollPeriod? get period => _period;
  Project? get project => _project;
  List<PayrollLine> get lines => _lines;
  String workerName(int id) => _workerNames[id] ?? 'Worker #$id';
  String workerTrade(int id) => _workerTrades[id] ?? '';
  AppRole get role => _session.activeRole!;

  double get totalGross => _lines.fold(0, (s, l) => s + l.grossPay);
  double get totalCashAdvance => _lines.fold(0, (s, l) => s + l.cashAdvance);
  double get totalNet => _lines.fold(0, (s, l) => s + l.netPay);

  /// The server has no statutory contribution table yet: its lines carry a
  /// zero total with `deductions_policy: 'unconfigured'`, so the screens say so
  /// instead of showing three columns of zero contributions as computed.
  bool get basicPayroll => _lines.any(
    (l) => l.deductionsPolicy == PayrollLine.deductionsUnconfigured,
  );

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
          role == AppRole.owner &&
          await _projects.isAssigned(
            _project!.id,
            _session.user!.id,
            AppRole.owner,
          );
      final workers = await _labor.getWorkers();
      _workerNames = {for (final w in workers) w.id: w.fullName};
      _workerTrades = {for (final w in workers) w.id: w.trade};
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

  /// The payroll period as a printable payroll sheet.
  PdfReport pdfReport() {
    final p = period!;
    final pr = project!;
    String peso(double v) => Formatters.peso(v);
    double sum(double Function(PayrollLine) f) =>
        _lines.fold(0, (s, l) => s + f(l));
    return PdfReport(
      title: 'Payroll',
      fileName:
          'payroll-${pr.code}-${p.periodEnd.toIso8601String().substring(0, 10)}',
      subtitle: '${pr.code} · ${pr.name}',
      info: [
        ('Period', Formatters.dateRange(p.periodStart, p.periodEnd)),
        ('Status', p.status.label),
        ('Workers', '${_lines.length}'),
        ('Total Net Pay', peso(totalNet)),
      ],
      tables: [
        PdfTable(
          title: 'Pay',
          headers: const ['Worker', 'Days', 'Cash adv.', 'Net pay'],
          rows: [
            for (final l in _lines)
              [
                workerName(l.workerId),
                InputParsers.amountText(l.daysWorked),
                peso(l.cashAdvance),
                peso(l.netPay),
              ],
          ],
          numeric: const {1, 2, 3},
          totals: [
            'Total',
            InputParsers.amountText(sum((l) => l.daysWorked)),
            peso(sum((l) => l.cashAdvance)),
            peso(totalNet),
          ],
        ),
      ],
      signatures: const [
        'Prepared by (Accountant)',
        'Verified by (Project Manager)',
        'Received by',
      ],
    );
  }

  /// Printable individual payslip for one worker in this payroll period.
  PdfReport payslipReport(PayrollLine line) {
    final p = period!;
    final pr = project!;
    final name = workerName(line.workerId);
    final trade = workerTrade(line.workerId);
    final slug = name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');

    return PdfReport(
      title: 'Payslip · $name',
      fileName:
          'payslip-${pr.code}-$slug-${p.periodEnd.toIso8601String().substring(0, 10)}',
      subtitle: '${pr.code} · ${pr.name}',
      info: [
        ('Worker', name),
        if (trade.isNotEmpty) ('Trade', trade),
        ('Pay Period', Formatters.dateRange(p.periodStart, p.periodEnd)),
        ('Status', p.status.label),
        ('Days Worked', InputParsers.amountText(line.daysWorked)),
        ('Net Pay', Formatters.peso(line.netPay)),
      ],
      tables: [
        PdfTable(
          title: 'Pay Summary',
          headers: const ['Item', 'Amount'],
          numeric: const {1},
          rows: [
            ['Pay (${InputParsers.amountText(line.daysWorked)} day(s))', Formatters.peso(line.grossPay)],
            ['Less: Cash advance', '−${Formatters.peso(line.cashAdvance)}'],
          ],
          totals: ['Net pay', Formatters.peso(line.netPay)],
        ),
      ],
      signatures: [
        'Prepared by (Accountant)',
        'Received by ($name)',
      ],
    );
  }
}

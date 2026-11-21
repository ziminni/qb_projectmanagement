import 'package:flutter/foundation.dart' show ChangeNotifier;

import '../../../data/models/payment.dart';
import '../../../data/models/payroll_period.dart';
import '../../../data/models/progress_billing.dart';
import '../../../data/models/project.dart';
import '../../../data/repositories/billing_repository.dart';
import '../../../data/repositories/labor_repository.dart';
import '../../../data/repositories/project_repository.dart';

class AccountantDashboardViewModel extends ChangeNotifier {
  AccountantDashboardViewModel({
    required ProjectRepository projects,
    required BillingRepository billing,
    required LaborRepository labor,
  }) : _projects = projects,
       _billing = billing,
       _labor = labor;

  final ProjectRepository _projects;
  final BillingRepository _billing;
  final LaborRepository _labor;

  bool _loading = true;
  String? _error;
  List<Project> _projectsList = const [];
  List<ProgressBilling> _billings = const [];
  List<Payment> _payments = const [];
  List<PayrollPeriod> _periods = const [];
  BilledSummary _summary = const BilledSummary(billed: 0, collected: 0);
  double _retentionBalance = 0;
  int _activeWorkers = 0;

  bool get isLoading => _loading;
  String? get error => _error;
  List<Project> get projects => _projectsList;
  int get activeWorkers => _activeWorkers;

  double get outstandingReceivables =>
      (_summary.billed - _summary.collected).clamp(0, double.infinity);
  double get totalCollected => _summary.collected;
  double get retentionBalance => _retentionBalance;

  List<PayrollPeriod> get verifiedPeriods =>
      _periods.where((p) => p.status == PayrollStatus.verified).toList();

  int get openPeriodsCount =>
      _periods.where((p) => p.status == PayrollStatus.open).length;

  List<ProgressBilling> get awaitingCollection => _billings
      .where(
        (b) =>
            b.status == BillingStatus.approved ||
            b.status == BillingStatus.pendingClient ||
            b.status == BillingStatus.disputed,
      )
      .toList();

  List<Payment> get recentPayments => _payments.take(8).toList();

  String projectName(int projectId) {
    for (final p in _projectsList) {
      if (p.id == projectId) return p.name;
    }
    return 'Project #$projectId';
  }

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final projects = await _projects.getProjects();
      final projectIds = [for (final p in projects) p.id];
      final billings = await _billing.getBillings(projectIds: projectIds);
      final payments = await _billing.getPayments(projectIds: projectIds);
      payments.sort((a, b) => b.paidOn.compareTo(a.paidOn));
      final summary = await _billing.billedSummary(projectIds: projectIds);
      final workers = await _labor.getWorkers(activeOnly: true);
      final periods = _labor.supportsPayroll
          ? await _labor.getPeriods(projectIds: projectIds)
          : <PayrollPeriod>[];

      double retention = 0;
      for (final p in projects) {
        try {
          final r = await _billing.retentionFor(p.id);
          retention += (r.held - r.released).clamp(0, double.infinity);
        } catch (_) {
          // Ignore per-project retention errors.
        }
      }

      _projectsList = projects;
      _billings = billings;
      _payments = payments;
      _periods = periods;
      _summary = summary;
      _retentionBalance = retention;
      _activeWorkers = workers.length;
    } catch (e) {
      _error = 'Could not load accounting dashboard. $e';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }
}

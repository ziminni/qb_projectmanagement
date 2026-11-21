import '../../../../data/models/payment.dart';
import '../../../../data/models/payroll_period.dart';
import '../../../../data/models/progress_billing.dart';
import '../../../../data/models/project.dart';
import '../../../../data/models/variation_order.dart';
import '../../../../data/repositories/billing_repository.dart';
import '../../../../data/repositories/labor_repository.dart';
import '../../../../data/repositories/procurement_repository.dart';
import '../../../../data/repositories/project_repository.dart';
import 'admin_projects_viewmodel.dart' show ProjectStage;
import 'admin_tab_viewmodel.dart';

/// One project's money, as the Finance tab's table shows it.
class AdminProjectMoney {
  const AdminProjectMoney({
    required this.project,
    required this.billed,
    required this.collected,
    required this.storeBalance,
  });

  final Project project;

  /// Net due on billings sent to the client.
  final double billed;
  final double collected;

  /// What the project owes the company store; null when unknown.
  final double? storeBalance;

  double get receivable => (billed - collected).clamp(0, double.infinity);

  /// Share of the contract billed so far.
  double get billedShare =>
      project.contractAmount <= 0 ? 0 : billed / project.contractAmount;
}

/// The Finance tab: what is billed, collected, owed and held, company-wide.
/// Read-only: the admin sees the figures but records nothing.
class AdminFinanceViewModel extends AdminTabViewModel {
  AdminFinanceViewModel({
    required ProjectRepository projects,
    required BillingRepository billing,
    required ProcurementRepository procurement,
    required LaborRepository labor,
    super.now,
  }) : _projects = projects,
       _billing = billing,
       _procurement = procurement,
       _labor = labor;

  final ProjectRepository _projects;
  final BillingRepository _billing;
  final ProcurementRepository _procurement;
  final LaborRepository _labor;

  /// Billings the client has been sent (counted as billed).
  static const billedStatuses = {
    BillingStatus.pendingClient,
    BillingStatus.disputed,
    BillingStatus.approved,
    BillingStatus.paid,
  };

  List<Project> _projectList = const [];
  List<ProgressBilling> _billings = const [];
  List<Payment> _payments = const [];
  List<VariationOrder> _vos = const [];
  List<PayrollPeriod> _payroll = const [];
  double _retentionReleased = 0;
  Map<int, double?> _storeBalances = const {};
  int _storeFailures = 0;
  List<AdminProjectMoney> _rows = const [];

  @override
  String get subject => 'the finance figures';

  /// Contract value of projects that are not finished.
  double get openContractValue => _projectList
      .where((p) => ProjectStage.of(p.status) != ProjectStage.done)
      .fold(0, (s, p) => s + p.contractAmount);

  /// Contract value of every project, approved variation orders included.
  double get totalContractValue =>
      _projectList.fold<double>(0, (s, p) => s + p.contractAmount);

  double get billed => _billings
      .where((b) => billedStatuses.contains(b.status))
      .fold(0, (s, b) => s + b.netDue);

  double get collected => _payments.fold(0, (s, p) => s + p.amount);

  double get receivable => (billed - collected).clamp(0, double.infinity);

  /// Collected as a share of billed.
  double get collectionRate => billed <= 0 ? 0 : collected / billed;

  double get collectedLast30Days {
    final since = today.subtract(const Duration(days: 30));
    return _payments
        .where((p) => !p.paidOn.isBefore(since))
        .fold(0, (s, p) => s + p.amount);
  }

  /// Retention withheld on billings sent, less what was released.
  double get retentionHeld {
    final withheld = _billings
        .where((b) => billedStatuses.contains(b.status))
        .fold<double>(0, (s, b) => s + b.lessRetention);
    return (withheld - _retentionReleased).clamp(0, double.infinity);
  }

  /// Billing count and net due per status.
  Map<BillingStatus, ({int count, double amount})> get billingsByStatus {
    final out = <BillingStatus, ({int count, double amount})>{};
    for (final b in _billings) {
      final prev = out[b.status] ?? (count: 0, amount: 0.0);
      out[b.status] = (count: prev.count + 1, amount: prev.amount + b.netDue);
    }
    return out;
  }

  /// Billings the client disputed, newest first.
  List<ProgressBilling> get disputed =>
      _billings.where((b) => b.status == BillingStatus.disputed).toList()
        ..sort((a, b) => b.periodEnd.compareTo(a.periodEnd));

  /// Billings waiting on the client for over 14 days.
  List<ProgressBilling> get slowClientReplies => _billings.where((b) {
    if (b.status != BillingStatus.pendingClient) return false;
    final sent = b.updatedAt ?? b.createdAt ?? b.periodEnd;
    return today.difference(sent).inDays > 14;
  }).toList();

  /// Approved but not fully paid: what clients owe right now.
  List<ProgressBilling> get approvedUnpaid =>
      _billings.where((b) => b.status == BillingStatus.approved).toList();

  double get approvedVoTotal => _vos
      .where((v) => v.status == VariationOrderStatus.approved)
      .fold(0, (s, v) => s + v.amount);

  int get pendingVoCount => _vos
      .where(
        (v) =>
            v.status == VariationOrderStatus.proposed ||
            v.status == VariationOrderStatus.pendingClient,
      )
      .length;

  double get pendingVoTotal => _vos
      .where(
        (v) =>
            v.status == VariationOrderStatus.proposed ||
            v.status == VariationOrderStatus.pendingClient,
      )
      .fold(0, (s, v) => s + v.amount);

  int payrollIn(PayrollStatus status) =>
      _payroll.where((p) => p.status == status).length;

  /// Owed to the company store across projects it could report on.
  double get storeOwed => _storeBalances.values.fold(0, (s, v) => s + (v ?? 0));

  /// Projects whose store balance could not be read (store offline).
  int get storeFailures => _storeFailures;

  bool get hasStoreFigures => _storeBalances.values.any((v) => v != null);

  /// Payments, newest first.
  List<Payment> get recentPayments => _payments.take(6).toList();

  List<AdminProjectMoney> get projectRows => _rows;

  String projectName(int projectId) {
    for (final p in _projectList) {
      if (p.id == projectId) return '${p.code} · ${p.name}';
    }
    return 'Project #$projectId';
  }

  int? projectOfBilling(int billingId) {
    for (final b in _billings) {
      if (b.id == billingId) return b.projectId;
    }
    return null;
  }

  @override
  Future<void> fetch() async {
    final (projects, billings, payments, vos, releases, payroll) = await (
      _projects.getProjects(),
      _billing.getBillings(),
      _billing.getPayments(),
      _billing.getVariationOrders(),
      _billing.getRetentionReleases(),
      _labor.supportsPayroll
          ? _labor.getPeriods()
          : Future.value(const <PayrollPeriod>[]),
    ).wait;
    _projectList = projects;
    _billings = billings;
    _payments = [...payments]..sort((a, b) => b.paidOn.compareTo(a.paidOn));
    _vos = vos;
    _payroll = payroll;
    _retentionReleased = releases.fold(0, (s, r) => s + r.amount);

    // The store is a separate system that may be offline: one project's
    // failure never hides the rest of the tab.
    final open = [
      for (final p in projects)
        if (ProjectStage.of(p.status) != ProjectStage.done) p,
    ];
    var failures = 0;
    final balances = await Future.wait([
      for (final p in open)
        _procurement
            .getStoreBalance(p.id)
            .then<double?>(
              (b) => b == null || !b.atStore ? 0 : b.balance,
              onError: (_) {
                failures++;
                return null;
              },
            ),
    ]);
    _storeFailures = failures;
    _storeBalances = {for (final (i, p) in open.indexed) p.id: balances[i]};

    final billingProject = {for (final b in billings) b.id: b.projectId};
    final collectedBy = <int, double>{};
    for (final p in payments) {
      final pid = billingProject[p.progressBillingId];
      if (pid != null) collectedBy[pid] = (collectedBy[pid] ?? 0) + p.amount;
    }
    final billedBy = <int, double>{};
    for (final b in billings) {
      if (!billedStatuses.contains(b.status)) continue;
      billedBy[b.projectId] = (billedBy[b.projectId] ?? 0) + b.netDue;
    }
    _rows = [
      for (final p in projects)
        AdminProjectMoney(
          project: p,
          billed: billedBy[p.id] ?? 0,
          collected: collectedBy[p.id] ?? 0,
          storeBalance: _storeBalances[p.id],
        ),
    ]..sort((a, b) => b.receivable.compareTo(a.receivable));
  }
}

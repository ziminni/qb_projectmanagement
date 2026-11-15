import 'package:flutter/foundation.dart' show ChangeNotifier;

import '../../../data/models/payment.dart';
import '../../../data/models/progress_billing.dart';
import '../../../data/models/project.dart';
import '../../../data/models/variation_order.dart';
import '../../../data/repositories/billing_repository.dart';
import '../../../data/repositories/project_repository.dart';
import '../../../data/services/business_rule_exception.dart';
import 'expense_reports_viewmodel.dart';

/// Project "Financials" tab: contract, % accomplished, earned value,
/// billed and collected, budget vs. actual, billings, payments and VOs.
class ProjectFinancialsViewModel extends ChangeNotifier {
  ProjectFinancialsViewModel({
    required this.projectId,
    required ProjectRepository projects,
    required BillingRepository billing,
    required CostReportBuilder builder,
  }) : _projects = projects,
       _billing = billing,
       _builder = builder;

  final int projectId;
  final ProjectRepository _projects;
  final BillingRepository _billing;
  final CostReportBuilder _builder;

  bool _loading = true;
  String? _error;
  Project? project;
  CostReport? report;
  List<ProgressBilling> billings = const [];
  List<Payment> payments = const [];
  List<VariationOrder> variationOrders = const [];
  BilledSummary? summary;
  double retentionHeld = 0;

  /// True when the derived-cost half (materials, payroll, equipment) has no
  /// route yet: the billings, payments, VOs and retention are still the
  /// server's own rows and must not disappear with it.
  bool costsUnavailable = false;

  bool get isLoading => _loading;
  String? get error => _error;

  double get approvedVoTotal => variationOrders
      .where((v) => v.status == VariationOrderStatus.approved)
      .fold(0, (s, v) => s + v.amount);

  Future<void> load() async {
    try {
      project = (await _projects.getProject(projectId))!;
      billings = await _billing.getBillings(projectIds: [projectId]);
      payments = await _billing.getPayments(projectIds: [projectId]);
      variationOrders = await _billing.getVariationOrders(
        projectIds: [projectId],
      );
      summary = await _billing.billedSummary(projectIds: [projectId]);
      final r = await _billing.retentionFor(projectId);
      retentionHeld = r.held - r.released;
      report = await _builder.build(project!);
    } on UnsupportedError {
      // Derived costs have no route yet (phase-4 contract excludes them), so
      // the tab shows the billing half and says costing is unavailable.
      costsUnavailable = true;
    } on BusinessRuleException catch (e) {
      _error = e.message;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }
}

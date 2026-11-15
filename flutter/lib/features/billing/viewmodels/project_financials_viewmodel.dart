import 'package:flutter/foundation.dart' show ChangeNotifier;

import '../../../data/models/payment.dart';
import '../../../data/models/progress_billing.dart';
import '../../../data/models/project.dart';
import '../../../data/models/variation_order.dart';
import '../../../data/repositories/billing_repository.dart';
import '../../../data/models/store_balance.dart';
import '../../../data/repositories/procurement_repository.dart';
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
    required ProcurementRepository procurement,
  }) : _projects = projects,
       _billing = billing,
       _procurement = procurement,
       _builder = builder;

  final int projectId;
  final ProjectRepository _projects;
  final BillingRepository _billing;
  final ProcurementRepository _procurement;
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

  /// Why the cost half is missing, when the server said why.
  String? costsError;

  /// What the store says this project owes it; null when there is no store to
  /// ask (the offline demo) or it could not be read, see [storeBalanceError].
  StoreBalance? storeBalance;

  /// Online payment proofs submitted to the store for this project (Phase 1c).
  List<StorePaymentReceipt> storeReceipts = const [];

  /// Why the store's balance is missing. Kept apart from [error] so a store
  /// that is down never takes the billings, payments and VOs down with it.
  String? storeBalanceError;

  /// True when the derived-cost half (materials, payroll, equipment) has no
  /// route yet: the billings, payments, VOs and retention are still the
  /// server's own rows and must not disappear with it.
  bool costsUnavailable = false;

  bool get isLoading => _loading;
  String? get error => _error;

  double get approvedVoTotal => variationOrders
      .where((v) => v.status == VariationOrderStatus.approved)
      .fold(0, (s, v) => s + v.amount);

  Future<void> _loadStoreBalance() async {
    try {
      storeBalance = await _procurement.getStoreBalance(projectId);
      if (storeBalance != null && storeBalance!.atStore) {
        try {
          storeReceipts = await _procurement.getStorePaymentReceipts(projectId);
        } on Object {
          storeReceipts = const [];
        }
      }
    } on BusinessRuleException catch (e) {
      storeBalanceError = e.message;
    } on FormatException {
      storeBalanceError = 'The store sent an answer CPMS could not read.';
    }
  }

  Future<void> submitStorePaymentReceipt({
    required double amount,
    required String referenceNo,
    String paymentMethod = 'BANK_TRANSFER',
    String notes = '',
  }) async {
    await _procurement.submitStorePaymentReceipt(
      projectId,
      amount: amount,
      referenceNo: referenceNo,
      paymentMethod: paymentMethod,
      notes: notes,
    );
    await _loadStoreBalance();
    notifyListeners();
  }

  /// The cost half fails on its own: the billings above it still show.
  Future<void> _loadCosts() async {
    try {
      report = await _builder.build(project!);
    } on UnsupportedError {
      costsUnavailable = true;
    } on BusinessRuleException catch (e) {
      costsUnavailable = true;
      costsError = e.message;
    }
  }

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
      await _loadStoreBalance();
      await _loadCosts();
    } on BusinessRuleException catch (e) {
      _error = e.message;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }
}

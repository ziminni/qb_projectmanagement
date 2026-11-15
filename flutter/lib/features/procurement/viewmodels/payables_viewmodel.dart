import 'package:flutter/foundation.dart' show ChangeNotifier;

import '../../../core/utils/action_runner.dart';
import '../../../core/utils/app_messages.dart';
import '../../../data/models/app_role.dart';
import '../../../data/models/store_balance.dart';
import '../../../data/repositories/procurement_repository.dart';
import '../../../data/services/business_rule_exception.dart';
import '../../../data/services/procurement_rules.dart';
import '../../../data/services/session_service.dart';
import '../../../shared/widgets/app_payment_dialog.dart';
import 'procurement_lookups.dart';

/// Accountant's supplier payables: delivered value, paid and balance per PO.
class PayablesViewModel extends ChangeNotifier with ActionRunner {
  PayablesViewModel({
    required SessionService session,
    required ProcurementRepository procurement,
    required this.lookups,
  }) : _session = session,
       _procurement = procurement;

  final SessionService _session;
  final ProcurementRepository _procurement;
  final ProcurementLookups lookups;

  bool _loading = true;
  String? _error;
  List<Payable> _all = const [];
  bool _unpaidOnly = true;

  /// API mode: outside purchases are paid at the counter, so the supplier
  /// debt is what projects owe our store, and the store holds that record
  /// (owner decision 2026-11-15). This view then only reads it.
  bool get fromStore => !_procurement.supportsPayments;

  /// Projects the store has charged, with what it says they owe.
  List<(int projectId, StoreBalance balance)> storeBalances = const [];

  bool get isLoading => _loading;
  String? get error => _error;
  bool get unpaidOnly => _unpaidOnly;
  bool get canPay => _session.activeRole == AppRole.accountant;

  List<Payable> get items =>
      _unpaidOnly ? _all.where((p) => p.balance > 0.005).toList() : _all;

  double get totalBalance => fromStore
      ? storeBalances.fold(0, (s, b) => s + b.$2.balance)
      : _all.fold(0, (s, p) => s + p.balance);

  Future<void> load() async {
    await lookups.load(_session.user!.id, _session.activeRole!);
    await _refresh();
  }

  Future<void> _refresh() async {
    _error = null;
    if (fromStore) return _refreshFromStore();
    try {
      _all =
          await _procurement.getPayables(
              projectIds: lookups.projects.keys.toList(),
            )
            ..sort((a, b) => b.balance.compareTo(a.balance));
    } on UnsupportedError {
      // Supplier payables are blocked in API mode (blocker 2).
      _all = const [];
      _error = supplierAccountingUnavailable;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// One unreadable project fails the whole list: a total missing a project
  /// would look smaller than the real debt.
  Future<void> _refreshFromStore() async {
    try {
      final ids = lookups.projects.keys.toList();
      final answers = await Future.wait(ids.map(_procurement.getStoreBalance));
      storeBalances = [
        for (final (i, b) in answers.indexed)
          if (b != null && b.atStore && (!_unpaidOnly || b.balance > 0.005))
            (ids[i], b),
      ]..sort((a, b) => b.$2.balance.compareTo(a.$2.balance));
    } on BusinessRuleException catch (e) {
      storeBalances = const [];
      _error = e.message;
    } on FormatException {
      storeBalances = const [];
      _error = 'The store sent an answer CPMS could not read.';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  void setUnpaidOnly(bool v) {
    _unpaidOnly = v;
    if (fromStore) {
      _refresh();
      return;
    }
    notifyListeners();
  }

  String? validateAmount(Payable p, double? amount) =>
      ProcurementRules.validatePayment(amount, p.balance);

  Future<String?> pay(Payable p, AppPaymentInput input) => runAction(() async {
    await _procurement.recordPayment(
      p.order.id,
      amount: input.amount,
      paidOn: input.paidOn,
      method: input.method,
      referenceNo: input.referenceNo,
      userId: _session.user!.id,
    );
    await _refresh();
  });
}

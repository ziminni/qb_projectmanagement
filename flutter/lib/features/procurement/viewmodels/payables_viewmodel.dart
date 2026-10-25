import 'package:flutter/foundation.dart' show ChangeNotifier;

import '../../../core/utils/action_runner.dart';
import '../../../data/models/app_role.dart';
import '../../../data/repositories/procurement_repository.dart';
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
  List<Payable> _all = const [];
  bool _unpaidOnly = true;

  bool get isLoading => _loading;
  bool get unpaidOnly => _unpaidOnly;
  bool get canPay => _session.activeRole == AppRole.accountant;

  List<Payable> get items =>
      _unpaidOnly ? _all.where((p) => p.balance > 0.005).toList() : _all;

  double get totalBalance => _all.fold(0, (s, p) => s + p.balance);

  Future<void> load() async {
    await lookups.load(_session.user!.id, _session.activeRole!);
    await _refresh();
  }

  Future<void> _refresh() async {
    _all =
        await _procurement.getPayables(
            projectIds: lookups.projects.keys.toList(),
          )
          ..sort((a, b) => b.balance.compareTo(a.balance));
    _loading = false;
    notifyListeners();
  }

  void setUnpaidOnly(bool v) {
    _unpaidOnly = v;
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

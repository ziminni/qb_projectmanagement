import 'package:flutter/foundation.dart' show ChangeNotifier;

import '../../../core/utils/action_runner.dart';
import '../../../data/models/app_role.dart';
import '../../../data/models/purchase_order.dart';
import '../../../data/repositories/procurement_repository.dart';
import '../../../data/services/session_service.dart';
import 'procurement_lookups.dart';

class PurchaseOrderDetailViewModel extends ChangeNotifier with ActionRunner {
  PurchaseOrderDetailViewModel({
    required this.orderId,
    required SessionService session,
    required ProcurementRepository procurement,
    required this.lookups,
  }) : _session = session,
       _procurement = procurement;

  final int orderId;
  final SessionService _session;
  final ProcurementRepository _procurement;
  final ProcurementLookups lookups;

  bool _loading = true;
  String? _error;
  PurchaseOrderDetail? _detail;

  bool get isLoading => _loading;
  String? get error => _error;
  PurchaseOrderDetail? get detail => _detail;
  PurchaseOrder? get order => _detail?.order;
  AppRole get role => _session.activeRole!;

  double get paid =>
      _detail?.payments.fold<double>(0, (s, p) => s + p.amount) ?? 0;

  bool get canApprove =>
      role == AppRole.owner &&
      order?.status == PurchaseOrderStatus.pendingOwner;

  bool get canCancel =>
      role == AppRole.purchasing &&
      _detail != null &&
      _detail!.deliveries.isEmpty &&
      order!.status != PurchaseOrderStatus.cancelled;

  bool get canReceive =>
      role == AppRole.siteEngineer && (order?.status.awaitsDelivery ?? false);

  Future<void> load() async {
    try {
      await lookups.load(_session.user!.id, role);
      _detail = await _procurement.getPurchaseOrder(orderId);
      if (_detail == null) {
        _error = 'Purchase order not found.';
      } else if (!lookups.projects.containsKey(_detail!.order.projectId)) {
        _error = 'You cannot see this purchase order.';
      }
    } catch (e) {
      _error = 'Could not load the purchase order. $e';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<String?> approve() => runAction(() async {
    await _procurement.approvePurchaseOrder(orderId, userId: _session.user!.id);
    _detail = await _procurement.getPurchaseOrder(orderId);
  });

  Future<String?> cancel() => runAction(() async {
    await _procurement.cancelPurchaseOrder(orderId, userId: _session.user!.id);
    _detail = await _procurement.getPurchaseOrder(orderId);
  });
}

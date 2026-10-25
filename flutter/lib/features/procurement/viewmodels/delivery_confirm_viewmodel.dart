import 'package:flutter/foundation.dart' show ChangeNotifier;

import '../../../core/utils/action_runner.dart';
import '../../../data/models/app_role.dart';
import '../../../data/models/purchase_order_item.dart';
import '../../../data/repositories/procurement_repository.dart';
import '../../../data/services/session_service.dart';
import 'procurement_lookups.dart';

class ReceiptLine {
  ReceiptLine(this.item, {required this.alreadyReceived})
    : received = item.quantity - alreadyReceived;

  final PurchaseOrderItem item;
  final double alreadyReceived;
  double received;
  double damaged = 0;

  double get remaining => item.quantity - alreadyReceived;
}

/// Site engineer confirms what actually arrived, including damage.
class DeliveryConfirmViewModel extends ChangeNotifier with ActionRunner {
  DeliveryConfirmViewModel({
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
  List<ReceiptLine> lines = const [];
  bool receiptPhoto = false;

  bool get isLoading => _loading;
  String? get error => _error;
  PurchaseOrderDetail? get detail => _detail;

  Future<void> load() async {
    try {
      if (_session.activeRole != AppRole.siteEngineer) {
        _error = 'Only the site engineer confirms deliveries.';
        return;
      }
      await lookups.load(_session.user!.id, AppRole.siteEngineer);
      _detail = await _procurement.getPurchaseOrder(orderId);
      if (_detail == null ||
          !lookups.projects.containsKey(_detail!.order.projectId)) {
        _error = 'Purchase order not found on your sites.';
        return;
      }
      if (!_detail!.order.status.awaitsDelivery) {
        _error =
            '${_detail!.order.poNo} is ${_detail!.order.status.label.toLowerCase()}.';
        return;
      }
      lines = [
        for (final i in _detail!.items)
          if (_detail!.receivedFor(i.id) < i.quantity)
            ReceiptLine(i, alreadyReceived: _detail!.receivedFor(i.id)),
      ];
    } catch (e) {
      _error = 'Could not load the purchase order. $e';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  void setReceiptPhoto(bool v) {
    receiptPhoto = v;
    notifyListeners();
  }

  void changed() => notifyListeners();

  Future<String?> confirm() => runAction(
    () => _procurement.confirmDelivery(
      orderId,
      [
        for (final l in lines)
          (poItemId: l.item.id, received: l.received, damaged: l.damaged),
      ],
      userId: _session.user!.id,
      receiptPhotoUrl: receiptPhoto
          ? 'mock://receipts/${DateTime.now().microsecondsSinceEpoch}'
          : null,
    ),
  );
}

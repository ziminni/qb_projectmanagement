import 'package:flutter/foundation.dart' show ChangeNotifier;

import '../../../data/models/app_role.dart';
import '../../../data/models/purchase_order.dart';
import '../../../data/repositories/procurement_repository.dart';
import '../../../data/services/session_service.dart';
import 'procurement_lookups.dart';

/// POs expecting deliveries and the delivery history, for the site engineer
/// (own sites) and the owner.
class DeliveriesViewModel extends ChangeNotifier {
  DeliveriesViewModel({
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
  List<PurchaseOrder> _awaiting = const [];
  List<({DeliveryDetail delivery, PurchaseOrder order})> _history = const [];

  bool get isLoading => _loading;
  String? get error => _error;
  List<PurchaseOrder> get awaiting => _awaiting;
  List<({DeliveryDetail delivery, PurchaseOrder order})> get history =>
      _history;
  bool get canConfirm => _session.activeRole == AppRole.siteEngineer;

  Future<void> load() async {
    try {
      await lookups.load(_session.user!.id, _session.activeRole!);
      final ids = lookups.projects.keys.toList();
      _awaiting = await _procurement.getPurchaseOrders(
        projectIds: ids,
        statuses: [
          PurchaseOrderStatus.released,
          PurchaseOrderStatus.partiallyDelivered,
        ],
      );
      _history = await _procurement.getDeliveries(projectIds: ids);
    } catch (e) {
      _error = 'Could not load deliveries. $e';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }
}

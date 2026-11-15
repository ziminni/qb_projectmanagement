import 'package:flutter/foundation.dart' show ChangeNotifier;

import '../../../data/models/material_request.dart';
import '../../../data/models/material_source.dart';
import '../../../data/models/purchase_order.dart';
import '../../../data/repositories/procurement_repository.dart';
import '../../../data/services/inventory_calculator.dart';
import '../../../data/services/session_service.dart';
import 'procurement_lookups.dart';

/// The project "Materials" tab: requests, POs, deliveries, site inventory
/// and own-store vs. external cost.
class ProjectMaterialsViewModel extends ChangeNotifier {
  ProjectMaterialsViewModel({
    required this.projectId,
    required SessionService session,
    required ProcurementRepository procurement,
    required this.lookups,
  }) : _session = session,
       _procurement = procurement;

  final int projectId;
  final SessionService _session;
  final ProcurementRepository _procurement;
  final ProcurementLookups lookups;

  bool _loading = true;
  List<MaterialRequest> requests = const [];
  List<PurchaseOrder> orders = const [];
  List<({DeliveryDetail delivery, PurchaseOrder order})> deliveries = const [];
  List<InventoryLine> inventory = const [];

  bool get isLoading => _loading;

  /// Ordered value by source, excluding cancelled POs.
  double costFor(MaterialSource source) => orders
      .where(
        (o) => o.source == source && o.status != PurchaseOrderStatus.cancelled,
      )
      .fold(0, (s, o) => s + o.totalAmount);

  Future<void> load() async {
    await lookups.load(_session.user!.id, _session.activeRole!);
    requests = await _procurement.getRequests(projectIds: [projectId]);
    orders = await _procurement.getPurchaseOrders(projectIds: [projectId]);
    deliveries = await _procurement.getDeliveries(projectIds: [projectId]);
    inventory = await _procurement.getSiteInventory(projectId);
    _loading = false;
    notifyListeners();
  }
}

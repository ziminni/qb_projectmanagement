import 'package:flutter/foundation.dart' show ChangeNotifier;

import '../../../data/models/purchase_order.dart';
import '../../../data/repositories/procurement_repository.dart';
import '../../../data/services/session_service.dart';
import 'procurement_lookups.dart';

class PurchaseOrdersViewModel extends ChangeNotifier {
  PurchaseOrdersViewModel({
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
  List<PurchaseOrder> _items = const [];
  PurchaseOrderStatus? _status;

  bool get isLoading => _loading;
  String? get error => _error;
  List<PurchaseOrder> get items => _items;
  PurchaseOrderStatus? get statusFilter => _status;

  Future<void> load() async {
    _loading = true;
    notifyListeners();
    try {
      await lookups.load(_session.user!.id, _session.activeRole!);
      _items = await _procurement.getPurchaseOrders(
        projectIds: lookups.projects.keys.toList(),
        statuses: _status == null ? null : [_status!],
      );
    } catch (e) {
      _error = 'Could not load purchase orders. $e';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  void setStatus(PurchaseOrderStatus? status) {
    _status = status;
    load();
  }
}

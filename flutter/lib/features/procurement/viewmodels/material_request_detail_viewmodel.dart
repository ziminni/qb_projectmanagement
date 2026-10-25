import 'package:flutter/foundation.dart' show ChangeNotifier;

import '../../../core/utils/action_runner.dart';
import '../../../data/models/app_role.dart';
import '../../../data/models/material_request.dart';
import '../../../data/models/purchase_order.dart';
import '../../../data/repositories/procurement_repository.dart';
import '../../../data/services/procurement_rules.dart';
import '../../../data/services/session_service.dart';
import 'procurement_lookups.dart';

class MaterialRequestDetailViewModel extends ChangeNotifier with ActionRunner {
  MaterialRequestDetailViewModel({
    required this.requestId,
    required SessionService session,
    required ProcurementRepository procurement,
    required this.lookups,
  }) : _session = session,
       _procurement = procurement;

  final int requestId;
  final SessionService _session;
  final ProcurementRepository _procurement;
  final ProcurementLookups lookups;

  bool _loading = true;
  String? _error;
  MaterialRequestDetail? _detail;
  BudgetCheck? _budget;
  List<PurchaseOrder> _orders = const [];

  bool get isLoading => _loading;
  String? get error => _error;
  MaterialRequestDetail? get detail => _detail;
  MaterialRequest? get request => _detail?.request;
  BudgetCheck? get budget => _budget;
  List<PurchaseOrder> get orders => _orders;
  AppRole get role => _session.activeRole!;

  /// Estimated cost at default unit costs.
  double get estimatedCost => _detail == null
      ? 0
      : _detail!.items.fold(
          0,
          (s, i) =>
              s +
              i.quantity *
                  (lookups.materials[i.materialId]?.defaultUnitCost ?? 0),
        );

  bool get canReview => switch (request?.status) {
    MaterialRequestStatus.pending => role == AppRole.pm,
    MaterialRequestStatus.pendingOwner => role == AppRole.owner,
    _ => false,
  };

  bool get canOrder =>
      role == AppRole.purchasing &&
      request?.status == MaterialRequestStatus.approved;

  Future<void> load() async {
    try {
      await lookups.load(_session.user!.id, role);
      await _refresh();
      if (_detail != null &&
          !lookups.projects.containsKey(_detail!.request.projectId)) {
        _error = 'You cannot see this request.';
      }
    } catch (e) {
      _error = 'Could not load the request. $e';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> _refresh() async {
    _detail = await _procurement.getRequest(requestId);
    if (_detail == null) {
      _error = 'Request not found.';
      return;
    }
    final r = _detail!.request;
    _budget = await _procurement.checkBudget(r.categoryId, [
      for (final i in _detail!.items)
        (materialId: i.materialId, quantity: i.quantity),
    ], excludingRequestId: r.id);
    final itemIds = _detail!.items.map((i) => i.id).toSet();
    final orders = <PurchaseOrder>[];
    for (final o in await _procurement.getPurchaseOrders(
      projectIds: [r.projectId],
    )) {
      final d = await _procurement.getPurchaseOrder(o.id);
      if (d!.items.any((i) => itemIds.contains(i.materialRequestItemId))) {
        orders.add(o);
      }
    }
    _orders = orders;
  }

  Future<String?> approve() => runAction(() async {
    await _procurement.approveRequest(
      requestId,
      userId: _session.user!.id,
      role: role,
    );
    await _refresh();
  });

  Future<String?> reject(String reason) => runAction(() async {
    await _procurement.rejectRequest(
      requestId,
      userId: _session.user!.id,
      role: role,
      reason: reason,
    );
    await _refresh();
  });
}

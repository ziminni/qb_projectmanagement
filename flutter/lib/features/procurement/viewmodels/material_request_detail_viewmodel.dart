import 'package:flutter/foundation.dart' show ChangeNotifier;

import '../../../core/utils/action_runner.dart';
import '../../../data/models/app_role.dart';
import '../../../data/models/material_request.dart';
import '../../../data/models/material_source.dart';
import '../../../data/models/purchase_order.dart';
import '../../../data/repositories/procurement_repository.dart';
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
  List<PurchaseOrder> _orders = const [];
  Map<int, PosStatus> _posStatuses = const {};
  Set<int> _posStatusFailed = const {};

  bool get isLoading => _loading;
  String? get error => _error;
  MaterialRequestDetail? get detail => _detail;
  MaterialRequest? get request => _detail?.request;
  List<PurchaseOrder> get orders => _orders;
  AppRole get role => _session.activeRole!;
  bool get supportsPosStatus => _procurement.supportsPosStatus;

  String? storeStatusFor(PurchaseOrder order) {
    if (!supportsPosStatus || order.source != MaterialSource.ownStore) {
      return null;
    }
    if (_posStatusFailed.contains(order.id)) {
      return 'Store status unavailable';
    }
    return _posStatuses[order.id]?.compactSummary;
  }

  bool get canReject =>
      role == AppRole.owner && request?.status == MaterialRequestStatus.pending;

  /// The owner can answer with more than one order, e.g. part from the own
  /// store and the rest bought elsewhere.
  bool get canOrder =>
      role == AppRole.owner &&
      request?.status != MaterialRequestStatus.rejected;

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
      _orders = const [];
      _posStatuses = const {};
      _posStatusFailed = const {};
      return;
    }
    _orders = [
      for (final o in await _procurement.getPurchaseOrders(
        projectIds: [_detail!.request.projectId],
      ))
        if (o.materialRequestId == requestId) o,
    ];
    final posStatuses = <int, PosStatus>{};
    final posStatusFailed = <int>{};
    if (_procurement.supportsPosStatus) {
      for (final o in _orders) {
        if (o.source != MaterialSource.ownStore) continue;
        try {
          posStatuses[o.id] = await _procurement.getPosStatus(o.id);
        } catch (_) {
          posStatusFailed.add(o.id);
        }
      }
    }
    _posStatuses = posStatuses;
    _posStatusFailed = posStatusFailed;
  }

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

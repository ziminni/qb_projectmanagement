import 'package:flutter/foundation.dart' show ChangeNotifier;

import '../../../core/utils/action_runner.dart';
import '../../../data/models/app_role.dart';
import '../../../data/models/material_request_item.dart';
import '../../../data/models/material_source.dart';
import '../../../data/models/supplier.dart';
import '../../../data/repositories/procurement_repository.dart';
import '../../../data/services/business_rule_exception.dart';
import '../../../data/services/session_service.dart';
import 'procurement_lookups.dart';

/// The owner's choice for one request item.
class OrderLineDraft {
  OrderLineDraft(this.item, {required this.unitPrice});

  final MaterialRequestItem item;
  bool include = true;
  MaterialSource source = MaterialSource.ownStore;
  int? supplierId;
  double unitPrice;

  double get amount => item.quantity * unitPrice;
}

/// Turns an approved request into POs: the owner picks Own store or Other
/// supplier per item, and each supplier becomes one PO.
class PurchaseOrderCreateViewModel extends ChangeNotifier with ActionRunner {
  PurchaseOrderCreateViewModel({
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
  List<OrderLineDraft> lines = const [];
  int _created = 0;

  bool get isLoading => _loading;
  String? get error => _error;
  MaterialRequestDetail? get detail => _detail;
  int get createdCount => _created;

  Supplier? get ownStore =>
      lookups.suppliers.values.where((s) => s.isOwnStore).firstOrNull;

  List<Supplier> get externalSuppliers =>
      lookups.suppliers.values.where((s) => !s.isOwnStore).toList();

  /// Planned POs: supplier → total, for the summary.
  Map<int, double> get totalsBySupplier {
    final totals = <int, double>{};
    for (final l in lines.where((l) => l.include && l.supplierId != null)) {
      totals[l.supplierId!] = (totals[l.supplierId!] ?? 0) + l.amount;
    }
    return totals;
  }

  Future<void> load() async {
    try {
      if (_session.activeRole != AppRole.owner) {
        _error = 'Only the owner places purchase orders.';
        return;
      }
      await lookups.load(_session.user!.id, AppRole.owner);
      _detail = await _procurement.getRequest(requestId);
      if (_detail == null) {
        _error = 'Request not found.';
        return;
      }
      lines = [
        for (final i in _detail!.items)
          if (i.status == MaterialRequestItemStatus.pending)
            OrderLineDraft(
              i,
              unitPrice: lookups.materials[i.materialId]?.defaultUnitCost ?? 0,
            )..supplierId = ownStore?.id,
      ];
      if (lines.isEmpty) _error = 'Every item on this request is ordered.';
    } catch (e) {
      _error = 'Could not load the request. $e';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  void setSource(OrderLineDraft line, MaterialSource source) {
    line.source = source;
    line.supplierId = source == MaterialSource.ownStore
        ? ownStore?.id
        : (externalSuppliers.length == 1 ? externalSuppliers.first.id : null);
    notifyListeners();
  }

  void changed() => notifyListeners();

  Future<String?> create() => runAction(() async {
    final chosen = lines.where((l) => l.include).toList();
    if (chosen.any((l) => l.supplierId == null)) {
      throw const BusinessRuleException('Choose a supplier for every item.');
    }
    final orders = await _procurement.createPurchaseOrders(requestId, [
      for (final l in chosen)
        OrderLine(
          requestItemId: l.item.id,
          source: l.source,
          supplierId: l.supplierId!,
          unitPrice: l.unitPrice,
        ),
    ], userId: _session.user!.id);
    _created = orders.length;
  });
}

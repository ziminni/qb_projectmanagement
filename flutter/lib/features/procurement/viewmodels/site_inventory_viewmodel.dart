import 'package:flutter/foundation.dart' show ChangeNotifier;

import '../../../data/repositories/procurement_repository.dart';
import '../../../data/services/inventory_calculator.dart';
import '../../../data/services/session_service.dart';
import 'procurement_lookups.dart';

/// Site inventory per project: deliveries received − materials used.
class SiteInventoryViewModel extends ChangeNotifier {
  SiteInventoryViewModel({
    this.fixedProjectId,
    required SessionService session,
    required ProcurementRepository procurement,
    required this.lookups,
  }) : _session = session,
       _procurement = procurement;

  final int? fixedProjectId;
  final SessionService _session;
  final ProcurementRepository _procurement;
  final ProcurementLookups lookups;

  bool _loading = true;
  int? _projectId;
  List<InventoryLine> _lines = const [];

  bool get isLoading => _loading;
  int? get projectId => _projectId;
  List<InventoryLine> get lines => _lines;

  Future<void> load() async {
    await lookups.load(_session.user!.id, _session.activeRole!);
    _projectId = fixedProjectId ?? lookups.projects.keys.firstOrNull;
    await _refresh();
  }

  Future<void> setProject(int? id) async {
    _projectId = id;
    await _refresh();
  }

  Future<void> _refresh() async {
    _lines = _projectId == null
        ? const []
        : (await _procurement.getSiteInventory(_projectId!)
            ..sort(
              (a, b) => lookups
                  .materialName(a.materialId)
                  .compareTo(lookups.materialName(b.materialId)),
            ));
    _loading = false;
    notifyListeners();
  }
}

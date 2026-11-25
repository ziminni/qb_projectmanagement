import 'package:flutter/foundation.dart' show ChangeNotifier;

import '../../../core/utils/action_runner.dart';
import '../../../data/models/equipment.dart';
import '../../../data/repositories/master_data_repository.dart';
import 'admin_audit.dart';

/// Admin "Equipment master list": the Queen Builders equipment catalogue that
/// feeds the equipment dropdown on a project's Equipment tab
/// (`project_equipment_page.dart`, "Borrow / request equipment").
class EquipmentMasterListViewModel extends ChangeNotifier with ActionRunner {
  EquipmentMasterListViewModel({
    required MasterDataRepository masterData,
    AdminAudit? audit,
  }) : _masterData = masterData,
       _audit = audit;

  final MasterDataRepository _masterData;
  final AdminAudit? _audit;

  bool _loading = true;
  String? _error;
  List<Equipment> _all = const [];
  String _query = '';
  EquipmentOwnership? _ownershipFilter;

  bool get isLoading => _loading;
  String? get error => _error;
  List<Equipment> get all => _all;
  String get query => _query;
  EquipmentOwnership? get ownershipFilter => _ownershipFilter;
  bool get hasFilters => _query.isNotEmpty || _ownershipFilter != null;

  int countOf(EquipmentOwnership o) =>
      _all.where((e) => e.ownership == o).length;

  List<Equipment> get items {
    final q = _query.toLowerCase();
    return [
      for (final e in _all)
        if ((_ownershipFilter == null || e.ownership == _ownershipFilter) &&
            (q.isEmpty || e.name.toLowerCase().contains(q)))
          e,
    ];
  }

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _all = await _masterData.getEquipment();
    } catch (e) {
      _error = 'Could not load the equipment list. $e';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  void setQuery(String value) {
    _query = value.trim();
    notifyListeners();
  }

  void setOwnership(EquipmentOwnership? value) {
    _ownershipFilter = value;
    notifyListeners();
  }

  void clearFilters() {
    _query = '';
    _ownershipFilter = null;
    notifyListeners();
  }

  /// Another entry with the same name (ignoring case and spaces) and the
  /// same ownership, which would show twice in the borrow dropdown.
  Equipment? duplicateOf(Equipment e) {
    final name = e.name.trim().toLowerCase();
    for (final other in _all) {
      if (other.id != e.id &&
          other.ownership == e.ownership &&
          other.name.trim().toLowerCase() == name) {
        return other;
      }
    }
    return null;
  }

  /// Creates (id 0) or updates [e], logs it and reloads. Null on success.
  Future<String?> save(Equipment e) async {
    final dup = duplicateOf(e);
    if (dup != null) {
      return '"${dup.name}" is already on the list as '
          '${dup.ownership.label.toLowerCase()} equipment.';
    }
    return runAction(() async {
      final saved = await _masterData.saveEquipment(e);
      await _audit?.record(
        'equipment_${e.id == 0 ? 'created' : 'updated'}',
        entity: 'equipment',
        entityId: saved.id,
        details: {'name': saved.name},
      );
      _all = await _masterData.getEquipment();
    });
  }
}

import 'package:flutter/foundation.dart' show ChangeNotifier;

import '../../../core/utils/action_runner.dart';
import '../../../data/models/client.dart';
import '../../../data/models/equipment.dart';
import '../../../data/models/material_item.dart';
import '../../../data/models/supplier.dart';
import '../../../data/models/trade.dart';
import '../../../data/repositories/client_repository.dart';
import '../../../data/repositories/master_data_repository.dart';
import 'admin_audit.dart';

class MasterListsViewModel extends ChangeNotifier with ActionRunner {
  MasterListsViewModel({
    required MasterDataRepository masterData,
    required ClientRepository clients,
    AdminAudit? audit,
  }) : _masterData = masterData,
       _clientRepo = clients,
       _audit = audit;

  final MasterDataRepository _masterData;
  final AdminAudit? _audit;
  final ClientRepository _clientRepo;

  bool _loading = true;
  String? _error;
  List<MaterialItem> materials = const [];
  List<Supplier> suppliers = const [];
  List<Trade> trades = const [];
  List<Client> clients = const [];
  List<Equipment> equipment = const [];

  bool get isLoading => _loading;
  String? get error => _error;

  Future<void> load() async {
    try {
      await _refresh();
    } catch (e) {
      _error = 'Could not load master lists. $e';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> _refresh() async {
    materials = await _masterData.getMaterials();
    suppliers = await _masterData.getSuppliers();
    trades = await _masterData.getTrades();
    clients = await _clientRepo.getClients();
    equipment = await _masterData.getEquipment();
  }

  /// Runs [action], logs it as `<entity>_<verb>` and reloads the lists.
  /// The verb is "created" for a new record (id 0) unless [verb] is given.
  Future<String?> _save(
    Future<Object?> Function() action, {
    required String entity,
    required int id,
    required String name,
    String? verb,
  }) => runAction(() async {
    await action();
    await _audit?.record(
      '${entity}_${verb ?? (id == 0 ? 'created' : 'updated')}',
      entity: entity,
      entityId: id,
      details: {'name': name},
    );
    await _refresh();
  });

  Future<String?> saveMaterial(MaterialItem m) => _save(
    () => _masterData.saveMaterial(m),
    entity: 'material',
    id: m.id,
    name: m.name,
  );

  Future<String?> saveSupplier(Supplier s) => _save(
    () => _masterData.saveSupplier(s),
    entity: 'supplier',
    id: s.id,
    name: s.name,
  );

  Future<String?> saveTrade(Trade t) => _save(
    () => _masterData.saveTrade(t),
    entity: 'trade',
    id: t.id,
    name: t.name,
  );

  Future<String?> deleteTrade(Trade t) => _save(
    () => _masterData.deleteTrade(t.id),
    entity: 'trade',
    id: t.id,
    name: t.name,
    verb: 'deleted',
  );

  Future<String?> saveClient(Client c) => _save(
    () => _clientRepo.saveClient(c),
    entity: 'client',
    id: c.id,
    name: c.name,
  );

  Future<String?> saveEquipment(Equipment e) => _save(
    () => _masterData.saveEquipment(e),
    entity: 'equipment',
    id: e.id,
    name: e.name,
  );
}

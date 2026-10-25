import 'package:flutter/foundation.dart' show ChangeNotifier;

import '../../../core/utils/action_runner.dart';
import '../../../data/models/client.dart';
import '../../../data/models/equipment.dart';
import '../../../data/models/material_item.dart';
import '../../../data/models/supplier.dart';
import '../../../data/models/trade.dart';
import '../../../data/repositories/client_repository.dart';
import '../../../data/repositories/master_data_repository.dart';

class MasterListsViewModel extends ChangeNotifier with ActionRunner {
  MasterListsViewModel({
    required MasterDataRepository masterData,
    required ClientRepository clients,
  }) : _masterData = masterData,
       _clientRepo = clients;

  final MasterDataRepository _masterData;
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

  Future<String?> _save(Future<Object?> Function() action) =>
      runAction(() async {
        await action();
        await _refresh();
      });

  Future<String?> saveMaterial(MaterialItem m) =>
      _save(() => _masterData.saveMaterial(m));

  Future<String?> saveSupplier(Supplier s) =>
      _save(() => _masterData.saveSupplier(s));

  Future<String?> saveTrade(Trade t) => _save(() => _masterData.saveTrade(t));

  Future<String?> deleteTrade(Trade t) =>
      _save(() => _masterData.deleteTrade(t.id));

  Future<String?> saveClient(Client c) =>
      _save(() => _clientRepo.saveClient(c));

  Future<String?> saveEquipment(Equipment e) =>
      _save(() => _masterData.saveEquipment(e));
}

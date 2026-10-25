import '../models/equipment.dart';
import '../models/material_item.dart';
import '../models/supplier.dart';
import '../models/trade.dart';
import '../services/business_rule_exception.dart';
import '../services/master_data_rules.dart';
import 'master_data_repository.dart';
import 'mock_company_data.dart';

class MockMasterDataRepository implements MasterDataRepository {
  final _materials = [...MockCompanyData.materials];
  final _suppliers = [...MockCompanyData.suppliers];
  final _trades = [...MockCompanyData.trades];
  final _equipment = [...MockCompanyData.equipment];

  @override
  Future<List<MaterialItem>> getMaterials() async =>
      [..._materials]..sort((a, b) => a.name.compareTo(b.name));

  @override
  Future<MaterialItem> saveMaterial(MaterialItem material) async {
    MasterDataRules.enforce(
      MasterDataRules.required(material.name, 'material name'),
    );
    MasterDataRules.enforce(MasterDataRules.required(material.unit, 'unit'));
    MasterDataRules.enforce(
      MasterDataRules.validateAmount(material.defaultUnitCost, 'unit cost'),
    );
    _ensureUnique(
      _materials.where((m) => m.id != material.id).map((m) => m.name),
      material.name,
      'A material with this name already exists.',
    );
    final saved = material.copyWith(
      id: material.id == 0 ? _nextId(_materials.map((m) => m.id)) : null,
      name: material.name.trim(),
      unit: material.unit.trim(),
      updatedAt: DateTime.now(),
    );
    _upsert(_materials, saved, (m) => m.id);
    return saved;
  }

  @override
  Future<List<Supplier>> getSuppliers() async => [..._suppliers]
    ..sort((a, b) {
      if (a.isOwnStore != b.isOwnStore) return a.isOwnStore ? -1 : 1;
      return a.name.compareTo(b.name);
    });

  @override
  Future<Supplier> saveSupplier(Supplier supplier) async {
    MasterDataRules.enforce(
      MasterDataRules.required(supplier.name, 'supplier name'),
    );
    _ensureUnique(
      _suppliers.where((s) => s.id != supplier.id).map((s) => s.name),
      supplier.name,
      'A supplier with this name already exists.',
    );
    final saved = supplier.copyWith(
      id: supplier.id == 0 ? _nextId(_suppliers.map((s) => s.id)) : null,
      name: supplier.name.trim(),
      updatedAt: DateTime.now(),
    );
    _upsert(_suppliers, saved, (s) => s.id);
    return saved;
  }

  @override
  Future<List<Trade>> getTrades() async =>
      [..._trades]..sort((a, b) => a.name.compareTo(b.name));

  @override
  Future<Trade> saveTrade(Trade trade) async {
    MasterDataRules.enforce(MasterDataRules.required(trade.name, 'trade name'));
    _ensureUnique(
      _trades.where((t) => t.id != trade.id).map((t) => t.name),
      trade.name,
      'This trade is already listed.',
    );
    final saved = Trade(
      id: trade.id == 0 ? _nextId(_trades.map((t) => t.id)) : trade.id,
      name: trade.name.trim(),
      createdAt: trade.createdAt,
      updatedAt: DateTime.now(),
    );
    _upsert(_trades, saved, (t) => t.id);
    return saved;
  }

  @override
  Future<void> deleteTrade(int id) async =>
      _trades.removeWhere((t) => t.id == id);

  @override
  Future<List<Equipment>> getEquipment() async =>
      [..._equipment]..sort((a, b) => a.name.compareTo(b.name));

  @override
  Future<Equipment> saveEquipment(Equipment equipment) async {
    MasterDataRules.enforce(
      MasterDataRules.required(equipment.name, 'equipment name'),
    );
    MasterDataRules.enforce(
      MasterDataRules.validateAmount(equipment.rate, 'rate'),
    );
    final saved = equipment.copyWith(
      id: equipment.id == 0 ? _nextId(_equipment.map((e) => e.id)) : null,
      name: equipment.name.trim(),
      updatedAt: DateTime.now(),
    );
    _upsert(_equipment, saved, (e) => e.id);
    return saved;
  }

  static int _nextId(Iterable<int> ids) =>
      ids.fold(0, (m, id) => id > m ? id : m) + 1;

  static void _ensureUnique(
    Iterable<String> others,
    String name,
    String message,
  ) {
    final n = name.trim().toLowerCase();
    if (others.any((o) => o.toLowerCase() == n)) {
      throw BusinessRuleException(message);
    }
  }

  static void _upsert<T>(List<T> list, T item, int Function(T) idOf) {
    final i = list.indexWhere((e) => idOf(e) == idOf(item));
    if (i < 0) {
      list.add(item);
    } else {
      list[i] = item;
    }
  }
}

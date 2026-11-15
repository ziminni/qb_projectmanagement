import '../models/equipment.dart';
import '../models/material_item.dart';
import '../models/supplier.dart';
import '../models/trade.dart';

/// Admin-maintained lists: materials with unit costs, suppliers, trades and
/// equipment. Each save creates the record when its id is 0.
abstract interface class MasterDataRepository {
  Future<List<MaterialItem>> getMaterials();

  Future<MaterialItem> saveMaterial(MaterialItem material);

  Future<List<Supplier>> getSuppliers();

  Future<Supplier> saveSupplier(Supplier supplier);

  Future<List<Trade>> getTrades();

  Future<Trade> saveTrade(Trade trade);

  Future<void> deleteTrade(int id);

  Future<List<Equipment>> getEquipment();

  Future<Equipment> saveEquipment(Equipment equipment);
}

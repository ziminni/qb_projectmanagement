import '../../core/network/api_client.dart';
import '../models/equipment.dart';
import '../models/material_item.dart';
import '../models/supplier.dart';
import '../models/trade.dart';
import 'master_data_repository.dart';

/// The admin-maintained lists, against the CPMS backend. Saves are `POST` for
/// a new row (id 0) and `PATCH` for an existing one; ids, ordering, uniqueness
/// and the required-field messages are the server's. A save is sent the whole
/// object either way, so a price the server redacted (`0` for a non-finance
/// active role) goes back unchanged and the server keeps the stored figure.
class HttpMasterDataRepository implements MasterDataRepository {
  HttpMasterDataRepository(this._client);

  final ApiClient _client;

  /// Master lists live under `master-data/` so `equipment/` does not collide
  /// with the legacy site-inventory route.
  static const _base = 'master-data';

  @override
  Future<List<MaterialItem>> getMaterials() async => [
    for (final row in await _client.getRows('$_base/materials/'))
      MaterialItem.fromJson(row),
  ];

  @override
  Future<MaterialItem> saveMaterial(MaterialItem material) async =>
      MaterialItem.fromJson(
        jsonObject(
          await _save('materials', material.id, {
            'name': material.name,
            'unit': material.unit,
            'default_unit_cost': material.defaultUnitCost,
            'store_sku': _blankToNull(material.storeSku),
          }),
        ),
      );

  @override
  Future<List<Supplier>> getSuppliers() async => [
    for (final row in await _client.getRows('$_base/suppliers/'))
      Supplier.fromJson(row),
  ];

  @override
  Future<Supplier> saveSupplier(Supplier supplier) async => Supplier.fromJson(
    jsonObject(
      await _save('suppliers', supplier.id, {
        'name': supplier.name,
        'contact_person': supplier.contactPerson,
        'phone': supplier.phone,
        'address': supplier.address,
        'is_own_store': supplier.isOwnStore,
      }),
    ),
  );

  @override
  Future<List<Trade>> getTrades() async => [
    for (final row in await _client.getRows('$_base/trades/'))
      Trade.fromJson(row),
  ];

  @override
  Future<Trade> saveTrade(Trade trade) async => Trade.fromJson(
    jsonObject(await _save('trades', trade.id, {'name': trade.name})),
  );

  /// Trades are the only list with a delete; the server hard-deletes and
  /// answers `204`.
  @override
  Future<void> deleteTrade(int id) async {
    await _client.delete('$_base/trades/$id/');
  }

  @override
  Future<List<Equipment>> getEquipment() async => [
    for (final row in await _client.getRows('$_base/equipment/'))
      Equipment.fromJson(row),
  ];

  @override
  Future<Equipment> saveEquipment(Equipment equipment) async =>
      Equipment.fromJson(
        jsonObject(
          await _save('equipment', equipment.id, {
            'name': equipment.name,
            'ownership': equipment.ownership.toJson(),
            'rate': equipment.rate,
            'rate_unit': equipment.rateUnit.toJson(),
          }),
        ),
      );

  Future<Object?> _save(String list, int id, Map<String, dynamic> body) =>
      id == 0
      ? _client.post('$_base/$list/', body: body)
      : _client.patch('$_base/$list/$id/', body: body);

  /// A blank SKU is a `null` on the wire; the model treats null as "none".
  static String? _blankToNull(String? value) {
    final trimmed = value?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }
}

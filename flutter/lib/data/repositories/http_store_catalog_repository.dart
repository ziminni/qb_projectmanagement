import '../../core/network/api_client.dart';
import '../models/json_utils.dart';
import '../models/store_product.dart';
import 'store_catalog_repository.dart';

/// The company store's catalog, read from the server's master data.
///
/// Only a material with a POS `pos_code` can be ordered for the own store
/// (`apps/requisitions/procurement_services.py` refuses the rest), so the
/// unmapped rows are left out. The master list has no name, category or stock
/// field and no query filter, so the search happens here, and a price the
/// server hid from this role stays `null` — never `0`, and never a POS figure.
class HttpStoreCatalogRepository implements StoreCatalogRepository {
  HttpStoreCatalogRepository(this._client);

  final ApiClient _client;

  static const _materials = 'master-data/materials/';

  @override
  Future<List<StoreProduct>> getProducts({
    String? query,
    String? category,
  }) async {
    // The master list keeps no category, so no category filter can match.
    if (category != null) return const [];
    final q = query?.trim().toLowerCase() ?? '';
    return [
      for (final row in await _client.getRows(_materials))
        if (_sellsInStore(row) && _matches(row, q)) _product(row),
    ];
  }

  @override
  Future<List<String>> getCategories() async => const [];

  /// Rows are read here rather than through `MaterialItem` because the search
  /// needs `pos_code`/`store_sku`, which the model does not keep.
  static bool _sellsInStore(Map<String, dynamic> row) =>
      _text(row['pos_code']).isNotEmpty;

  static bool _matches(Map<String, dynamic> row, String query) =>
      query.isEmpty ||
      _text(row['name']).toLowerCase().contains(query) ||
      _text(row['store_sku']).toLowerCase().contains(query) ||
      _text(row['pos_code']).toLowerCase().contains(query);

  StoreProduct _product(Map<String, dynamic> row) => StoreProduct(
    sku: _text(row['store_sku']).isEmpty
        ? _text(row['pos_code'])
        : _text(row['store_sku']),
    name: _text(row['name']),
    unit: _text(row['unit']),
    price: _client.seesFinance
        ? JsonUtils.toDouble(row['default_unit_cost'])
        : null,
    materialId: row['id'] as int,
  );

  static String _text(Object? value) => (value as String?)?.trim() ?? '';
}

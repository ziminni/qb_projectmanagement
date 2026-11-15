import '../../core/network/api_client.dart';
import '../models/json_utils.dart';
import '../models/store_product.dart';
import '../services/business_rule_exception.dart';
import 'store_catalog_repository.dart';

/// The company store's catalog.
///
/// The store owns its prices and stock, so the catalogue is read **live** from
/// it through the CPMS server (`pos-catalog/`, the service account): the store's
/// price and a coarse stock status, joined to the CPMS material id the order
/// line needs. If the store cannot be reached the list falls back to the server's
/// master data with [StoreProduct.fromStore] false and no price, so a CPMS
/// planning cost is never shown as the store's price.
///
/// In the fallback only a material with a POS `pos_code` can be ordered for the own store
/// (`apps/requisitions/procurement_services.py` refuses the rest), so the
/// unmapped rows are left out. The master list has no name, category or stock
/// field and no query filter, so the search happens here, and a price the
/// server hid from this role stays `null` — never `0`, and never a POS figure.
class HttpStoreCatalogRepository implements StoreCatalogRepository {
  HttpStoreCatalogRepository(this._client, {this.live = true});

  final ApiClient _client;

  /// False skips the store and serves the master list only (tests, and a build
  /// with no store configured).
  final bool live;

  static const _materials = 'master-data/materials/';

  @override
  Future<List<StoreProduct>> getProducts({
    String? query,
    String? category,
  }) async {
    // Neither source keeps a category, so no category filter can match.
    if (category != null) return const [];
    final q = query?.trim().toLowerCase() ?? '';
    if (live) {
      try {
        return await _fromStore(q);
      } on BusinessRuleException {
        // The store is down or not set up: fall through to the master list.
      }
    }
    return [
      for (final row in await _client.getRows(_materials))
        if (_sellsInStore(row) && _matches(row, q)) _product(row),
    ];
  }

  /// Only an item a CPMS material points at can be ordered, so the rest are
  /// left out of the picker.
  Future<List<StoreProduct>> _fromStore(String query) async => [
    for (final row in await _client.getRows('pos-catalog/'))
      if (row['material_id'] is int && _storeMatches(row, query))
        StoreProduct(
          sku: _text(row['code']),
          name: _text(row['product']),
          unit: _text(row['unit']),
          // Unknown stays null: a price the store did not give is not free.
          price: row['price'] == null ? null : JsonUtils.toDouble(row['price']),
          stockStatus: StoreStock.fromApi(row['stock_status']),
          materialId: row['material_id'] as int,
        ),
  ];

  static bool _storeMatches(Map<String, dynamic> row, String query) =>
      query.isEmpty ||
      _text(row['product']).toLowerCase().contains(query) ||
      _text(row['code']).toLowerCase().contains(query);

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
    // The store's price is the real price and the store was not reachable, so
    // none is shown; the CPMS planning cost is not the store's price.
    materialId: row['id'] as int,
    fromStore: false,
  );

  static String _text(Object? value) => (value as String?)?.trim() ?? '';
}

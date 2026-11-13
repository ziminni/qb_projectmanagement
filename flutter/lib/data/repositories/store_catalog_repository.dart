import '../models/store_product.dart';

/// The company hardware store's catalog. The mock stands in for the POS
/// API until the two systems are connected.
abstract interface class StoreCatalogRepository {
  /// Every product, optionally narrowed by [query] (name or SKU) and
  /// [category].
  Future<List<StoreProduct>> getProducts({String? query, String? category});

  Future<List<String>> getCategories();
}

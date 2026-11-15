import '../models/store_product.dart';
import 'store_catalog_repository.dart';

class MockStoreCatalogRepository implements StoreCatalogRepository {
  static const _products = [
    StoreProduct(
      sku: 'CEM-40',
      name: 'Portland cement 40 kg',
      unit: 'bag',
      price: 260,
      category: 'Cement and aggregates',
      stock: 540,
      materialId: 1,
    ),
    StoreProduct(
      sku: 'RB-10',
      name: 'Deformed bar 10 mm × 6 m',
      unit: 'pc',
      price: 230,
      category: 'Steel',
      stock: 820,
      materialId: 2,
    ),
    StoreProduct(
      sku: 'RB-12',
      name: 'Deformed bar 12 mm × 6 m',
      unit: 'pc',
      price: 330,
      category: 'Steel',
      stock: 410,
      materialId: 3,
    ),
    StoreProduct(
      sku: 'TW-16',
      name: 'Tie wire #16',
      unit: 'kg',
      price: 95,
      category: 'Steel',
      stock: 260,
      materialId: 9,
    ),
    StoreProduct(
      sku: 'CHB-4',
      name: 'CHB 4"',
      unit: 'pc',
      price: 18,
      category: 'Masonry',
      stock: 3200,
      materialId: 6,
    ),
    StoreProduct(
      sku: 'PLY-12',
      name: 'Marine plywood 1/2"',
      unit: 'sheet',
      price: 750,
      category: 'Lumber and plywood',
      stock: 95,
      materialId: 7,
    ),
    StoreProduct(
      sku: 'TA-25',
      name: 'Tile adhesive 25 kg',
      unit: 'bag',
      price: 380,
      category: 'Finishing',
      stock: 120,
      materialId: 12,
    ),
  ];

  @override
  Future<List<StoreProduct>> getProducts({
    String? query,
    String? category,
  }) async {
    final q = query?.trim().toLowerCase() ?? '';
    return [
      for (final p in _products)
        if ((category == null || p.category == category) &&
            (q.isEmpty ||
                p.name.toLowerCase().contains(q) ||
                p.sku.toLowerCase().contains(q)))
          p,
    ];
  }

  @override
  Future<List<String>> getCategories() async =>
      {
        for (final p in _products)
          if (p.category != null) p.category!,
      }.toList()..sort();
}

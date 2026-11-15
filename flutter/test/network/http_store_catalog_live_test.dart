import 'package:buildpro_frontend/data/models/store_product.dart';
import 'package:buildpro_frontend/data/repositories/http_store_catalog_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_api.dart';

/// One `pos-catalog/` row, shaped like `pos_catalog_view`.
Map<String, dynamic> storeRow(
  String code, {
  String product = 'Portland Cement 40kg',
  String unit = 'BAG',
  Object? price = '275.00',
  Object? stock = 'low',
  int? materialId = 41,
}) => {
  'code': code,
  'product': product,
  'unit': unit,
  'price': price,
  'stock_status': stock,
  'material_id': materialId,
};

HttpStoreCatalogRepository repo(FakeApi api) => HttpStoreCatalogRepository(
  testClient(api: api, tokens: InMemoryTokenStore()),
);

void main() {
  group('live store catalogue', () {
    test('shows the store price and stock status under the CPMS id', () async {
      final api = FakeApi(
        (o) => o.path == 'pos-catalog/'
            ? json([
                storeRow('QB000001-7'),
                storeRow(
                  'QB000010-9',
                  product: 'Tile Adhesive 25kg',
                  price: '410.50',
                  stock: 'in_stock',
                  materialId: 42,
                ),
              ])
            : throw StateError('only the store should be asked: ${o.path}'),
      );

      final products = await repo(api).getProducts();

      expect([for (final p in products) p.materialId], [41, 42]);
      final cement = products.first;
      expect(cement.sku, 'QB000001-7');
      expect(cement.price, 275);
      expect(cement.stockStatus, StoreStock.low);
      expect(cement.fromStore, isTrue);
      expect(products.last.price, 410.5);
      expect(products.last.stockStatus, StoreStock.inStock);
    });

    test(
      'an item no CPMS material points at is not offered for ordering',
      () async {
        final api = FakeApi(
          (o) => json([
            storeRow('QB000001-7'),
            storeRow('NAIL-4', materialId: null),
          ]),
        );

        final products = await repo(api).getProducts();

        expect([for (final p in products) p.sku], ['QB000001-7']);
      },
    );

    test(
      'an unknown price or status is unknown, never free or in stock',
      () async {
        final api = FakeApi(
          (o) => json([storeRow('QB000001-7', price: null, stock: '??')]),
        );

        final product = (await repo(api).getProducts()).single;

        expect(product.price, isNull);
        expect(product.stockStatus, isNull);
      },
    );

    test('a real store price of zero stays zero', () async {
      final api = FakeApi((o) => json([storeRow('QB000001-7', price: '0.00')]));

      expect((await repo(api).getProducts()).single.price, 0);
    });

    test('searches the product name and code here', () async {
      final api = FakeApi(
        (o) => json([
          storeRow('QB000001-7'),
          storeRow('QB000010-9', product: 'Tile Adhesive 25kg', materialId: 42),
        ]),
      );

      expect(
        [
          for (final p in await repo(api).getProducts(query: 'tile'))
            p.materialId,
        ],
        [42],
      );
      expect(
        [
          for (final p in await repo(api).getProducts(query: 'qb000001'))
            p.materialId,
        ],
        [41],
      );
    });

    test(
      'a store that cannot be reached falls back to the master list, priceless',
      () async {
        final api = FakeApi((o) {
          if (o.path == 'pos-catalog/') {
            return json({
              'detail':
                  'The store could not be reached. Try again in a moment.',
            }, status: 502);
          }
          return json({
            'count': 1,
            'next': null,
            'results': [
              {
                'id': 41,
                'name': 'Portland cement 40 kg',
                'unit': 'bag',
                'default_unit_cost': 260,
                'store_sku': 'CEM-40',
                'pos_code': 'QB000001-7',
                'created_at': '2026-01-01T00:00:00Z',
                'updated_at': '2026-01-02T00:00:00Z',
              },
            ],
          });
        });

        final product = (await repo(api).getProducts()).single;

        expect(product.materialId, 41);
        expect(product.fromStore, isFalse);
        expect(
          product.price,
          isNull,
          reason: 'the CPMS cost is not the store price',
        );
        expect(product.stockStatus, isNull);
      },
    );
  });
}

import 'package:buildpro_frontend/core/network/api_config.dart';
import 'package:buildpro_frontend/data/models/app_role.dart';
import 'package:buildpro_frontend/data/repositories/http_store_catalog_repository.dart';
import 'package:buildpro_frontend/data/services/business_rule_exception.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_api.dart';

/// One `master-data/materials/` row, shaped like `MaterialItemSerializer`.
Map<String, dynamic> materialRow(
  int id, {
  String name = 'Cement',
  String unit = 'bag',
  num cost = 260,
  String? storeSku,
  String? posCode,
}) => {
  'id': id,
  'name': name,
  'unit': unit,
  'default_unit_cost': cost,
  'store_sku': storeSku,
  'pos_code': posCode,
  'created_at': '2026-01-01T00:00:00Z',
  'updated_at': '2026-01-02T00:00:00Z',
};

HttpStoreCatalogRepository storeCatalog({
  required FakeApi api,
  AppRole active = AppRole.owner,
}) => HttpStoreCatalogRepository(
  testClient(
    api: api,
    tokens: InMemoryTokenStore(),
    session: signedInSession(roles: [active], active: active),
  ),
  // These tests are about the master-list fallback; the live store has its own
  // file (http_store_catalog_live_test.dart).
  live: false,
);

void main() {
  group('http store catalog repository', () {
    test('serves the POS-mapped materials under their server ids', () async {
      final api = FakeApi(
        (options) => json({
          'count': 3,
          'next': null,
          'results': [
            materialRow(
              41,
              name: 'Portland cement 40 kg',
              storeSku: 'CEM-40',
              posCode: 'QB000001',
            ),
            materialRow(
              42,
              name: 'Tie wire #16',
              unit: 'kg',
              cost: 95,
              posCode: 'QB000002',
            ),
            materialRow(43, name: 'Washed sand', unit: 'cu.m', cost: 900),
          ],
        }),
      );

      final products = await storeCatalog(api: api).getProducts();

      expect([for (final p in products) p.materialId], [41, 42]);
      final cement = products.first;
      expect(cement.name, 'Portland cement 40 kg');
      expect(cement.sku, 'CEM-40');
      expect(cement.unit, 'bag');
      // The store's price is the real price and the store was not asked, so
      // the CPMS planning cost (260) is never shown as the store's price.
      expect(cement.price, isNull);
      expect(cement.fromStore, isFalse);
      // The master list keeps no shelf count and no category: none is invented.
      expect(cement.stock, isNull);
      expect(cement.category, isNull);
      // A material with no POS code cannot be ordered for the own store.
      expect(products.any((p) => p.materialId == 43), isFalse);
      // No store SKU: the POS code names the product.
      expect(products.last.sku, 'QB000002');
    });

    test('follows the master-list pages', () async {
      final api = FakeApi((options) {
        final second = options.uri.queryParameters['page'] == '2';
        return json({
          'count': 2,
          'next': second ? null : '$apiBaseUrl/master-data/materials/?page=2',
          'results': [
            if (!second) materialRow(41, name: 'Cement', posCode: 'QB000001'),
            if (second) materialRow(42, name: 'Tie wire', posCode: 'QB000002'),
          ],
        });
      });

      final products = await storeCatalog(api: api).getProducts();

      expect([for (final p in products) p.materialId], [41, 42]);
    });

    test(
      'searches name and SKU here, because the route has no filter',
      () async {
        final api = FakeApi(
          (options) => json({
            'count': 2,
            'next': null,
            'results': [
              materialRow(
                41,
                name: 'Portland cement 40 kg',
                storeSku: 'CEM-40',
                posCode: 'QB000001',
              ),
              materialRow(
                42,
                name: 'Tie wire #16',
                unit: 'kg',
                cost: 95,
                posCode: 'QB000002',
              ),
            ],
          }),
        );
        final repo = storeCatalog(api: api);

        expect(
          [for (final p in await repo.getProducts(query: 'tie')) p.materialId],
          [42],
        );
        expect(
          [
            for (final p in await repo.getProducts(query: 'cem-40'))
              p.materialId,
          ],
          [41],
        );
        expect(
          [for (final p in await repo.getProducts(query: '  ')) p.materialId],
          [41, 42],
        );
        // The master list has no categories, so no category filter can match.
        expect(await repo.getProducts(category: 'Steel'), isEmpty);
        expect(await repo.getCategories(), isEmpty);
      },
    );

    test('no role sees a CPMS cost as the store price', () async {
      final api = FakeApi(
        (options) => json({
          'count': 1,
          'next': null,
          'results': [
            materialRow(
              41,
              name: 'Portland cement 40 kg',
              cost: 260,
              storeSku: 'CEM-40',
              posCode: 'QB000001',
            ),
          ],
        }),
      );

      for (final role in [AppRole.owner, AppRole.siteEngineer]) {
        final products = await storeCatalog(
          api: api,
          active: role,
        ).getProducts();
        expect(products.single.price, isNull, reason: '$role');
      }
    });

    test('an empty master list is an empty catalogue', () async {
      final api = FakeApi(
        (options) => json({'count': 0, 'next': null, 'results': <Object>[]}),
      );

      expect(await storeCatalog(api: api).getProducts(), isEmpty);
    });

    test('a refused read shows the server message', () async {
      final api = FakeApi(
        (options) => json({
          'detail': 'Only the admin can edit master data.',
        }, status: 400),
      );
      final repo = storeCatalog(api: api);

      await expectLater(
        repo.getProducts(),
        throwsA(
          isA<BusinessRuleException>().having(
            (e) => e.message,
            'message',
            'Only the admin can edit master data.',
          ),
        ),
      );
    });

    test('a forbidden read is not shown as an empty catalogue', () async {
      final api = FakeApi(
        (options) => json({'detail': 'Forbidden.'}, status: 403),
      );

      await expectLater(
        storeCatalog(api: api).getProducts(),
        throwsA(
          isA<BusinessRuleException>().having(
            (e) => e.message,
            'message',
            'Forbidden.',
          ),
        ),
      );
    });
  });
}

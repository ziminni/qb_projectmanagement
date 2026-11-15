import 'package:buildpro_frontend/core/di/service_locator.dart';
import 'package:buildpro_frontend/data/models/app_role.dart';
import 'package:buildpro_frontend/data/models/material_source.dart';
import 'package:buildpro_frontend/data/repositories/http_store_catalog_repository.dart';
import 'package:buildpro_frontend/data/repositories/mock_store_catalog_repository.dart';
import 'package:buildpro_frontend/data/services/session_service.dart';
import 'package:buildpro_frontend/features/procurement/viewmodels/order_form_viewmodel.dart';
import 'package:buildpro_frontend/features/procurement/viewmodels/procurement_lookups.dart';
import 'package:flutter_test/flutter_test.dart';

import 'network/fake_api.dart';
import 'test_helpers.dart';

/// A master-data row the own store can sell (`pos_code` present).
Map<String, dynamic> cementRow({int id = 41, num cost = 260}) => {
  'id': id,
  'name': 'Portland cement 40 kg',
  'unit': 'bag',
  'default_unit_cost': cost,
  'store_sku': 'CEM-40',
  'pos_code': 'QB000001',
  'created_at': '2026-01-01T00:00:00Z',
  'updated_at': '2026-01-02T00:00:00Z',
};

void main() {
  setUp(resetServices);

  test('an own-store line carries the server material id', () async {
    final api = FakeApi(
      (options) => json({
        'count': 1,
        'next': null,
        'results': [cementRow(id: 9001)],
      }),
    );
    final catalog = HttpStoreCatalogRepository(
      testClient(
        api: api,
        tokens: InMemoryTokenStore(),
        session: signedInSession(roles: const [AppRole.owner], active: AppRole.owner),
      ),
    );
    final vm = OrderFormViewModel(
      requestId: 1,
      source: MaterialSource.ownStore,
      session: getIt<SessionService>(),
      procurement: getIt(),
      catalog: catalog,
      lookups: ProcurementLookups.fromServices(),
    );

    final product = (await catalog.getProducts()).single;
    vm.addProduct(product);

    expect(product.materialId, 9001);
    expect(vm.lines.single.materialId, 9001);
    expect(vm.lines.single.toOrderLine().materialId, 9001);
    expect(vm.lines.single.unitPrice, 260);
    expect(vm.isPicked(product), isTrue);
  });

  test('mock mode keeps the demo catalogue', () async {
    final products = await MockStoreCatalogRepository().getProducts();

    expect(products.first.sku, 'CEM-40');
    expect(products.first.price, 260);
    expect(products.first.materialId, 1);
    expect(await MockStoreCatalogRepository().getCategories(), isNotEmpty);
  });
}

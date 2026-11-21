import 'package:buildpro_frontend/core/di/service_locator.dart';
import 'package:buildpro_frontend/data/models/app_role.dart';
import 'package:buildpro_frontend/data/models/material_request.dart';
import 'package:buildpro_frontend/data/models/material_request_item.dart';
import 'package:buildpro_frontend/data/models/material_source.dart';
import 'package:buildpro_frontend/data/models/store_product.dart';
import 'package:buildpro_frontend/data/repositories/http_store_catalog_repository.dart';
import 'package:buildpro_frontend/data/repositories/mock_audit_log_repository.dart';
import 'package:buildpro_frontend/data/repositories/mock_procurement_repository.dart';
import 'package:buildpro_frontend/data/repositories/mock_store_catalog_repository.dart';
import 'package:buildpro_frontend/data/repositories/procurement_repository.dart';
import 'package:buildpro_frontend/data/repositories/store_catalog_repository.dart';
import 'package:buildpro_frontend/data/services/session_service.dart';
import 'package:buildpro_frontend/features/procurement/viewmodels/order_form_viewmodel.dart';
import 'package:buildpro_frontend/features/procurement/viewmodels/procurement_lookups.dart';
import 'package:buildpro_frontend/features/procurement/widgets/procurement_line_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'network/fake_api.dart';
import 'test_helpers.dart';

/// A catalogue that serves exactly [products].
class FixedCatalog implements StoreCatalogRepository {
  FixedCatalog(this.products);

  final List<StoreProduct> products;

  @override
  Future<List<StoreProduct>> getProducts({
    String? query,
    String? category,
  }) async => products;

  @override
  Future<List<String>> getCategories() async => const [];
}

/// A request whose items are [items], as the engineer typed them.
class AskedRequestProcurement extends MockProcurementRepository {
  AskedRequestProcurement(this.items)
    : super(
        projects: getIt(),
        schedule: getIt(),
        masterData: getIt(),
        reports: getIt(),
        users: getIt(),
        auditLog: MockAuditLogRepository(),
      );

  final List<MaterialRequestItem> items;

  @override
  Future<MaterialRequestDetail?> getRequest(int id) async =>
      MaterialRequestDetail(
        MaterialRequest(
          id: id,
          projectId: 1,
          requestedBy: 4,
          neededBy: DateTime(2026, 11, 18),
          status: MaterialRequestStatus.pending,
        ),
        items,
        const [],
      );
}

/// The server catalogue row QA used: same words as the request line.
const cementProduct = StoreProduct(
  sku: 'CEM-40',
  name: 'Portland cement 40 kg',
  unit: 'bag',
  price: 260,
  materialId: 1,
);

MaterialRequestItem askedCement({String unit = 'bag', double quantity = 20}) =>
    MaterialRequestItem(
      id: 1,
      materialRequestId: 1,
      description: 'Portland cement 40 kg',
      unit: unit,
      quantity: quantity,
    );

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
      (options) => json([
        {
          'code': 'CEM-40',
          'product': 'Portland cement 40 kg',
          'unit': 'bag',
          'price': '260.00',
          'stock_status': 'in_stock',
          'material_id': 9001,
        },
      ]),
    );
    final catalog = HttpStoreCatalogRepository(
      testClient(
        api: api,
        tokens: InMemoryTokenStore(),
        session: signedInSession(
          roles: const [AppRole.owner],
          active: AppRole.owner,
        ),
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

  group('own-store prefill from the request line', () {
    OrderFormViewModel vmFor(
      List<StoreProduct> products,
      List<MaterialRequestItem> items,
    ) => OrderFormViewModel(
      requestId: 1,
      source: MaterialSource.ownStore,
      session: getIt<SessionService>()
        ..signIn(testUser, const [AppRole.owner], activeRole: AppRole.owner),
      procurement: AskedRequestProcurement(items),
      catalog: FixedCatalog(products),
      lookups: ProcurementLookups.fromServices(),
    );

    test('a matching request line fills qty and price', () async {
      final vm = vmFor([cementProduct], [askedCement()]);
      await vm.load();

      vm.addProduct(cementProduct);

      expect(vm.lines.single.quantity, 20);
      expect(vm.lines.single.unitPrice, 260);
      expect(vm.total, 5200);
    });

    test('a hidden price leaves the price blank, never 0', () async {
      const noPrice = StoreProduct(
        sku: 'CEM-40',
        name: 'Portland cement 40 kg',
        unit: 'bag',
        materialId: 1,
      );
      final vm = vmFor([noPrice], [askedCement()]);
      await vm.load();

      vm.addProduct(noPrice);

      expect(vm.lines.single.quantity, 20);
      expect(vm.lines.single.priceHidden, isTrue);
    });

    test('units that do not match leave the qty for the owner', () async {
      final vm = vmFor([cementProduct], [askedCement(unit: 'bags')]);
      await vm.load();

      vm.addProduct(cementProduct);

      expect(vm.lines.single.quantity, 0);
      expect(vm.lines.single.unitPrice, 260);
    });

    test('added twice: what the owner typed is not overwritten', () async {
      final vm = vmFor([cementProduct], [askedCement()]);
      await vm.load();
      vm.addProduct(cementProduct);
      // The owner corrects the prefilled numbers.
      vm.lines.single
        ..quantity = 15
        ..unitPrice = 250;
      vm.changed();

      vm.addProduct(cementProduct);

      expect(vm.lines, hasLength(1));
      expect(vm.lines.single.quantity, 15);
      expect(vm.lines.single.unitPrice, 250);
    });

    test('mock mode keeps its own lines: no qty prefill', () async {
      final vm = vmFor(
        await MockStoreCatalogRepository().getProducts(),
        (await getIt<ProcurementRepository>().getRequest(1))!.items,
      );
      await vm.load();
      final cement = (await MockStoreCatalogRepository().getProducts()).first;

      vm.addProduct(cement);

      expect(vm.lines.single.quantity, 0);
      expect(vm.lines.single.unitPrice, 260);
    });

    testWidgets('the editor shows the prefilled numbers, not blanks', (
      tester,
    ) async {
      final vm = vmFor([cementProduct], [askedCement()]);
      await vm.load();
      vm.addProduct(cementProduct);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Form(
              child: ProcurementLineEditor(
                line: vm.lines.single,
                nameLabel: 'Product',
                fixedName: true,
                showPrice: true,
                onChanged: vm.changed,
                onRemove: () {},
              ),
            ),
          ),
        ),
      );

      expect(find.text('20'), findsOneWidget);
      expect(find.text('260'), findsOneWidget);
      expect(find.text('₱5,200.00'), findsOneWidget);
    });
  });

  group('matching a requested item to a store product', () {
    const nails = StoreProduct(
      sku: 'NAIL-4',
      name: 'Common Nail 4in',
      unit: 'KG',
      price: 95.5,
      materialId: 2,
    );
    MaterialRequestItem askedNails() => const MaterialRequestItem(
      id: 2,
      materialRequestId: 1,
      description: 'nails 4 inch',
      unit: 'kg',
      quantity: 3,
    );

    Future<OrderFormViewModel> loaded() async {
      final vm = OrderFormViewModel(
        requestId: 1,
        source: MaterialSource.ownStore,
        session: getIt<SessionService>()
          ..signIn(testUser, const [AppRole.owner], activeRole: AppRole.owner),
        procurement: AskedRequestProcurement([
          askedCement(unit: 'bags'),
          askedNails(),
        ]),
        catalog: FixedCatalog([nails, cementProduct]),
        lookups: ProcurementLookups.fromServices(),
      );
      await vm.load();
      // The mock owner is not on project 1, so load() stops before the
      // catalogue; read it directly.
      await vm.reloadCatalog();
      return vm;
    }

    test('match fills qty from the request and the store price, and covers '
        'the item', () async {
      final vm = await loaded();

      vm.match(askedCement(unit: 'bags'), cementProduct);

      final line = vm.matchFor(1)!;
      expect(line.quantity, 20);
      expect(line.unit, 'bag');
      expect(line.unitPrice, 260);
      expect(line.materialId, 1);
      expect(vm.covers, {1});
      expect(vm.lines, [line]);
      expect(vm.total, 5200);
    });

    test('re-matching replaces the earlier product: one line, one cover', () async {
      final vm = await loaded();
      vm.match(askedCement(), nails);

      vm.match(askedCement(), cementProduct);

      expect(vm.lines, hasLength(1));
      expect(vm.lines.single.materialId, 1);
      expect(vm.covers, {1});
    });

    test('unmatch removes the line and the cover', () async {
      final vm = await loaded();
      vm.match(askedCement(), cementProduct);
      vm.match(askedNails(), nails);

      vm.unmatch(1);

      expect(vm.matchFor(1), isNull);
      expect(vm.lines.single.materialId, 2);
      expect(vm.covers, {2});
    });

    test('rankFor puts the closest product first', () async {
      final vm = await loaded();

      expect(vm.rankFor('portland cement').first, cementProduct);
      expect(vm.rankFor('nails 4').first, nails);
      expect(vm.rankFor(''), hasLength(2));
    });

    testWidgets('a locked price is shown as text, not a field', (tester) async {
      final vm = await loaded();
      vm.match(askedCement(), cementProduct);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Form(
              child: ProcurementLineEditor(
                line: vm.lines.single,
                nameLabel: 'Product',
                fixedName: true,
                showPrice: true,
                lockPrice: true,
                onChanged: vm.changed,
                onRemove: () {},
              ),
            ),
          ),
        ),
      );

      expect(find.text('₱260.00'), findsOneWidget);
      expect(find.byIcon(Icons.lock_outline), findsOneWidget);
      // Only the quantity can be typed.
      expect(find.byType(TextFormField), findsOneWidget);
    });
  });

  test('mock mode keeps the demo catalogue', () async {
    final products = await MockStoreCatalogRepository().getProducts();

    expect(products.first.sku, 'CEM-40');
    expect(products.first.price, 260);
    expect(products.first.materialId, 1);
    expect(await MockStoreCatalogRepository().getCategories(), isNotEmpty);
  });
}

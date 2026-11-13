import 'package:buildpro_frontend/core/di/service_locator.dart';
import 'package:buildpro_frontend/data/models/app_role.dart';
import 'package:buildpro_frontend/data/models/material_request.dart';
import 'package:buildpro_frontend/data/models/material_source.dart';
import 'package:buildpro_frontend/data/models/payment_method.dart';
import 'package:buildpro_frontend/data/models/purchase_order.dart';
import 'package:buildpro_frontend/data/repositories/mock_audit_log_repository.dart';
import 'package:buildpro_frontend/data/repositories/mock_procurement_repository.dart';
import 'package:buildpro_frontend/data/repositories/procurement_repository.dart';
import 'package:buildpro_frontend/data/services/business_rule_exception.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

void main() {
  setUp(resetServices);

  late MockProcurementRepository repo;
  setUp(() {
    repo = MockProcurementRepository(
      projects: getIt(),
      schedule: getIt(),
      masterData: getIt(),
      reports: getIt(),
      users: getIt(),
      auditLog: MockAuditLogRepository(),
      clock: () => DateTime(2026, 10, 26, 9),
    );
  });

  Matcher throwsRule(String fragment) => throwsA(
    isA<BusinessRuleException>().having(
      (e) => e.message,
      'message',
      contains(fragment),
    ),
  );

  /// Every material on project 1's site, counted at what the system expects.
  Future<List<CountLine>> fullCount(int projectId) async => [
    for (final l in await repo.getSiteInventory(projectId))
      if (l.needsCount)
        (
          materialId: l.materialId,
          name: l.name,
          unit: l.unit,
          expected: l.onHand,
          counted: l.onHand,
        ),
  ];

  Future<MaterialRequestDraft> draft({
    double qty = 10,
    int projectId = 1,
    DateTime? neededBy,
    bool counted = true,
  }) async => MaterialRequestDraft(
    projectId: projectId,
    neededBy: neededBy ?? DateTime(2026, 10, 30),
    items: [(description: 'Cement 40kg bags', unit: '', quantity: qty)],
    counts: counted ? await fullCount(projectId) : const [],
  );

  OrderLine line(int? materialId, String name, double qty, double price) => (
    materialId: materialId,
    description: name,
    unit: 'pc',
    quantity: qty,
    unitPrice: price,
  );

  group('requests', () {
    test(
      'validations: ongoing project, assigned engineer, qty, date',
      () async {
        expect(
          repo.createRequest(await draft(projectId: 3), userId: 8),
          throwsRule('Ongoing'),
        );
        expect(
          repo.createRequest(await draft(), userId: 8),
          throwsRule('assigned'),
        );
        expect(
          repo.createRequest(await draft(qty: 0), userId: 4),
          throwsRule('greater than 0'),
        );
        expect(
          repo.createRequest(
            await draft(neededBy: DateTime(2026, 10, 1)),
            userId: 4,
          ),
          throwsRule('past'),
        );
      },
    );

    test('materials on site must be counted first', () async {
      expect(
        repo.createRequest(await draft(counted: false), userId: 4),
        throwsRule('Count the'),
      );
    });

    test('the request keeps the typed items and the site count', () async {
      final d = await draft();
      final r = await repo.createRequest(d, userId: 4);
      final detail = (await repo.getRequest(r.id))!;
      expect(detail.items.single.description, 'Cement 40kg bags');
      expect(r.categoryId, isNull);
      expect(detail.counts, hasLength(d.counts.length));
      expect(r.status, MaterialRequestStatus.pending);
    });

    test('rejecting needs a reason', () {
      expect(
        repo.rejectRequest(3, userId: 3, role: AppRole.owner, reason: ''),
        throwsRule('reason'),
      );
    });
  });

  group('orders', () {
    test('own store: catalog items delivered to an address', () async {
      expect(
        repo.placeOrder(
          OrderDraft.ownStore(
            requestId: 4,
            categoryId: 3,
            lines: [line(9, 'Tie wire #16', 10, 95)],
            deliveryAddress: ' ',
          ),
          userId: 3,
        ),
        throwsRule('delivery address'),
      );
      final o = await repo.placeOrder(
        OrderDraft.ownStore(
          requestId: 4,
          categoryId: 3,
          lines: [line(9, 'Tie wire #16', 10, 95)],
          deliveryAddress: 'Lot 4, Manolo Fortich',
        ),
        userId: 3,
      );
      expect(o.source, MaterialSource.ownStore);
      expect(o.status, PurchaseOrderStatus.released);
      expect(o.totalAmount, 950);
      expect(o.deliveryAddress, 'Lot 4, Manolo Fortich');
      expect(o.categoryId, 3);
      expect(
        (await repo.getRequest(4))!.request.status,
        MaterialRequestStatus.ordered,
      );
      expect((await repo.getPayables()).any((p) => p.order.id == o.id), isTrue);
    });

    test('other store: needs OR and photo, paid so not a payable', () async {
      expect(
        repo.placeOrder(
          OrderDraft.otherStore(
            requestId: 4,
            categoryId: 3,
            lines: [line(null, 'Long-span roof sheet 0.5 mm', 220, 450)],
            storeName: 'Southern Roofing',
            orNumber: 'OR 1182',
            receiptPhotoUrl: '',
          ),
          userId: 3,
        ),
        throwsRule('photo'),
      );
      final o = await repo.placeOrder(
        OrderDraft.otherStore(
          requestId: 4,
          categoryId: 3,
          lines: [line(null, 'long-span roof sheet 0.5 mm', 220, 450)],
          storeName: 'Southern Roofing',
          orNumber: 'OR 1182',
          receiptPhotoUrl: '/tmp/receipt.jpg',
        ),
        userId: 3,
      );
      expect(o.status, PurchaseOrderStatus.purchased);
      expect(o.orNumber, 'OR 1182');
      expect(o.totalAmount, 99000);
      // A typed name on the price list links to that material.
      expect((await repo.getPurchaseOrder(o.id))!.items.single.materialId, 10);
      expect(
        (await repo.getPayables()).any((p) => p.order.id == o.id),
        isFalse,
      );
      expect(
        repo.cancelPurchaseOrder(o.id, userId: 3),
        throwsRule('cannot be cancelled'),
      );
    });

    test('one request split between own store and another store', () async {
      // MR-0004: item 11 roof sheets, item 12 tie wire.
      final own = await repo.placeOrder(
        OrderDraft.ownStore(
          requestId: 4,
          categoryId: 3,
          lines: [line(9, 'Tie wire #16', 10, 95)],
          coversItemIds: const [12],
          deliveryAddress: 'Site',
        ),
        userId: 3,
      );
      expect(
        repo.placeOrder(
          OrderDraft.ownStore(
            requestId: 4,
            categoryId: 3,
            lines: [line(9, 'Tie wire #16', 10, 95)],
            coversItemIds: const [12],
            deliveryAddress: 'Site',
          ),
          userId: 3,
        ),
        throwsRule('already covered'),
      );
      final other = await repo.placeOrder(
        OrderDraft.otherStore(
          requestId: 4,
          categoryId: 3,
          lines: [line(10, 'Long-span roof sheet 0.5 mm', 220, 450)],
          coversItemIds: const [11],
          storeName: 'Southern Roofing',
          orNumber: 'OR 1182',
          receiptPhotoUrl: '/tmp/r.jpg',
        ),
        userId: 3,
      );
      var items = (await repo.getRequest(4))!.items;
      expect(items.firstWhere((i) => i.id == 12).purchaseOrderId, own.id);
      expect(items.firstWhere((i) => i.id == 11).purchaseOrderId, other.id);

      // Cancelling the own-store order opens its item again.
      await repo.cancelPurchaseOrder(own.id, userId: 3);
      items = (await repo.getRequest(4))!.items;
      expect(items.firstWhere((i) => i.id == 12).isCovered, isFalse);
    });

    test('only the project owner orders', () {
      expect(
        repo.placeOrder(
          OrderDraft.ownStore(
            requestId: 4,
            categoryId: 3,
            lines: [line(9, 'Tie wire #16', 10, 95)],
            deliveryAddress: 'Site',
          ),
          userId: 4,
        ),
        throwsRule('Only the owner'),
      );
    });

    test('budget warning counts what is already ordered', () async {
      final check = await repo.checkBudget(2, 10000000);
      expect(check.committed, greaterThan(0));
      expect(check.exceedsBudget, isTrue);
    });

    test('cancelling the only order sends the request back', () async {
      final o = await repo.placeOrder(
        OrderDraft.ownStore(
          requestId: 4,
          categoryId: 3,
          lines: [line(9, 'Tie wire #16', 10, 95)],
          deliveryAddress: 'Site',
        ),
        userId: 3,
      );
      await repo.cancelPurchaseOrder(o.id, userId: 3);
      expect(
        (await repo.getRequest(4))!.request.status,
        MaterialRequestStatus.pending,
      );
    });
  });

  group('deliveries, inventory and payables', () {
    test('received cannot exceed ordered; damaged cannot exceed received', () {
      // PO 5 line 8: 80 bags of cement, none received yet.
      expect(
        repo.confirmDelivery(5, [
          (poItemId: 8, received: 81, damaged: 0),
        ], userId: 4),
        throwsRule('left to receive'),
      );
      expect(
        repo.confirmDelivery(5, [
          (poItemId: 8, received: 10, damaged: 11),
        ], userId: 4),
        throwsRule('Damaged'),
      );
    });

    test('partial then full delivery; inventory nets out usage', () async {
      var inv = await repo.getSiteInventory(1);
      double onHand(int materialId) =>
          inv.firstWhere((l) => l.materialId == materialId).onHand;
      // 120 cement received − 50 used on approved reports.
      expect(onHand(1), 70);
      // 120 rebar 12 mm − 2 damaged − 60 used.
      expect(onHand(3), 58);

      await repo.confirmDelivery(5, [
        (poItemId: 8, received: 50, damaged: 2),
      ], userId: 4);
      expect(
        (await repo.getPurchaseOrder(5))!.order.status,
        PurchaseOrderStatus.partiallyDelivered,
      );
      await repo.confirmDelivery(5, [
        (poItemId: 8, received: 30, damaged: 0),
      ], userId: 4);
      expect(
        (await repo.getPurchaseOrder(5))!.order.status,
        PurchaseOrderStatus.delivered,
      );
      inv = await repo.getSiteInventory(1);
      expect(onHand(1), 70 + 48 + 30);
    });

    test('items bought outside the price list are tracked by name', () async {
      final o = await repo.placeOrder(
        OrderDraft.otherStore(
          requestId: 4,
          categoryId: 3,
          lines: [line(null, 'Roof screws', 500, 2)],
          storeName: 'Ace Hardware',
          orNumber: 'OR 7',
          receiptPhotoUrl: '/tmp/r.jpg',
        ),
        userId: 3,
      );
      final item = (await repo.getPurchaseOrder(o.id))!.items.single;
      await repo.confirmDelivery(o.id, [
        (poItemId: item.id, received: 500, damaged: 0),
      ], userId: 4);
      final screws = (await repo.getSiteInventory(
        1,
      )).firstWhere((l) => l.name == 'Roof screws');
      expect(screws.materialId, isNull);
      expect(screws.onHand, 500);
    });

    test('payments cannot exceed the delivered balance', () async {
      final payables = await repo.getPayables();
      final po3 = payables.firstWhere((p) => p.order.id == 3);
      expect(po3.balance, 11000);
      expect(
        repo.recordPayment(
          3,
          amount: 12000,
          paidOn: DateTime(2026, 10, 26),
          method: PaymentMethod.cash,
          userId: 6,
        ),
        throwsRule('exceeds'),
      );
      await repo.recordPayment(
        3,
        amount: 11000,
        paidOn: DateTime(2026, 10, 26),
        method: PaymentMethod.cash,
        userId: 6,
      );
      expect(
        (await repo.getPayables()).firstWhere((p) => p.order.id == 3).balance,
        0,
      );
    });
  });

  testWidgets('site engineer counts the site, then requests materials', (
    tester,
  ) async {
    await pumpApp(tester);
    await signInAs(tester, 'ana@example.ph');
    await goTo(tester, '/material-requests/new?projectId=1');
    // Items are typed: no category, material or unit pickers.
    expect(find.textContaining('Category'), findsNothing);
    expect(find.widgetWithText(TextFormField, 'Unit'), findsNothing);
    final counts = find.widgetWithText(TextFormField, 'Counted');
    expect(counts, findsWidgets);
    for (var i = 0; i < counts.evaluate().length; i++) {
      await tester.enterText(counts.at(i), '5');
    }
    await tester.enterText(find.widgetWithText(TextFormField, 'Item'), 'Nails');
    await tester.enterText(find.widgetWithText(TextFormField, 'Qty'), '3');
    expect(find.textContaining('₱'), findsNothing);
    await tester.tap(find.text('Send to owner'));
    await tester.pumpAndSettle();
    expect(find.text('Request sent to the owner.'), findsOneWidget);
    expect(find.text('Waiting for owner'), findsOneWidget);
    expect(find.text('Site count before this request'), findsOneWidget);
  });

  testWidgets('owner orders a request from the own store', (tester) async {
    await pumpApp(tester);
    await signInAs(tester, 'ramon@example.ph');
    await goTo(tester, '/purchasing/requests');
    await tester.tap(find.textContaining('MR-0004'));
    await tester.pumpAndSettle();
    expect(find.text('Other store'), findsOneWidget);
    await tester.tap(find.text('Own hardware store'));
    await tester.pumpAndSettle();
    expect(find.text('Order from own hardware store'), findsOneWidget);
    expect(find.text('Requested by the site engineer'), findsOneWidget);
    await tester.tap(
      find.widgetWithText(DropdownButtonFormField<int>, 'Charge to category'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Roofing').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Search name or SKU'),
      'tie',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Add to order'));
    await tester.pumpAndSettle();
    // Tick the requested item this order covers.
    await tester.tap(find.widgetWithText(CheckboxListTile, 'Tie wire'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send order'));
    await tester.pumpAndSettle();
    // Qty starts empty, so the form asks for it first.
    expect(find.text('Quantity must be greater than 0.'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextFormField, 'Qty'), '10');
    await tester.tap(find.text('Send order'));
    await tester.pumpAndSettle();
    // Confirmation: the site engineer's list next to the order.
    expect(find.text('Confirm order'), findsOneWidget);
    expect(find.text('You are ordering'), findsOneWidget);
    expect(find.text('Roof sheets (long span)'), findsWidgets);
    await tester.tap(find.text('Back to edit'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Ordered from own store'), findsNothing);
    await tester.tap(find.text('Send order'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm and send'));
    await tester.pumpAndSettle();
    // Back on the request: the rest can go to another store.
    expect(
      find.text(
        'Ordered from own store. Add another order for the rest if needed.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Covered by PO-'), findsOneWidget);
    expect(find.text('Not ordered yet'), findsOneWidget);
    expect(find.text('Other store'), findsOneWidget);
  });

  testWidgets('the other-store page shows the requested list', (
    tester,
  ) async {
    // Tall enough to build the whole form.
    await pumpApp(tester, size: const Size(1400, 2600));
    await signInAs(tester, 'ramon@example.ph');
    await goTo(tester, '/material-requests/4');
    await tester.tap(find.text('Other store'));
    await tester.pumpAndSettle();
    expect(find.text('Bought from other store'), findsOneWidget);
    expect(find.text('Requested by the site engineer'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'OR number'), findsOneWidget);
    expect(find.text('Attach receipt photo'), findsOneWidget);
  });

  testWidgets('site engineer confirms a partial delivery', (tester) async {
    await pumpApp(tester);
    await signInAs(tester, 'ana@example.ph');
    await goTo(tester, '/deliveries');
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(find.text('Receive PO-2026-0005'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Received'),
      '40',
    );
    await tester.tap(find.text('Confirm delivery'));
    await tester.pumpAndSettle();
    expect(
      find.text('Delivery confirmed. Site inventory updated.'),
      findsOneWidget,
    );
  });
}

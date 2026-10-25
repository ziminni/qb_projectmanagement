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
      company: getIt(),
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

  MaterialRequestDraft draft({
    double qty = 10,
    int categoryId = 2,
    int projectId = 1,
    DateTime? neededBy,
  }) => MaterialRequestDraft(
    projectId: projectId,
    categoryId: categoryId,
    neededBy: neededBy ?? DateTime(2026, 10, 30),
    items: [(materialId: 1, quantity: qty)],
  );

  group('requests', () {
    test('validations: ongoing project, assigned engineer, qty, date', () {
      expect(
        repo.createRequest(draft(projectId: 3, categoryId: 1), userId: 8),
        throwsRule('Ongoing'),
      );
      expect(repo.createRequest(draft(), userId: 8), throwsRule('assigned'));
      expect(
        repo.createRequest(draft(qty: 0), userId: 4),
        throwsRule('greater than 0'),
      );
      expect(
        repo.createRequest(draft(neededBy: DateTime(2026, 10, 1)), userId: 4),
        throwsRule('past'),
      );
    });

    test('within budget: PM approval approves', () async {
      final r = await repo.approveRequest(3, userId: 3, role: AppRole.pm);
      expect(r.status, MaterialRequestStatus.approved);
    });

    test('over budget: PM approval escalates to the owner', () async {
      // 2,000 bags × ₱260 = ₱520,000 against Pillars' remaining ~₱306,150.
      final created = await repo.createRequest(draft(qty: 2000), userId: 4);
      final check = await repo.checkBudget(2, [
        (materialId: 1, quantity: 2000),
      ]);
      expect(check.exceedsBudget, isTrue);
      final afterPm = await repo.approveRequest(
        created.id,
        userId: 3,
        role: AppRole.pm,
      );
      expect(afterPm.status, MaterialRequestStatus.pendingOwner);
      expect(
        repo.approveRequest(created.id, userId: 3, role: AppRole.pm),
        throwsRule('cannot be approved'),
      );
      final afterOwner = await repo.approveRequest(
        created.id,
        userId: 2,
        role: AppRole.owner,
      );
      expect(afterOwner.status, MaterialRequestStatus.approved);
    });

    test('rejecting needs a reason', () {
      expect(
        repo.rejectRequest(3, userId: 3, role: AppRole.pm, reason: ''),
        throwsRule('reason'),
      );
    });
  });

  group('purchase orders', () {
    test('one PO per supplier; large ones wait for the owner', () async {
      final detail = (await repo.getRequest(4))!;
      final sheets = detail.items.firstWhere((i) => i.materialId == 10);
      final wire = detail.items.firstWhere((i) => i.materialId == 9);
      final orders = await repo.createPurchaseOrders(4, [
        OrderLine(
          requestItemId: sheets.id,
          source: MaterialSource.external,
          supplierId: 4,
          unitPrice: 450,
        ),
        OrderLine(
          requestItemId: wire.id,
          source: MaterialSource.ownStore,
          supplierId: 1,
          unitPrice: 95,
        ),
      ], userId: 5);
      expect(orders, hasLength(2));
      final roofing = orders.firstWhere((o) => o.supplierId == 4);
      expect(roofing.totalAmount, 99000);
      expect(roofing.status, PurchaseOrderStatus.pendingOwner);
      expect(
        orders.firstWhere((o) => o.supplierId == 1).status,
        PurchaseOrderStatus.released,
      );
      expect(
        (await repo.getRequest(4))!.request.status,
        MaterialRequestStatus.ordered,
      );

      final released = await repo.approvePurchaseOrder(roofing.id, userId: 2);
      expect(released.status, PurchaseOrderStatus.released);
    });

    test('source must match the supplier', () async {
      final item = (await repo.getRequest(4))!.items.first;
      expect(
        repo.createPurchaseOrders(4, [
          OrderLine(
            requestItemId: item.id,
            source: MaterialSource.ownStore,
            supplierId: 4,
            unitPrice: 1,
          ),
        ], userId: 5),
        throwsRule('own store'),
      );
    });

    test('cancelling frees the items for reordering', () async {
      final item = (await repo.getRequest(4))!.items.first;
      final orders = await repo.createPurchaseOrders(4, [
        OrderLine(
          requestItemId: item.id,
          source: MaterialSource.external,
          supplierId: 4,
          unitPrice: 450,
        ),
      ], userId: 5);
      await repo.cancelPurchaseOrder(orders.single.id, userId: 5);
      final again = (await repo.getRequest(4))!;
      expect(again.request.status, MaterialRequestStatus.approved);
      expect(again.items.every((i) => i.status.name == 'pending'), isTrue);
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

  testWidgets('site engineer requests materials with a budget check', (
    tester,
  ) async {
    await pumpApp(tester);
    await signInAs(tester, 'ana@example.ph');
    await goTo(tester, '/material-requests/new?projectId=1');
    await tester.tap(
      find.widgetWithText(
        DropdownButtonFormField<int>,
        'Category (budget it draws from)',
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Roofing').last);
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(DropdownButtonFormField<int>, 'Material'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Portland cement 40 kg (bag)').last);
    await tester.pumpAndSettle();
    expect(find.text('Budget check'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Send to PM'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Send to PM'));
    await tester.pumpAndSettle();
    expect(find.text('Request sent to the PM.'), findsOneWidget);
    expect(find.text('Waiting for PM'), findsOneWidget);
  });

  testWidgets('purchasing orders an approved request', (tester) async {
    await pumpApp(tester);
    await signInAs(tester, 'carlo@example.ph');
    expect(find.textContaining('MR-0004'), findsOneWidget);
    await tester.tap(find.textContaining('MR-0004'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create purchase orders'));
    await tester.pumpAndSettle();
    // Long-span sheets from an external supplier.
    await tester.tap(find.text('Other supplier').first);
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(DropdownButtonFormField<int>, 'Supplier').first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Southern Roofing Corp.').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('goes to the owner first'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.widgetWithText(FilledButton, 'Create purchase orders'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(
      find.widgetWithText(FilledButton, 'Create purchase orders'),
    );
    await tester.pumpAndSettle();
    expect(find.text('2 purchase order(s) created.'), findsOneWidget);
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

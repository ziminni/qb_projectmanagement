import 'package:buildpro_frontend/core/di/service_locator.dart';
import 'package:buildpro_frontend/core/utils/app_messages.dart';
import 'package:buildpro_frontend/data/models/payment_method.dart';
import 'package:buildpro_frontend/data/models/progress_billing.dart';
import 'package:buildpro_frontend/data/models/variation_order.dart';
import 'package:buildpro_frontend/data/repositories/billing_repository.dart';
import 'package:buildpro_frontend/data/repositories/mock_audit_log_repository.dart';
import 'package:buildpro_frontend/data/repositories/mock_billing_repository.dart';
import 'package:buildpro_frontend/data/repositories/procurement_repository.dart';
import 'package:buildpro_frontend/data/repositories/project_repository.dart';
import 'package:buildpro_frontend/data/services/business_rule_exception.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

void main() {
  setUp(resetServices);

  late MockBillingRepository repo;
  setUp(() {
    repo = MockBillingRepository(
      projects: getIt(),
      schedule: getIt(),
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

  test('seeded billing #1 matches the shared progress calculation', () async {
    // Fresh project: no previous billings for the comparison.
    final c = await repo.previewBilling(1, DateTime(2026, 9, 15));
    expect(c.pctAccomplished, closeTo(0.29, 1e-9));
    // Previous billing #1 already covers this gross, so this period is 0.
    expect(c.grossEarned, 580000);
    expect(c.thisPeriod, 0);
  });

  test('new billing: earned − previous − DP recoupment − retention', () async {
    final b = await repo.createBilling(1, DateTime(2026, 10, 26), userId: 3);
    expect(b.billingNo, 2);
    expect(b.pctAccomplished, closeTo(0.37, 1e-9));
    expect(b.grossEarned, 740000);
    expect(b.lessPrevious, 580000);
    expect(b.lessDpRecoupment, 24000);
    expect(b.lessRetention, 16000);
    expect(b.netDue, 120000);
    expect(b.status, BillingStatus.draft);
  });

  test('billing rules', () async {
    // Project 2 already has a billing in progress.
    expect(
      repo.createBilling(2, DateTime(2026, 10, 26), userId: 3),
      throwsRule('in progress'),
    );
    expect(
      repo.createBilling(1, DateTime(2026, 10, 27), userId: 3),
      throwsRule('future'),
    );
    expect(
      repo.createBilling(1, DateTime(2026, 9, 10), userId: 3),
      throwsRule('previous billing'),
    );
    // Sep 16: no new verified work since the Sep 15 billing.
    expect(
      repo.createBilling(1, DateTime(2026, 9, 16), userId: 3),
      throwsRule('no new verified'),
    );
    // Project 3 is not Ongoing.
    expect(
      repo.createBilling(3, DateTime(2026, 10, 26), userId: 8),
      throwsRule('Ongoing'),
    );
  });

  test('approval chain, dispute and payments', () async {
    final b = await repo.createBilling(1, DateTime(2026, 10, 26), userId: 3);
    expect(
      repo.clientApprove(b.id, userId: 7),
      throwsRule('not waiting for client'),
    );
    await repo.submitBilling(b.id, userId: 3);

    expect(
      repo.clientDispute(b.id, userId: 7, reason: ''),
      throwsRule('reason'),
    );
    await repo.clientDispute(b.id, userId: 7, reason: 'Pillars not complete');
    final history = (await repo.getBilling(b.id))!.history;
    expect(history.last.details['reason'], 'Pillars not complete');

    await repo.submitBilling(b.id, userId: 3);
    expect(
      repo.recordPayment(
        b.id,
        amount: 10,
        paidOn: DateTime(2026, 10, 26),
        method: PaymentMethod.cash,
        userId: 6,
      ),
      throwsRule('client-approved'),
    );
    await repo.clientApprove(b.id, userId: 7);
    expect(
      repo.recordPayment(
        b.id,
        amount: 120001,
        paidOn: DateTime(2026, 10, 26),
        method: PaymentMethod.cash,
        userId: 6,
      ),
      throwsRule('exceeds'),
    );
    await repo.recordPayment(
      b.id,
      amount: 20000,
      paidOn: DateTime(2026, 10, 26),
      method: PaymentMethod.cash,
      userId: 6,
    );
    expect(
      (await repo.getBilling(b.id))!.billing.status,
      BillingStatus.approved,
    );
    await repo.recordPayment(
      b.id,
      amount: 100000,
      paidOn: DateTime(2026, 10, 26),
      method: PaymentMethod.check,
      userId: 6,
    );
    expect((await repo.getBilling(b.id))!.billing.status, BillingStatus.paid);

    // Retention from both paid billings is now held.
    final r = await repo.retentionFor(1);
    expect(r.held, 58000 + 16000);
    expect(
      repo.releaseRetention(
        1,
        amount: 1,
        releasedOn: DateTime(2026, 10, 26),
        method: PaymentMethod.cash,
        userId: 6,
      ),
      throwsRule('Completed'),
    );
  });

  group('variation orders', () {
    test('a deductive VO cannot cut the contract below the amount billed', () {
      final vo = VariationOrder(
        id: 0,
        projectId: 1,
        voNo: '',
        type: VariationOrderType.deductive,
        description: 'Delete second floor',
        amount: 1500000,
        daysImpact: 0,
        status: VariationOrderStatus.proposed,
      );
      expect(
        repo.saveVariationOrder(vo, userId: 3),
        throwsRule('already billed'),
      );
    });

    test(
      'deductive amounts are stored negative; client approval logs VO without modifying project details',
      () async {
        final vo = await repo.saveVariationOrder(
          VariationOrder(
            id: 0,
            projectId: 1,
            voNo: '',
            type: VariationOrderType.deductive,
            description: 'Delete window grills',
            amount: 12000,
            daysImpact: 0,
            status: VariationOrderStatus.proposed,
          ),
          userId: 3,
        );
        expect(vo.amount, -12000);
        expect(vo.voNo, 'VO-03');

        // VO-01 waits for the client: approving it records approval on the VO
        // without altering the project's contract amount or target end date.
        final before = (await getIt<ProjectRepository>().getProject(1))!;
        final approved = await repo.clientApproveVo(1, userId: 7);
        expect(approved.status, VariationOrderStatus.approved);
        expect(approved.approvedByClient, 7);
        final after = (await getIt<ProjectRepository>().getProject(1))!;
        expect(after.contractAmount, before.contractAmount);
        expect(after.targetEndDate, before.targetEndDate);
      },
    );

    test(
      'a site engineer\'s VO has no price until the owner sets one',
      () async {
        final vo = await repo.saveVariationOrder(
          VariationOrder(
            id: 0,
            projectId: 1,
            voNo: '',
            type: VariationOrderType.additive,
            description: 'Extra lighting outlets',
            amount: 9999,
            daysImpact: 1,
            status: VariationOrderStatus.proposed,
          ),
          userId: 4,
        );
        expect(vo.amount, 0);
        expect(
          repo.submitVariationOrder(vo.id, userId: 3),
          throwsRule('cost impact'),
        );
        await repo.saveVariationOrder(vo.copyWith(amount: 15000), userId: 3);
        final sent = await repo.submitVariationOrder(vo.id, userId: 3);
        expect(sent.amount, 15000);
      },
    );

    test('only the owner sends a VO to the client', () async {
      expect(
        repo.submitVariationOrder(2, userId: 4),
        throwsRule('project manager'),
      );
      final sent = await repo.submitVariationOrder(2, userId: 3);
      expect(sent.status, VariationOrderStatus.pendingClient);
      expect(sent.approvedByOwner, 3);
    });
  });

  testWidgets('owner creates a billing and sends it to the client', (
    tester,
  ) async {
    await pumpApp(tester);
    await signInAs(tester, 'ramon@example.ph');
    await goTo(tester, '/billings/new?projectId=1');
    expect(find.text('₱120,000.00'), findsOneWidget);
    await tester.tap(find.text('Create draft billing'));
    await tester.pumpAndSettle();
    expect(find.text('PROGRESS BILLING NO. 2'), findsOneWidget);
    await tester.tap(find.text('Send to client'));
    await tester.pumpAndSettle();
    expect(statusChip('Waiting for client'), findsOneWidget);
  });

  testWidgets('owner rejects a proposed VO from the inbox', (tester) async {
    await pumpApp(tester);
    await signInAs(tester, 'ramon@example.ph');
    expect(find.text('Billed vs. collected'), findsOneWidget);
    await goTo(tester, '/approvals');
    expect(find.text('Variation orders (2)'), findsWidgets);
    await tester.tap(find.text('Variation orders (2)').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('VO-02 · QB-2026-014'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reject'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'Use 0.4 mm as quoted');
    await tester.tap(find.widgetWithText(FilledButton, 'Reject'));
    await tester.pumpAndSettle();
    expect(statusChip('Rejected'), findsOneWidget);
    expect(find.textContaining('Use 0.4 mm as quoted'), findsOneWidget);
  });

  group('supplier accounting is blocked in API mode', () {
    // API mode throws on supplier accounting (phase-3 blockers 1-2): the
    // screens must say so and stop the spinner instead of hanging forever.
    setUp(() async {
      await getIt.unregister<ProcurementRepository>();
      getIt.registerLazySingleton<ProcurementRepository>(
        ApiLikeProcurement.new,
      );
    });

    testWidgets('financials tab explains the block and stops loading', (
      tester,
    ) async {
      await pumpApp(tester);
      await signInAs(tester, 'liza@example.ph');
      await goTo(tester, '/projects/1/financials');
      expect(find.text(supplierAccountingUnavailable), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      // Only the derived cost half is blocked: the billings are the server's
      // own rows and still show.
      expect(find.text('Progress billings'), findsOneWidget);
      expect(find.text('Billed'), findsOneWidget);
    });

    testWidgets('expense reports explain the block and stop loading', (
      tester,
    ) async {
      await pumpApp(tester);
      await signInAs(tester, 'liza@example.ph');
      await goTo(tester, '/expense-reports');
      expect(find.text(supplierAccountingUnavailable), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });

  testWidgets('financials tab and expense report', (tester) async {
    await pumpApp(tester);
    await signInAs(tester, 'liza@example.ph');
    await goTo(tester, '/projects/1/financials');
    expect(find.text('Budget vs. actual'), findsOneWidget);
    expect(find.text('₱435,000.00'), findsWidgets);
    await goTo(tester, '/expense-reports');
    expect(find.text('Actual cost'), findsOneWidget);
    await goTo(tester, '/retention');
    expect(
      find.textContaining('Retention is released only after'),
      findsWidgets,
    );
  });

  testWidgets('variation orders page shows dashboard KPIs and breakdowns', (
    tester,
  ) async {
    await pumpApp(tester);
    await signInAs(tester, 'ramon@example.ph');
    await goTo(tester, '/variation-orders');

    expect(find.text('Total variation orders'), findsOneWidget);
    expect(find.text('Awaiting approval'), findsOneWidget);
    expect(find.text('Approved cost impact'), findsOneWidget);
    expect(find.text('Approved schedule impact'), findsOneWidget);
    expect(find.text('Approval pipeline'), findsOneWidget);
    expect(find.text('By change type'), findsOneWidget);

    // Filter via the Approved chip; dashboard stays visible and empty state
    // appears when no approved VOs exist in seed data.
    await tester.tap(find.text('Approved (0)'));
    await tester.pumpAndSettle();
    expect(find.text('No variation orders match.'), findsOneWidget);
    expect(find.text('Total variation orders'), findsOneWidget);
  });

  testWidgets('VO form adapts photo attachment slots per change type', (
    tester,
  ) async {
    await pumpApp(tester);
    await signInAs(tester, 'ramon@example.ph');
    await goTo(tester, '/variation-orders/new');

    // Default type: Added work -> 1 photo slot for what is to be added.
    expect(find.text('Photo evidence of work to add'), findsOneWidget);
    expect(find.byKey(const ValueKey('vo-photo-primary')), findsOneWidget);
    expect(find.byKey(const ValueKey('vo-photo-secondary')), findsNothing);

    // Switch to Removed work -> 1 photo slot for what is to be removed.
    await tester.tap(find.text('Removed work'));
    await tester.pumpAndSettle();
    expect(find.text('Photos of work to be removed'), findsOneWidget);
    expect(find.byKey(const ValueKey('vo-photo-primary')), findsOneWidget);
    expect(find.byKey(const ValueKey('vo-photo-secondary')), findsNothing);

    // Switch to Design change -> 2 photo slots (current vs. new).
    await tester.tap(find.text('Design change'));
    await tester.pumpAndSettle();
    expect(find.text('Current / existing condition'), findsOneWidget);
    expect(find.text('New / proposed design'), findsOneWidget);
    expect(find.byKey(const ValueKey('vo-photo-primary')), findsOneWidget);
    expect(find.byKey(const ValueKey('vo-photo-secondary')), findsOneWidget);
  });

  testWidgets('VO detail page displays attached photos and opens preview popup', (
    tester,
  ) async {
    await pumpApp(tester);
    final billing = getIt<BillingRepository>();
    final created = await billing.saveVariationOrder(
      const VariationOrder(
        id: 0,
        projectId: 1,
        voNo: '',
        type: VariationOrderType.change,
        description: 'Revised balcony railing design',
        amount: 25000,
        daysImpact: 2,
        status: VariationOrderStatus.proposed,
        primaryAttachments: [
          'mock://existing-balcony.jpg',
          'mock://existing-angle2.jpg',
        ],
        secondaryAttachments: ['mock://new-railing.png'],
      ),
      userId: 3,
    );

    await signInAs(tester, 'ramon@example.ph');
    await goTo(tester, '/variation-orders/${created.id}');

    expect(find.text('Photo evidence'), findsOneWidget);
    expect(find.text('Current / existing condition'), findsOneWidget);
    expect(find.text('New / proposed design'), findsOneWidget);
    expect(find.text('existing-balcony.jpg'), findsOneWidget);
    expect(find.text('existing-angle2.jpg'), findsOneWidget);
    expect(find.text('new-railing.png'), findsOneWidget);

    // Tapping a photo opens the preview dialog.
    await tester.tap(find.text('existing-balcony.jpg'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.byType(InteractiveViewer), findsOneWidget);
  });

  testWidgets(
    'after creating and sending a VO, Back returns to Variation orders list instead of the Add VO form',
    (tester) async {
      await pumpApp(tester);
      await signInAs(tester, 'ramon@example.ph');
      await goTo(tester, '/variation-orders');

      await tester.tap(find.text('Raise a VO'));
      await tester.pumpAndSettle();
      expect(find.text('Raise a variation order'), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Description of the change'),
        'Add extra garden faucet',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Amount added'),
        '8000',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Additional days (schedule change)'),
        '1',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Draft'));
      await tester.pumpAndSettle();

      expect(find.textContaining('added as draft'), findsOneWidget);
      expect(find.text('Send to client'), findsOneWidget);
      expect(find.text('Export VO'), findsNothing);
      await tester.tap(find.text('Send to client'));
      await tester.pumpAndSettle();

      expect(find.text('Export VO'), findsOneWidget);
      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();

      expect(find.text('Total variation orders'), findsOneWidget);
      expect(find.text('Raise a variation order'), findsNothing);
    },
  );
}

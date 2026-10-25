import 'package:buildpro_frontend/core/di/service_locator.dart';
import 'package:buildpro_frontend/data/models/payment_method.dart';
import 'package:buildpro_frontend/data/models/progress_billing.dart';
import 'package:buildpro_frontend/data/models/variation_order.dart';
import 'package:buildpro_frontend/data/repositories/mock_audit_log_repository.dart';
import 'package:buildpro_frontend/data/repositories/mock_billing_repository.dart';
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
    await repo.submitBilling(b.id, userId: 3);
    expect(
      repo.clientApprove(b.id, userId: 7),
      throwsRule('waiting for owner'),
    );
    await repo.ownerApprove(b.id, userId: 2);

    expect(
      repo.clientDispute(b.id, userId: 7, reason: ''),
      throwsRule('reason'),
    );
    await repo.clientDispute(b.id, userId: 7, reason: 'Pillars not complete');
    final history = (await repo.getBilling(b.id))!.history;
    expect(history.last.details['reason'], 'Pillars not complete');

    await repo.submitBilling(b.id, userId: 3);
    await repo.ownerApprove(b.id, userId: 2);
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
      'deductive amounts are stored negative; client approval updates the contract',
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
          userId: 4,
        );
        expect(vo.amount, -12000);
        expect(vo.voNo, 'VO-03');

        // VO-01 waits for the client: +₱85,000 and 5 days.
        final before = (await getIt<ProjectRepository>().getProject(1))!;
        await repo.clientApproveVo(1, userId: 7);
        final after = (await getIt<ProjectRepository>().getProject(1))!;
        expect(after.contractAmount, before.contractAmount + 85000);
        expect(
          after.targetEndDate,
          before.targetEndDate.add(const Duration(days: 5)),
        );
      },
    );

    test('only the PM submits; only the owner approves', () async {
      expect(
        repo.submitVariationOrder(2, userId: 4),
        throwsRule('project manager'),
      );
      await repo.submitVariationOrder(2, userId: 3);
      final approved = await repo.ownerApproveVo(2, userId: 2);
      expect(approved.status, VariationOrderStatus.pendingClient);
    });
  });

  testWidgets('PM creates a billing and submits it', (tester) async {
    await pumpApp(tester);
    await signInAs(tester, 'jose@example.ph');
    await goTo(tester, '/billings/new?projectId=1');
    expect(find.text('₱120,000.00'), findsOneWidget);
    await tester.tap(find.text('Create draft billing'));
    await tester.pumpAndSettle();
    expect(find.text('PROGRESS BILLING NO. 2'), findsOneWidget);
    await tester.tap(find.text('Submit to owner'));
    await tester.pumpAndSettle();
    expect(statusChip('Waiting for owner'), findsOneWidget);
  });

  testWidgets('owner approves a billing and a VO from the inbox', (
    tester,
  ) async {
    await pumpApp(tester);
    await signInAs(tester, 'ramon@example.ph');
    expect(find.text('Billed vs. collected'), findsOneWidget);
    await goTo(tester, '/approvals');
    expect(find.text('Progress billings (1)'), findsWidgets);
    await tester.tap(find.text('Billing #1 · QB-2026-018'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Approve and send to client'));
    await tester.pumpAndSettle();
    expect(statusChip('Waiting for client'), findsOneWidget);

    await goTo(tester, '/variation-orders/3');
    await tester.tap(find.text('Reject'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'Use 0.4 mm as quoted');
    await tester.tap(find.widgetWithText(FilledButton, 'Reject'));
    await tester.pumpAndSettle();
    expect(statusChip('Rejected'), findsOneWidget);
    expect(find.textContaining('Use 0.4 mm as quoted'), findsOneWidget);
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
}

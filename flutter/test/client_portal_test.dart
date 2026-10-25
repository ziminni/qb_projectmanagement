import 'package:buildpro_frontend/core/di/service_locator.dart';
import 'package:buildpro_frontend/data/repositories/billing_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

void main() {
  setUp(resetServices);

  testWidgets('client sees progress, S-curve and Gantt without costs', (
    tester,
  ) async {
    await pumpApp(tester);
    await signInAs(tester, 'mark@example.ph');
    expect(find.text('Two-storey residence, Villanueva'), findsOneWidget);
    expect(find.text('37%'), findsOneWidget);
    await tester.tap(find.text('Two-storey residence, Villanueva'));
    await tester.pumpAndSettle();
    expect(find.text('37% complete'), findsOneWidget);
    expect(find.text('S-curve'), findsOneWidget);
    expect(find.textContaining('Budget'), findsNothing);
    expect(find.textContaining('Earned value'), findsNothing);
    await tester.scrollUntilVisible(
      find.text('Category % complete'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Foundation'), findsWidgets);
  });

  testWidgets('photo gallery shows approved reports only', (tester) async {
    await pumpApp(tester);
    await signInAs(tester, 'mark@example.ph');
    await goTo(tester, '/client/photos');
    expect(find.text('Second-floor column cages'), findsOneWidget);
    // Report 6 is still waiting for the PM.
    expect(find.text('Formworks for second-floor columns'), findsNothing);
  });

  testWidgets('client approves a VO; the contract amount updates', (
    tester,
  ) async {
    await pumpApp(tester);
    await signInAs(tester, 'mark@example.ph');
    await goTo(tester, '/client/variation-orders');
    // VO-02 is still a proposal and hidden from the client.
    expect(find.textContaining('VO-02'), findsNothing);
    await tester.tap(find.textContaining('VO-01'));
    await tester.pumpAndSettle();
    expect(find.text('₱2,000,000.00'), findsOneWidget);
    await tester.tap(find.text('Approve change'));
    await tester.pumpAndSettle();
    expect(find.text('₱2,085,000.00'), findsOneWidget);
    expect(statusChip('Approved'), findsOneWidget);
  });

  testWidgets('client disputes a billing, then approves the revision', (
    tester,
  ) async {
    final billing = getIt<BillingRepository>();
    final b = await billing.createBilling(1, DateTime.now(), userId: 3);
    await billing.submitBilling(b.id, userId: 3);
    await billing.ownerApprove(b.id, userId: 2);

    await pumpApp(tester);
    await signInAs(tester, 'mark@example.ph');
    await goTo(tester, '/client/billings');
    expect(find.text('Waiting for your approval'), findsOneWidget);
    await tester.tap(find.textContaining('Billing #2'));
    await tester.pumpAndSettle();
    expect(find.text('NET AMOUNT DUE'), findsOneWidget);

    await tester.tap(find.text('Dispute'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'Pillars are not done');
    await tester.tap(find.text('Send dispute'));
    await tester.pumpAndSettle();
    expect(find.text('You disputed this billing'), findsOneWidget);

    await billing.submitBilling(b.id, userId: 3);
    await billing.ownerApprove(b.id, userId: 2);
    await goTo(tester, '/client/billings');
    await tester.tap(find.textContaining('Billing #2'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Approve billing'));
    await tester.pumpAndSettle();
    expect(statusChip('Approved by client'), findsOneWidget);
  });

  testWidgets('client cannot open another client\'s billing', (tester) async {
    await pumpApp(tester);
    await signInAs(tester, 'mark@example.ph');
    // Billing 2 belongs to project 2 (another client).
    await goTo(tester, '/client/billings/2');
    expect(find.text('Billing not found.'), findsOneWidget);
  });
}

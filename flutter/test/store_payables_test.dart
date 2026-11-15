import 'package:buildpro_frontend/core/utils/app_messages.dart';
import 'package:buildpro_frontend/data/models/store_balance.dart';
import 'package:buildpro_frontend/data/services/business_rule_exception.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'store_balance_test.dart' show useBalance;
import 'test_helpers.dart';

StoreBalance balance({
  double total = 780,
  double paid = 300,
  bool atStore = true,
}) => StoreBalance(
  total: total,
  paid: paid,
  balance: total - paid,
  atStore: atStore,
  fetchedAt: DateTime(2026, 11, 15, 10, 30),
);

/// API mode: outside purchases are paid at the counter, so the only supplier
/// debt is what projects owe our store, and the store holds that record.
void main() {
  setUp(resetServices);

  testWidgets('lists what each project owes the store, read-only', (
    tester,
  ) async {
    await pumpApp(tester);
    await useBalance(() async => balance(), supportsPayments: false);
    await signInAs(tester, 'liza@example.ph');
    await goTo(tester, '/payables');

    expect(
      find.textContaining('QB-2026-014', skipOffstage: false),
      findsOneWidget,
    );
    expect(find.text('₱480.00', skipOffstage: false), findsWidgets);
    expect(find.textContaining('recorded at the store'), findsOneWidget);
    // The store records payments: nothing to pay here.
    expect(find.text('Pay'), findsNothing);
    expect(find.text(supplierAccountingUnavailable), findsNothing);
  });

  testWidgets('a project the store has never been sent is not listed', (
    tester,
  ) async {
    await pumpApp(tester);
    await useBalance(
      () async => balance(total: 0, paid: 0, atStore: false),
      supportsPayments: false,
    );
    await signInAs(tester, 'liza@example.ph');
    await goTo(tester, '/payables');

    expect(find.textContaining('Nothing is owed to the store'), findsOneWidget);
  });

  testWidgets('a store that cannot be read says so, never a lower total', (
    tester,
  ) async {
    await pumpApp(tester);
    await useBalance(
      () async =>
          throw const BusinessRuleException('The store could not be reached.'),
      supportsPayments: false,
    );
    await signInAs(tester, 'liza@example.ph');
    await goTo(tester, '/payables');

    expect(find.textContaining('store could not be reached'), findsOneWidget);
    expect(find.textContaining('Unpaid:'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}

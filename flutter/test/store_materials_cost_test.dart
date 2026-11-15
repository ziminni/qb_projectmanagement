import 'package:buildpro_frontend/core/di/service_locator.dart';
import 'package:buildpro_frontend/data/models/store_balance.dart';
import 'package:buildpro_frontend/data/repositories/http_procurement_repository.dart';
import 'package:buildpro_frontend/data/services/business_rule_exception.dart';
import 'package:buildpro_frontend/data/services/project_cost_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'network/fake_api.dart';
import 'store_balance_test.dart' show useBalance;
import 'test_helpers.dart';

StoreBalance owed(double total) => StoreBalance(
  total: total,
  paid: 0,
  balance: total,
  atStore: true,
  fetchedAt: DateTime(2026, 11, 15),
);

void main() {
  setUp(resetServices);

  test('outside-store materials come from the server, by category', () async {
    final api = FakeApi(
      (o) => json({
        'project_id': 1,
        'by_category': {'3': '2340.00', '7': '199.00'},
      }),
    );
    final repo = HttpProcurementRepository(
      testClient(api: api, tokens: InMemoryTokenStore()),
    );

    final byCategory = await repo.deliveredValueByCategory(1);

    expect(api.requests.single.path, 'projects/1/external-materials-cost/');
    expect(byCategory, {3: 2340.0, 7: 199.0});
  });

  group('project costs', () {
    test(
      'the store charge is one materials line on top of the categories',
      () async {
        await useBalance(() async => owed(780));

        final mockCategories = await getIt<ProjectCostService>().costsFor(1);

        expect(mockCategories.storeMaterials, 780);
        expect(
          mockCategories.materials,
          mockCategories.materialsByCategory.values.fold<double>(
                0,
                (a, b) => a + b,
              ) +
              780,
        );
      },
    );

    test('no store to ask (the offline demo) adds nothing', () async {
      final costs = await getIt<ProjectCostService>().costsFor(1);

      expect(costs.storeMaterials, 0);
    });

    test(
      'a store that cannot be reached is an error, never a lower total',
      () async {
        await useBalance(
          () async => throw const BusinessRuleException(
            'The store could not be reached.',
          ),
        );

        expect(
          () => getIt<ProjectCostService>().costsFor(1),
          throwsA(
            isA<BusinessRuleException>().having(
              (e) => e.message,
              'message',
              contains("store's charges"),
            ),
          ),
        );
      },
    );
  });

  group('Financials tab', () {
    testWidgets('shows the store charge as its own budget-vs-actual row', (
      tester,
    ) async {
      await pumpApp(tester);
      await useBalance(() async => owed(780));
      await signInAs(tester, 'liza@example.ph');
      await goTo(tester, '/projects/1/financials');

      expect(
        find.text('Materials from our store', skipOffstage: false),
        findsOneWidget,
      );
      expect(find.text('₱780', skipOffstage: false), findsWidgets);
    });

    testWidgets(
      'a store that is down blocks only the cost table, with the reason',
      (tester) async {
        await pumpApp(tester);
        await useBalance(
          () async => throw const BusinessRuleException(
            'The store could not be reached.',
          ),
        );
        await signInAs(tester, 'liza@example.ph');
        await goTo(tester, '/projects/1/financials');

        expect(
          find.textContaining("store's charges", skipOffstage: false),
          findsOneWidget,
        );
        expect(find.text('Actual cost'), findsNothing);
        expect(
          find.text('Progress billings', skipOffstage: false),
          findsOneWidget,
        );
        expect(find.byType(CircularProgressIndicator), findsNothing);
      },
    );
  });
}

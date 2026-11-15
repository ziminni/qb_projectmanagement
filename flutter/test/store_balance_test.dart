import 'package:buildpro_frontend/core/di/service_locator.dart';
import 'package:buildpro_frontend/data/models/store_balance.dart';
import 'package:buildpro_frontend/data/repositories/http_procurement_repository.dart';
import 'package:buildpro_frontend/data/repositories/mock_audit_log_repository.dart';
import 'package:buildpro_frontend/data/repositories/mock_procurement_repository.dart';
import 'package:buildpro_frontend/data/repositories/procurement_repository.dart';
import 'package:buildpro_frontend/data/services/business_rule_exception.dart';
import 'package:flutter_test/flutter_test.dart';

import 'network/fake_api.dart';
import 'test_helpers.dart';

/// Mock procurement whose store balance is scripted.
class BalanceProcurement extends MockProcurementRepository {
  BalanceProcurement(this.answer)
    : super(
        projects: getIt(),
        schedule: getIt(),
        masterData: getIt(),
        reports: getIt(),
        users: getIt(),
        auditLog: MockAuditLogRepository(),
      );

  final Future<StoreBalance?> Function() answer;

  @override
  Future<StoreBalance?> getStoreBalance(int projectId) => answer();
}

Future<void> useBalance(Future<StoreBalance?> Function() answer) async {
  await getIt.unregister<ProcurementRepository>();
  getIt.registerLazySingleton<ProcurementRepository>(
    () => BalanceProcurement(answer),
  );
}

void main() {
  group('http store balance', () {
    HttpProcurementRepository repo(FakeApi api) => HttpProcurementRepository(
      testClient(api: api, tokens: InMemoryTokenStore()),
    );

    test('reads what the store says the project owes', () async {
      final api = FakeApi(
        (o) => json({
          'project_id': 1,
          'at_store': true,
          'total': '2750.00',
          'paid': '500.00',
          'balance': '2250.00',
          'fetched_at': '2026-11-15T10:30:00+08:00',
        }),
      );

      final balance = (await repo(api).getStoreBalance(1))!;

      expect(api.requests.single.path, 'projects/1/pos-payables/');
      expect(balance.total, 2750);
      expect(balance.paid, 500);
      expect(balance.balance, 2250);
      expect(balance.atStore, isTrue);
      expect(balance.fetchedAt, DateTime.parse('2026-11-15T10:30:00+08:00'));
    });

    test('a missing amount is an error, never a zero', () async {
      final api = FakeApi(
        (o) => json({'project_id': 1, 'at_store': true, 'total': '1.00'}),
      );

      expect(
        () => repo(api).getStoreBalance(1),
        throwsA(isA<FormatException>()),
      );
    });

    test('a store that cannot be reached is the server message', () async {
      final api = FakeApi(
        (o) => json({
          'detail': 'The store could not be reached. Try again in a moment.',
        }, status: 502),
      );

      expect(
        () => repo(api).getStoreBalance(1),
        throwsA(
          isA<BusinessRuleException>().having(
            (e) => e.message,
            'message',
            contains('store could not be reached'),
          ),
        ),
      );
    });
  });

  group('Owed to the store card on the Financials tab', () {
    setUp(resetServices);

    testWidgets('shows what the store says, and that payments live there', (
      tester,
    ) async {
      await pumpApp(tester);
      await useBalance(
        () async => StoreBalance(
          total: 2750,
          paid: 500,
          balance: 2250,
          atStore: true,
          fetchedAt: DateTime(2026, 11, 15, 10, 30),
        ),
      );
      await signInAs(tester, 'liza@example.ph');
      await goTo(tester, '/projects/1/financials');

      expect(find.text('Owed to the store'), findsOneWidget);
      expect(find.text('₱2,250.00'), findsWidgets);
      expect(find.textContaining('recorded at the store'), findsOneWidget);
    });

    testWidgets(
      'a store that is down says so and the rest of the tab still loads',
      (tester) async {
        await pumpApp(tester);
        await useBalance(
          () async => throw const BusinessRuleException(
            'The store could not be reached. Try again in a moment.',
          ),
        );
        await signInAs(tester, 'liza@example.ph');
        await goTo(tester, '/projects/1/financials');

        expect(
          find.textContaining('Store balance unavailable'),
          findsOneWidget,
        );
        expect(
          find.textContaining('store could not be reached'),
          findsOneWidget,
        );
        // Below the fold in a lazily built list, but built: the tab did not fail.
        expect(
          find.text('Progress billings', skipOffstage: false),
          findsOneWidget,
        );
      },
    );

    testWidgets('a project the store has never seen owes nothing yet', (
      tester,
    ) async {
      await pumpApp(tester);
      await useBalance(
        () async => StoreBalance(
          total: 0,
          paid: 0,
          balance: 0,
          atStore: false,
          fetchedAt: DateTime(2026, 11, 15),
        ),
      );
      await signInAs(tester, 'liza@example.ph');
      await goTo(tester, '/projects/1/financials');

      expect(
        find.textContaining('Nothing owed to the store yet'),
        findsOneWidget,
      );
    });

    testWidgets('the offline demo has no store, so no card', (tester) async {
      await pumpApp(tester);
      await signInAs(tester, 'liza@example.ph');
      await goTo(tester, '/projects/1/financials');

      expect(find.text('Owed to the store', skipOffstage: false), findsNothing);
      expect(
        find.text('Progress billings', skipOffstage: false),
        findsOneWidget,
      );
    });
  });
}

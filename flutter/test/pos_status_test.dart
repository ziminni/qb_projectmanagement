import 'dart:async';

import 'package:buildpro_frontend/core/di/service_locator.dart';
import 'package:buildpro_frontend/data/models/app_role.dart';
import 'package:buildpro_frontend/data/models/material_source.dart';
import 'package:buildpro_frontend/data/models/purchase_order.dart';
import 'package:buildpro_frontend/data/models/user.dart';
import 'package:buildpro_frontend/data/repositories/procurement_repository.dart';
import 'package:buildpro_frontend/data/services/business_rule_exception.dart';
import 'package:buildpro_frontend/data/services/session_service.dart';
import 'package:buildpro_frontend/features/procurement/viewmodels/procurement_lookups.dart';
import 'package:buildpro_frontend/features/procurement/viewmodels/purchase_order_detail_viewmodel.dart';
import 'package:buildpro_frontend/features/procurement/widgets/procurement_pos_status_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'network/fake_api.dart';
import 'network/http_procurement_repository_test.dart' show repoFor;
import 'test_helpers.dart';

Map<String, dynamic> snapshot({bool review = false}) => {
  'purchase_order_id': 5,
  'source': 'own_store',
  'pos_sync_status': 'failed',
  'pos_status': 'awaiting_counter',
  'last_checked_at': '2026-11-14T09:00:00Z',
  'stale': true,
  'detail': 'Store unavailable.',
  'decline_reason': '',
  'close_pending': false,
  'close_needs_review': review,
  'pos_expected_amount': '987654.32',
  'pos_token': 'SECRET',
  'pos_request_id': '11111111-2222-3333-4444-555555555555',
};

class StatusRepo extends ApiLikeProcurement {
  bool enabled = true;
  MaterialSource source = MaterialSource.ownStore;
  PurchaseOrderStatus status = PurchaseOrderStatus.released;
  Map<String, dynamic> response = snapshot();
  int reads = 0;
  int writes = 0;
  bool fail = false;
  Completer<PosStatus>? pending;
  @override
  bool get supportsPosStatus => enabled;
  @override
  Future<PurchaseOrderDetail?> getPurchaseOrder(int id) async =>
      PurchaseOrderDetail(
        order: PurchaseOrder(
          id: id,
          poNo: 'PO-5',
          projectId: 1,
          source: source,
          status: status,
          totalAmount: 0,
        ),
        items: const [],
        deliveries: const [],
        payments: const [],
        requestId: null,
      );
  @override
  Future<PosStatus> getPosStatus(int id) async {
    reads++;
    if (fail) throw const BusinessRuleException('Status unavailable. Retry.');
    return pending == null ? PosStatus.fromJson(response) : pending!.future;
  }

  @override
  Future<PosStatus> retryPosSync(int id) async {
    writes++;
    if (fail) throw const BusinessRuleException('Queue unavailable. Retry.');
    return pending == null ? PosStatus.fromJson(response) : pending!.future;
  }
}

void main() {
  test('HTTP cached GET and queue-only POST use no body or query', () async {
    final api = FakeApi((_) => json(snapshot(review: true)));
    final repo = repoFor(api);
    expect(repo.supportsPosStatus, isTrue);
    final status = await repo.getPosStatus(5);
    expect(status.syncStatus, 'failed');
    expect(status.storeStatus, 'awaiting_counter');
    expect(status.stale, isTrue);
    expect(status.closeNeedsReview, isTrue);
    expect(status.lastCheckedAt, DateTime.utc(2026, 11, 14, 9));
    await repo.retryPosSync(5);
    expect(api.paths, [
      'purchase-orders/5/pos-status/',
      'purchase-orders/5/pos-sync/',
    ]);
    expect(api.requests.map((r) => r.method), ['GET', 'POST']);
    for (final request in api.requests) {
      expect(request.data, isNull);
      expect(request.uri.queryParameters, isEmpty);
    }
  });
  for (final code in [401, 403, 404]) {
    for (final write in [false, true]) {
      test('HTTP ${write ? 'POST' : 'GET'} $code surfaces refusal', () async {
        final api = FakeApi(
          (_) => json({'detail': 'Refused $code'}, status: code),
        );
        final repo = repoFor(api);
        await expectLater(
          write ? repo.retryPosSync(5) : repo.getPosStatus(5),
          throwsA(
            isA<BusinessRuleException>().having(
              (e) => e.message,
              'message',
              code == 401 ? contains('Sign in again') : 'Refused $code',
            ),
          ),
        );
      });
    }
  }

  group('VM and panel', () {
    late StatusRepo repo;
    late SessionService session;
    late PurchaseOrderDetailViewModel vm;
    setUp(() async {
      await resetServices();
      repo = StatusRepo();
      session = getIt<SessionService>();
      session.signIn(
        const User(
          id: 3,
          companyId: 1,
          fullName: 'Owner',
          email: 'owner@example.ph',
        ),
        [AppRole.owner, AppRole.admin],
        activeRole: AppRole.owner,
      );
      vm = PurchaseOrderDetailViewModel(
        orderId: 5,
        session: session,
        procurement: repo,
        lookups: ProcurementLookups.fromServices(),
      );
    });
    tearDown(() => vm.dispose());
    test(
      'capability and own-store guard skip requests; non-owner cannot queue',
      () async {
        repo.enabled = false;
        await vm.load();
        expect(vm.supportsPosStatus, isFalse);
        expect(repo.reads, 0);
        repo.enabled = true;
        repo.source = MaterialSource.external;
        await vm.load();
        expect(vm.supportsPosStatus, isFalse);
        expect(repo.reads, 0);
        repo.source = MaterialSource.ownStore;
        await vm.load();
        session.switchRole(AppRole.admin);
        await vm.retryStoreSync();
        expect(repo.writes, 0);
      },
    );
    test('queue failure is not Queued and can be retried', () async {
      await vm.load();
      repo.fail = true;
      await vm.retryStoreSync();
      expect(vm.posQueued, isFalse);
      expect(vm.posError, 'Queue unavailable. Retry.');
      expect(vm.posBusy, isFalse);
      repo.fail = false;
      await vm.retryStoreSync();
      expect(vm.posQueued, isTrue);
      expect(vm.posError, isNull);
      expect(repo.writes, 2);
    });
    test('slow cache read leaves order visible, not blank spinner', () async {
      repo.pending = Completer<PosStatus>();
      final loading = vm.load();
      for (var i = 0; i < 30 && !vm.posBusy; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(vm.posBusy, isTrue);
      final visible = !vm.isLoading && vm.detail != null;
      repo.pending!.complete(PosStatus.fromJson(snapshot()));
      await loading;
      expect(visible, isTrue);
    });
    test('cancelled queue guard uses close_needs_review only', () async {
      repo.status = PurchaseOrderStatus.cancelled;
      await vm.load();
      expect(vm.canRetryStoreSync, isFalse);
      await vm.retryStoreSync();
      expect(repo.writes, 0);
      repo.response = snapshot(review: true);
      await vm.refreshPosStatus();
      expect(vm.canRetryStoreSync, isTrue);
      await vm.retryStoreSync();
      expect(repo.writes, 1);
      expect(vm.posQueued, isTrue);
    });
    test(
      'busy guards reads/writes; errors keep snapshot and permit retry',
      () async {
        await vm.load();
        repo.pending = Completer<PosStatus>();
        final pending = vm.retryStoreSync();
        await vm.retryStoreSync();
        await vm.refreshPosStatus();
        expect(repo.writes, 1);
        expect(repo.reads, 1);
        expect(vm.posBusy, isTrue);
        repo.pending!.complete(PosStatus.fromJson(snapshot()));
        await pending;
        repo.pending = null;
        repo.fail = true;
        await vm.refreshPosStatus();
        expect(vm.posError, 'Status unavailable. Retry.');
        expect(vm.posStatus, isNotNull);
        expect(vm.posBusy, isFalse);
        repo.fail = false;
        await vm.refreshPosStatus();
        expect(vm.posError, isNull);
        expect(repo.reads, 3);
      },
    );
    testWidgets(
      'panel cached copy, close warning, redaction, Queued not Synced',
      (tester) async {
        repo.status = PurchaseOrderStatus.cancelled;
        repo.response = snapshot(review: true);
        await vm.load();
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: AnimatedBuilder(
                animation: vm,
                builder: (_, _) => ProcurementPosStatusPanel(vm: vm),
              ),
            ),
          ),
        );
        expect(find.text('Stale cached data'), findsOneWidget);
        expect(find.text('awaiting_counter'), findsOneWidget);
        expect(find.textContaining('store may still hold'), findsOneWidget);
        expect(
          find.textContaining('not proof of physical release'),
          findsOneWidget,
        );
        for (final secret in [
          '987654.32',
          'SECRET',
          '11111111',
          'Estimate',
          'invoice',
        ]) {
          expect(find.textContaining(secret), findsNothing);
        }
        await tester.tap(find.text('Retry store sync'));
        await tester.pumpAndSettle();
        expect(find.text('Queued'), findsOneWidget);
        expect(find.text('Synced'), findsNothing);
        final reads = repo.reads;
        await tester.tap(find.text('Refresh cached snapshot'));
        await tester.pumpAndSettle();
        expect(repo.reads, reads + 1);
        expect(repo.writes, 1);
      },
    );
    testWidgets('initial status failure shows retry, no blank spinner', (
      tester,
    ) async {
      repo.fail = true;
      await vm.load();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AnimatedBuilder(
              animation: vm,
              builder: (_, _) => ProcurementPosStatusPanel(vm: vm),
            ),
          ),
        ),
      );
      expect(find.text('Status unavailable. Retry.'), findsOneWidget);
      expect(find.text('Refresh cached snapshot'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      repo.fail = false;
      await tester.tap(find.text('Refresh cached snapshot'));
      await tester.pumpAndSettle();
      expect(find.text('awaiting_counter'), findsOneWidget);
    });
  });
}

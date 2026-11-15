import 'package:buildpro_frontend/core/network/api_config.dart';
import 'package:buildpro_frontend/data/models/app_role.dart';
import 'package:buildpro_frontend/data/models/payment_method.dart';
import 'package:buildpro_frontend/data/models/progress_billing.dart';
import 'package:buildpro_frontend/data/models/variation_order.dart';
import 'package:buildpro_frontend/data/repositories/http_billing_repository.dart';
import 'package:buildpro_frontend/data/services/business_rule_exception.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_api.dart';

// Wire shapes from the Phase 4 slice 4.2a build: money as 2-dp strings, dates
// as `YYYY-MM-DD`, `this_period` derived on the server and ignored by the model.

Map<String, dynamic> billingRow({
  int id = 1,
  int projectId = 1,
  int billingNo = 1,
  String periodEnd = '2026-10-31',
  String status = 'pending_client',
  String gross = '450000.00',
  String previous = '0.00',
  String retention = '15000.00',
}) => {
  'id': id,
  'project_id': projectId,
  'billing_no': billingNo,
  'period_end': periodEnd,
  'pct_accomplished': '0.500000',
  'gross_earned': gross,
  'less_previous': previous,
  'less_dp_recoupment': '0.00',
  'less_retention': retention,
  'net_due': '435000.00',
  'this_period': '450000.00',
  'status': status,
  'created_at': '2026-10-31T09:00:00Z',
  'updated_at': '2026-10-31T09:00:00Z',
};

Map<String, dynamic> paymentRow({
  int id = 1,
  int billingId = 1,
  String amount = '100000.00',
  String paidOn = '2026-11-05',
}) => {
  'id': id,
  'progress_billing_id': billingId,
  'amount': amount,
  'paid_on': paidOn,
  'method': 'bank_transfer',
  'reference_no': 'BDO-8891',
  'created_at': '2026-11-05T09:00:00Z',
  'updated_at': '2026-11-05T09:00:00Z',
};

Map<String, dynamic> voRow({
  int id = 1,
  int projectId = 1,
  String status = 'pending_client',
  String amount = '50000.00',
  int? approvedByOwner = 4,
  int? approvedByClient,
}) => {
  'id': id,
  'project_id': projectId,
  'vo_no': 'VO-01',
  'type': 'additive',
  'description': 'Extra column footing',
  'amount': amount,
  'days_impact': 7,
  'status': status,
  'approved_by_owner': approvedByOwner,
  'approved_by_client': approvedByClient,
  'created_at': '2026-10-20T09:00:00Z',
  'updated_at': '2026-10-20T09:00:00Z',
};

Map<String, dynamic> releaseRow({
  int id = 1,
  int projectId = 1,
  String amount = '5000.00',
}) => {
  'id': id,
  'project_id': projectId,
  'amount': amount,
  'released_on': '2026-12-01',
  'method': 'check',
  'reference_no': 'CHK-2213',
  'created_at': '2026-12-01T09:00:00Z',
  'updated_at': '2026-12-01T09:00:00Z',
};

Map<String, dynamic> auditRow({int id = 1, String action = 'billing_submitted'}) => {
  'id': id,
  'user_id': 4,
  'action': action,
  'entity': 'progress_billing',
  'entity_id': 1,
  'details': {'reason': 'Rework on the second floor'},
  'created_at': '2026-10-31T10:00:00Z',
  'updated_at': null,
};

HttpBillingRepository billingRepoFor(
  FakeApi api, {
  AppRole active = AppRole.owner,
}) => HttpBillingRepository(
  testClient(
    api: api,
    tokens: InMemoryTokenStore(access: testAccess, refresh: testRefresh),
    session: signedInSession(active: active),
  ),
);

void main() {
  group('billings', () {
    test('reads the billing list and follows DRF pages', () async {
      final nextPageUrl = '$apiBaseUrl/progress-billings/?page=2';
      final api = FakeApi((options) {
        final second = options.uri.queryParameters['page'] == '2';
        return json({
          'count': 2,
          'next': second ? null : nextPageUrl,
          'previous': null,
          'results': [billingRow(id: second ? 2 : 1)],
        });
      });

      final billings = await billingRepoFor(api).getBillings();

      expect(api.last('progress-billings/').method, 'GET');
      expect(billings.map((b) => b.id), [1, 2]);
      expect(billings.first.billingNo, 1);
      expect(billings.first.periodEnd, DateTime(2026, 10, 31));
      expect(billings.first.pctAccomplished, 0.5);
      expect(billings.first.netDue, 435000);
      // `this_period` is the model's getter, not a stored field.
      expect(billings.first.thisPeriod, 450000);
      expect(billings.first.status, BillingStatus.pendingClient);
    });

    test('sends one project and one status as route filters', () async {
      final api = FakeApi(
        (options) => json([billingRow(projectId: 7, status: 'approved')]),
      );

      final billings = await billingRepoFor(api).getBillings(
        projectIds: [7],
        statuses: [BillingStatus.approved],
      );

      final query = api.last('progress-billings/').uri.queryParameters;
      expect(query['project'], '7');
      expect(query['status'], 'approved');
      expect(billings.single.status, BillingStatus.approved);
    });

    test('a longer list is filtered here, not guessed at the route', () async {
      final api = FakeApi(
        (options) => json([
          billingRow(id: 1, projectId: 1),
          billingRow(id: 2, projectId: 2),
          billingRow(id: 3, projectId: 3, status: 'paid'),
        ]),
      );

      final billings = await billingRepoFor(api).getBillings(
        projectIds: [1, 2],
        statuses: [BillingStatus.pendingClient, BillingStatus.paid],
      );

      expect(api.last('progress-billings/').uri.queryParameters, isEmpty);
      expect(billings.map((b) => b.id), [1, 2]);
    });

    test('the detail carries the payments and the audit history', () async {
      final api = FakeApi(
        (options) => json({
          ...billingRow(),
          'payments': [paymentRow()],
          'history': [auditRow()],
        }),
      );

      final detail = (await billingRepoFor(api).getBilling(1))!;

      expect(api.last('progress-billings/1/').method, 'GET');
      expect(detail.billing.id, 1);
      expect(detail.payments.single.amount, 100000);
      expect(detail.payments.single.method, PaymentMethod.bankTransfer);
      expect(detail.history.single.action, 'billing_submitted');
      expect(detail.history.single.details['reason'], 'Rework on the second floor');
      expect(detail.paid, 100000);
      expect(detail.balance, 335000);
    });

    test('a billing the server does not show is null, not an error', () async {
      final api = FakeApi((options) => json({'detail': 'Not found.'}, status: 404));

      // A draft billing is a 404 for the client: it may not learn it exists.
      expect(await billingRepoFor(api, active: AppRole.client).getBilling(9), isNull);
    });

    test('preview asks the server and trusts its figures', () async {
      final api = FakeApi(
        (options) => json({
          'pct_accomplished': '0.500000',
          'gross_earned': '450000.00',
          'less_previous': '400000.00',
          'less_dp_recoupment': '15000.00',
          'less_retention': '10000.00',
          'this_period': '50000.00',
          'net_due': '25000.00',
        }),
      );

      final figures = await billingRepoFor(
        api,
        active: AppRole.owner,
      ).previewBilling(3, DateTime(2026, 10, 31));

      final request = api.last('progress-billings/preview/');
      expect(request.method, 'GET');
      expect(request.uri.queryParameters['project'], '3');
      expect(request.uri.queryParameters['period_end'], '2026-10-31');
      expect(figures.pctAccomplished, 0.5);
      expect(figures.grossEarned, 450000);
      expect(figures.lessPrevious, 400000);
      expect(figures.lessDpRecoupment, 15000);
      expect(figures.lessRetention, 10000);
      expect(figures.thisPeriod, 50000);
      expect(figures.netDue, 25000);
    });

    test('a finance answer without a figure is a parse error, not zero', () async {
      final body = {
        'pct_accomplished': '0.500000',
        'gross_earned': '450000.00',
        'less_previous': '0.00',
        'less_dp_recoupment': '0.00',
        'less_retention': '10000.00',
        'this_period': '450000.00',
        'net_due': '440000.00',
      }..remove('gross_earned');
      final api = FakeApi((options) => json(body));

      // Preview is finance-only: a missing figure is a broken response, and a
      // zero would be money nobody computed.
      expect(
        billingRepoFor(api, active: AppRole.accountant).previewBilling(
          3,
          DateTime(2026, 10, 31),
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('creates a draft with the project and the period end only', () async {
      final api = FakeApi(
        (options) => json(billingRow(status: 'draft', billingNo: 4), status: 201),
      );

      final billing = await billingRepoFor(
        api,
      ).createBilling(3, DateTime(2026, 10, 31), userId: 4);

      final request = api.last('progress-billings/');
      expect(request.method, 'POST');
      final body = sentBody(request);
      expect(body['project_id'], 3);
      expect(body['period_end'], '2026-10-31');
      // The server owns the number, the money and the status.
      expect(body.containsKey('status'), isFalse);
      expect(body.containsKey('billing_no'), isFalse);
      expect(billing.billingNo, 4);
      expect(billing.status, BillingStatus.draft);
    });

    test('submits and withdraws through their own routes', () async {
      final api = FakeApi(
        (options) => json(
          billingRow(status: options.path.endsWith('/submit/')
              ? 'pending_client'
              : 'rejected'),
        ),
      );
      final repo = billingRepoFor(api);

      final submitted = await repo.submitBilling(1, userId: 4);
      final withdrawn = await repo.cancelBilling(1, userId: 4);

      expect(api.last('progress-billings/1/submit/').method, 'POST');
      expect(api.last('progress-billings/1/withdraw/').method, 'POST');
      expect(submitted.status, BillingStatus.pendingClient);
      expect(withdrawn.status, BillingStatus.rejected);
    });

    test('the client approves and disputes on the billing routes', () async {
      final api = FakeApi((options) => json(billingRow(status: 'disputed')));
      final repo = billingRepoFor(api, active: AppRole.client);

      await repo.clientApprove(1, userId: 9);
      await repo.clientDispute(1, userId: 9, reason: '  Wrong retention  ');

      expect(api.last('progress-billings/1/client-approve/').method, 'POST');
      final dispute = api.last('progress-billings/1/client-dispute/');
      expect(dispute.method, 'POST');
      expect(sentBody(dispute)['reason'], 'Wrong retention');
    });

    test('records the client payment on the billing', () async {
      final api = FakeApi((options) => json(paymentRow(), status: 201));

      final payment = await billingRepoFor(api, active: AppRole.accountant)
          .recordPayment(
            1,
            amount: 100000,
            paidOn: DateTime(2026, 11, 5),
            method: PaymentMethod.bankTransfer,
            referenceNo: ' BDO-8891 ',
            userId: 6,
          );

      final request = api.last('progress-billings/1/payments/');
      expect(request.method, 'POST');
      final body = sentBody(request);
      expect(body['amount'], 100000.0);
      expect(body['paid_on'], '2026-11-05');
      expect(body['method'], 'bank_transfer');
      expect(body['reference_no'], 'BDO-8891');
      expect(payment.amount, 100000);
      expect(payment.progressBillingId, 1);
    });

    test('no reference means no reference key, not an empty one', () async {
      final api = FakeApi((options) => json(paymentRow(), status: 201));

      await billingRepoFor(api).recordPayment(
        1,
        amount: 500,
        paidOn: DateTime(2026, 11, 5),
        method: PaymentMethod.cash,
        userId: 6,
      );

      expect(sentBody(api.last('progress-billings/1/payments/')).containsKey(
        'reference_no',
      ), isFalse);
    });

    test('keeps the server refusal text on a 400', () async {
      final api = FakeApi(
        (options) => json({
          'detail': 'Payments are recorded only on client-approved billings.',
        }, status: 400),
      );

      expect(
        billingRepoFor(api, active: AppRole.accountant).recordPayment(
          1,
          amount: 10,
          paidOn: DateTime(2026, 11, 5),
          method: PaymentMethod.cash,
          userId: 6,
        ),
        throwsA(
          isA<BusinessRuleException>().having(
            (e) => e.message,
            'message',
            'Payments are recorded only on client-approved billings.',
          ),
        ),
      );
    });
  });

  group('payments and summary', () {
    test('reads one project\'s payments through the route filter', () async {
      final api = FakeApi((options) => json([paymentRow()]));

      final payments = await billingRepoFor(
        api,
        active: AppRole.accountant,
      ).getPayments(projectIds: [3]);

      expect(api.last('client-payments/').uri.queryParameters['project'], '3');
      expect(payments.single.paidOn, DateTime(2026, 11, 5));
    });

    test('a longer list is matched through the billings', () async {
      final api = FakeApi((options) {
        if (options.path.startsWith('progress-billings/')) {
          return json([
            billingRow(id: 1, projectId: 1),
            billingRow(id: 2, projectId: 2),
          ]);
        }
        return json([
          paymentRow(id: 1, billingId: 1),
          paymentRow(id: 2, billingId: 2),
          paymentRow(id: 3, billingId: 99),
        ]);
      });

      final payments = await billingRepoFor(
        api,
        active: AppRole.accountant,
      ).getPayments(projectIds: [1]);

      // One project: the route already scoped it, no billing lookup needed.
      expect(api.countOf('progress-billings/'), 0);
      expect(payments.map((p) => p.id), [1, 2, 3]);

      final many = await billingRepoFor(api, active: AppRole.accountant)
          .getPayments(projectIds: [1, 2]);
      // A wider list matches the payments against those projects' billings.
      expect(api.countOf('progress-billings/'), 1);
      expect(many.map((p) => p.id), [1, 2]);
    });

    test('the summary comes from the billing-summary route', () async {
      final api = FakeApi(
        (options) => json({'billed': 435000.0, 'collected': 100000.0}),
      );

      final summary = await billingRepoFor(
        api,
        active: AppRole.owner,
      ).billedSummary(projectIds: [3]);

      expect(api.last('billing-summary/').uri.queryParameters['project'], '3');
      expect(summary.billed, 435000);
      expect(summary.collected, 100000);
    });

    test('several projects are summed from the very same rows', () async {
      final api = FakeApi((options) {
        if (options.path == 'billing-summary/') {
          return json({'billed': 999.0, 'collected': 999.0});
        }
        if (options.path == 'progress-billings/') {
          return json([
            billingRow(id: 1, projectId: 1),
            billingRow(id: 2, projectId: 2, status: 'draft'),
          ]);
        }
        return json([
          paymentRow(id: 1, billingId: 1, amount: '100000.00'),
          paymentRow(id: 2, billingId: 2, amount: '7000.00'),
        ]);
      });

      final summary = await billingRepoFor(
        api,
        active: AppRole.owner,
      ).billedSummary(projectIds: [1, 2]);

      // The route filters one project, so the wider list adds the same rows up.
      expect(api.countOf('billing-summary/'), 0);
      expect(summary.billed, 435000);
      expect(summary.collected, 107000);
    });

    test('retention held and released come from the retention route', () async {
      final api = FakeApi(
        (options) => json({
          'held': 15000.0,
          'released': 5000.0,
          'available': 10000.0,
        }),
      );

      final retention = await billingRepoFor(
        api,
        active: AppRole.accountant,
      ).retentionFor(3);

      expect(api.last('retention/').uri.queryParameters['project'], '3');
      expect(retention.held, 15000);
      expect(retention.released, 5000);
    });

    test('a finance answer without held retention is a parse error', () async {
      final api = FakeApi(
        (options) => json({'released': 5000.0, 'available': -5000.0}),
      );

      expect(
        billingRepoFor(api, active: AppRole.accountant).retentionFor(3),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('variation orders', () {
    test('reads the VO list and follows DRF pages', () async {
      final api = FakeApi(
        (options) => json({
          'count': 1,
          'next': null,
          'previous': null,
          'results': [voRow()],
        }),
      );

      final orders = await billingRepoFor(
        api,
        active: AppRole.siteEngineer,
      ).getVariationOrders(projectIds: [1]);

      expect(api.last('variation-orders/').uri.queryParameters['project'], '1');
      expect(orders.single.voNo, 'VO-01');
      expect(orders.single.amount, 50000);
      expect(orders.single.daysImpact, 7);
      expect(orders.single.approvedByOwner, 4);
      expect(orders.single.approvedByClient, isNull);
    });

    test('the detail carries its audit history', () async {
      final api = FakeApi(
        (options) => json({
          ...voRow(),
          'history': [auditRow(action: 'vo_submitted')],
        }),
      );

      final detail = (await billingRepoFor(
        api,
        active: AppRole.owner,
      ).getVariationOrder(1))!;

      expect(api.last('variation-orders/1/').method, 'GET');
      expect(detail.order.id, 1);
      expect(detail.history.single.action, 'vo_submitted');
    });

    test('a VO the route does not show is null', () async {
      final api = FakeApi((options) => json({'detail': 'Not found.'}, status: 404));

      expect(await billingRepoFor(api, active: AppRole.client).getVariationOrder(9), isNull);
    });

    test('proposes with POST and edits with PATCH', () async {
      final api = FakeApi((options) => json(voRow(id: 3), status: 201));
      final repo = billingRepoFor(api, active: AppRole.owner);
      final draft = VariationOrder(
        id: 0,
        projectId: 1,
        voNo: '',
        type: VariationOrderType.deductive,
        description: '  Remove the canopy  ',
        amount: 12000,
        daysImpact: -3,
        status: VariationOrderStatus.proposed,
      );

      await repo.saveVariationOrder(draft, userId: 4);
      await repo.saveVariationOrder(draft.copyWith(id: 3), userId: 4);

      final created = api.last('variation-orders/');
      expect(created.method, 'POST');
      final body = sentBody(created);
      expect(body['project_id'], 1);
      expect(body['type'], 'deductive');
      expect(body['description'], 'Remove the canopy');
      expect(body['amount'], 12000.0);
      expect(body['days_impact'], -3);
      expect(body.containsKey('vo_no'), isFalse);

      final edited = api.last('variation-orders/3/');
      expect(edited.method, 'PATCH');
      expect(sentBody(edited)['amount'], 12000.0);
    });

    test('a site engineer never sends a price', () async {
      final api = FakeApi((options) => json(voRow(amount: '0.00'), status: 201));

      await billingRepoFor(api, active: AppRole.siteEngineer).saveVariationOrder(
        VariationOrder(
          id: 0,
          projectId: 1,
          voNo: '',
          type: VariationOrderType.additive,
          description: 'Extra column footing',
          amount: 0,
          daysImpact: 7,
          status: VariationOrderStatus.proposed,
        ),
        userId: 5,
      );

      // The server prices a VO for the owner only; sending 0.00 would be a
      // price nobody quoted.
      expect(
        sentBody(api.last('variation-orders/')).containsKey('amount'),
        isFalse,
      );
    });

    test('submit, owner-reject, client approve and reject have routes', () async {
      final api = FakeApi((options) => json(voRow(status: 'rejected')));
      final repo = billingRepoFor(api, active: AppRole.owner);

      await repo.submitVariationOrder(1, userId: 4);
      await repo.ownerRejectVo(1, userId: 4, reason: ' Not needed ');
      await repo.clientApproveVo(1, userId: 9);
      await repo.clientRejectVo(1, userId: 9, reason: ' Too expensive ');

      expect(api.last('variation-orders/1/submit/').method, 'POST');
      expect(api.last('variation-orders/1/owner-reject/').method, 'POST');
      // Approval applies the VO to the contract on the server: no second call.
      expect(api.last('variation-orders/1/client-approve/').method, 'POST');
      expect(api.last('variation-orders/1/client-reject/').method, 'POST');
      expect(sentBody(api.last('variation-orders/1/owner-reject/'))['reason'],
          'Not needed');
      expect(sentBody(api.last('variation-orders/1/client-reject/'))['reason'],
          'Too expensive');
      expect(api.paths.where((p) => p.startsWith('projects/')), isEmpty);
    });
  });

  group('retention releases', () {
    test('lists releases, filtered to the projects asked for', () async {
      final api = FakeApi(
        (options) => json([
          releaseRow(id: 1, projectId: 1),
          releaseRow(id: 2, projectId: 2),
        ]),
      );

      final releases = await billingRepoFor(
        api,
        active: AppRole.accountant,
      ).getRetentionReleases(projectIds: [2]);

      expect(
        api.last('retention-releases/').uri.queryParameters['project'],
        '2',
      );
      expect(releases.single.projectId, 2);
      expect(releases.single.method, PaymentMethod.check);
      expect(releases.single.releasedOn, DateTime(2026, 12, 1));
    });

    test('releases retention with the method and the reference', () async {
      final api = FakeApi((options) => json(releaseRow(), status: 201));

      final release = await billingRepoFor(api, active: AppRole.accountant)
          .releaseRetention(
            1,
            amount: 5000,
            releasedOn: DateTime(2026, 12, 1),
            method: PaymentMethod.check,
            referenceNo: ' CHK-2213 ',
            userId: 6,
          );

      final body = sentBody(api.last('retention-releases/'));
      expect(body['project_id'], 1);
      expect(body['amount'], 5000.0);
      expect(body['released_on'], '2026-12-01');
      expect(body['method'], 'check');
      expect(body['reference_no'], 'CHK-2213');
      expect(release.amount, 5000);
    });

    test('keeps the refusal text when the project is not completed', () async {
      final api = FakeApi(
        (options) => json({
          'detail': 'Retention is released only after the project is completed.',
        }, status: 400),
      );

      expect(
        billingRepoFor(api, active: AppRole.accountant).releaseRetention(
          1,
          amount: 5000,
          releasedOn: DateTime(2026, 12, 1),
          method: PaymentMethod.cash,
          userId: 6,
        ),
        throwsA(
          isA<BusinessRuleException>().having(
            (e) => e.message,
            'message',
            'Retention is released only after the project is completed.',
          ),
        ),
      );
    });
  });
}

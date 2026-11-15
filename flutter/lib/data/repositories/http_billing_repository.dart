import '../../core/network/api_client.dart';
import '../models/audit_log.dart';
import '../models/json_utils.dart';
import '../models/payment.dart';
import '../models/payment_method.dart';
import '../models/progress_billing.dart';
import '../models/retention_release.dart';
import '../models/variation_order.dart';
import '../services/billing_calculator.dart';
import 'billing_repository.dart';

/// Progress billings, the client's payments, variation orders and retention
/// against the CPMS backend (Phase 4, slice 4.2a routes).
///
/// Scope, role and every rule are the server's: the active role (sent as
/// `X-Active-Role`) decides which projects and rows come back, whether a
/// client may see a draft at all (it is a `404`) and whether a VO amount is
/// priced, so the `userId`s in the interface are never sent as a claim.
/// Nothing here writes a status: each move is its own route, so the state
/// machine and its audit row stay inside the server transaction. Refusals
/// arrive as the server's own `detail` text and surface as
/// `BusinessRuleException` unchanged.
///
/// Every [BillingRepository] method has a route (contract, slice 4.2a), so no
/// method refuses and no capability flag is needed. Approving a variation
/// order applies it to the contract amount and target end date on the server,
/// which is why `ProjectRepository.applyVariation` is never called from here.
class HttpBillingRepository implements BillingRepository {
  HttpBillingRepository(this._client);

  final ApiClient _client;

  // ---- Billings

  @override
  Future<List<ProgressBilling>> getBillings({
    List<int>? projectIds,
    List<BillingStatus>? statuses,
  }) async {
    final rows = await _client.getRows(
      'progress-billings/',
      query: {
        ..._oneProject(projectIds),
        // The route filters one status; a longer list is filtered here.
        if (statuses != null && statuses.length == 1)
          'status': statuses.single.apiValue,
      },
    );
    return [
      for (final row in rows)
        if (ProgressBilling.fromJson(row) case final billing
            when _inProjects(billing.projectId, projectIds) &&
                (statuses == null || statuses.contains(billing.status)))
          billing,
    ];
  }

  /// One billing with its payments and its audit history; a billing the server
  /// does not show the caller (another project's, or a client's draft) is null
  /// rather than an error, so the screens say "no longer exists".
  @override
  Future<BillingDetail?> getBilling(int id) async {
    final data = await _client.get(
      'progress-billings/$id/',
      notFoundAsNull: true,
    );
    if (data == null) return null;
    final row = jsonObject(data);
    return BillingDetail(
      billing: ProgressBilling.fromJson(row),
      payments: [
        for (final payment in jsonRows(row['payments'])) Payment.fromJson(payment),
      ],
      history: _history(row['history']),
    );
  }

  /// What a billing for [periodEnd] would show: the server counts verified
  /// work as of that date, so no progress is computed here.
  @override
  Future<BillingComputation> previewBilling(
    int projectId,
    DateTime periodEnd,
  ) async {
    final data = jsonObject(
      await _client.get(
        'progress-billings/preview/',
        query: {
          'project': '$projectId',
          'period_end': JsonUtils.fromDate(periodEnd),
        },
      ),
    );
    return BillingComputation(
      pctAccomplished: JsonUtils.toDouble(data['pct_accomplished']),
      grossEarned: _money(data['gross_earned']),
      lessPrevious: _money(data['less_previous']),
      lessDpRecoupment: _money(data['less_dp_recoupment']),
      lessRetention: _money(data['less_retention']),
    );
  }

  @override
  Future<ProgressBilling> createBilling(
    int projectId,
    DateTime periodEnd, {
    required int userId,
  }) async => _billing(
    await _client.post(
      'progress-billings/',
      // The billing number, the money and the status are server-owned.
      body: {
        'project_id': projectId,
        'period_end': JsonUtils.fromDate(periodEnd),
      },
    ),
  );

  @override
  Future<ProgressBilling> submitBilling(int id, {required int userId}) =>
      _move(id, 'submit');

  @override
  Future<ProgressBilling> cancelBilling(int id, {required int userId}) =>
      _move(id, 'withdraw');

  @override
  Future<ProgressBilling> clientApprove(int id, {required int userId}) =>
      _move(id, 'client-approve');

  @override
  Future<ProgressBilling> clientDispute(
    int id, {
    required int userId,
    required String reason,
  }) => _move(id, 'client-dispute', body: {'reason': reason.trim()});

  @override
  Future<Payment> recordPayment(
    int billingId, {
    required double amount,
    required DateTime paidOn,
    required PaymentMethod method,
    String? referenceNo,
    required int userId,
  }) async {
    final reference = referenceNo?.trim();
    final data = await _client.post(
      'progress-billings/$billingId/payments/',
      body: {
        'amount': amount,
        'paid_on': JsonUtils.fromDate(paidOn),
        'method': method.apiValue,
        // An absent reference is no reference: an empty one is noise.
        if (reference != null && reference.isNotEmpty) 'reference_no': reference,
      },
    );
    return Payment.fromJson(jsonObject(data));
  }

  @override
  Future<List<Payment>> getPayments({List<int>? projectIds}) async {
    // A payment carries no project: a wider list is matched through the
    // billings the server scoped to the caller.
    Set<int>? billingIds;
    if (projectIds != null) {
      if (projectIds.isEmpty) return const [];
      if (projectIds.length > 1) {
        billingIds = {
          for (final billing in await getBillings(projectIds: projectIds))
            billing.id,
        };
      }
    }
    final rows = await _client.getRows(
      'client-payments/',
      query: _oneProject(projectIds),
    );
    return [
      for (final row in rows)
        if (Payment.fromJson(row) case final payment
            when billingIds == null || billingIds.contains(payment.progressBillingId))
          payment,
    ];
  }

  /// `billed` is the net due over billings sent to the client, `collected` the
  /// payments received. The route adds up one project; a wider list adds up
  /// the same server figures here rather than asking for the wrong total.
  @override
  Future<BilledSummary> billedSummary({List<int>? projectIds}) async {
    if (projectIds != null && projectIds.isEmpty) {
      return const BilledSummary(billed: 0, collected: 0);
    }
    if (projectIds == null || projectIds.length == 1) {
      final data = jsonObject(
        await _client.get(
          'billing-summary/',
          query: _oneProject(projectIds),
        ),
      );
      return BilledSummary(
        billed: _money(data['billed']),
        collected: _money(data['collected']),
      );
    }
    final billings = await getBillings(projectIds: projectIds);
    final payments = await getPayments(projectIds: projectIds);
    return BilledSummary(
      billed: billings
          .where((billing) => billing.status.isBilled)
          .fold(0, (sum, billing) => sum + billing.netDue),
      collected: payments.fold(0, (sum, payment) => sum + payment.amount),
    );
  }

  // ---- Variation orders

  @override
  Future<List<VariationOrder>> getVariationOrders({
    List<int>? projectIds,
    List<VariationOrderStatus>? statuses,
  }) async {
    final rows = await _client.getRows(
      'variation-orders/',
      query: {
        ..._oneProject(projectIds),
        if (statuses != null && statuses.length == 1)
          'status': statuses.single.apiValue,
      },
    );
    return [
      for (final row in rows)
        if (VariationOrder.fromJson(row) case final order
            when _inProjects(order.projectId, projectIds) &&
                (statuses == null || statuses.contains(order.status)))
          order,
    ];
  }

  @override
  Future<VariationOrderDetail?> getVariationOrder(int id) async {
    final data = await _client.get(
      'variation-orders/$id/',
      notFoundAsNull: true,
    );
    if (data == null) return null;
    final row = jsonObject(data);
    return VariationOrderDetail(
      VariationOrder.fromJson(row),
      _history(row['history']),
    );
  }

  /// Creates the VO when its id is 0, edits a **proposed** one by `PATCH`
  /// otherwise. The amount is only sent by a role that holds the money view:
  /// a site engineer proposes the change, and the server stores `0.00` for a
  /// new proposal and never reprices an existing one.
  @override
  Future<VariationOrder> saveVariationOrder(
    VariationOrder vo, {
    required int userId,
  }) async {
    final body = {
      'project_id': vo.projectId,
      'type': vo.type.apiValue,
      'description': vo.description.trim(),
      'days_impact': vo.daysImpact,
      if (_client.seesFinance) 'amount': vo.amount,
    };
    final data = vo.id == 0
        ? await _client.post('variation-orders/', body: body)
        : await _client.patch('variation-orders/${vo.id}/', body: body);
    return VariationOrder.fromJson(jsonObject(data));
  }

  @override
  Future<VariationOrder> submitVariationOrder(
    int id, {
    required int userId,
  }) => _voMove(id, 'submit');

  @override
  Future<VariationOrder> ownerRejectVo(
    int id, {
    required int userId,
    required String reason,
  }) => _voMove(id, 'owner-reject', body: {'reason': reason.trim()});

  /// Client approval applies the VO to the contract amount and the target end
  /// date inside the server's transaction, so the project is never patched
  /// from here.
  @override
  Future<VariationOrder> clientApproveVo(int id, {required int userId}) =>
      _voMove(id, 'client-approve');

  @override
  Future<VariationOrder> clientRejectVo(
    int id, {
    required int userId,
    required String reason,
  }) => _voMove(id, 'client-reject', body: {'reason': reason.trim()});

  // ---- Retention

  @override
  Future<({double held, double released})> retentionFor(int projectId) async {
    final data = jsonObject(
      await _client.get('retention/', query: {'project': '$projectId'}),
    );
    return (held: _money(data['held']), released: _money(data['released']));
  }

  @override
  Future<List<RetentionRelease>> getRetentionReleases({
    List<int>? projectIds,
  }) async {
    final rows = await _client.getRows(
      'retention-releases/',
      query: _oneProject(projectIds),
    );
    return [
      for (final row in rows)
        if (RetentionRelease.fromJson(row) case final release
            when _inProjects(release.projectId, projectIds))
          release,
    ];
  }

  @override
  Future<RetentionRelease> releaseRetention(
    int projectId, {
    required double amount,
    required DateTime releasedOn,
    required PaymentMethod method,
    String? referenceNo,
    required int userId,
  }) async {
    final reference = referenceNo?.trim();
    final data = await _client.post(
      'retention-releases/',
      body: {
        'project_id': projectId,
        'amount': amount,
        'released_on': JsonUtils.fromDate(releasedOn),
        'method': method.apiValue,
        if (reference != null && reference.isNotEmpty) 'reference_no': reference,
      },
    );
    return RetentionRelease.fromJson(jsonObject(data));
  }

  // ---- Helpers

  /// A billing move: each transition is its own audited route.
  Future<ProgressBilling> _move(int id, String move, {Object? body}) async =>
      _billing(
        await _client.post('progress-billings/$id/$move/', body: body),
      );

  Future<VariationOrder> _voMove(int id, String move, {Object? body}) async =>
      VariationOrder.fromJson(
        jsonObject(await _client.post('variation-orders/$id/$move/', body: body)),
      );

  ProgressBilling _billing(Object? data) =>
      ProgressBilling.fromJson(jsonObject(data));

  List<AuditLog> _history(Object? rows) => [
    for (final row in jsonRows(rows)) AuditLog.fromJson(row),
  ];

  /// A computed money figure. The routes that carry one are finance-only, so
  /// an omitted key is a broken response for a finance role; a redacted role
  /// never gets this far (the server answers `403` first) and reading it as
  /// zero would be money nobody computed.
  double _money(Object? value) =>
      JsonUtils.toFinanceDouble(value, omitted: !_client.seesFinance);

  Map<String, dynamic> _oneProject(List<int>? projectIds) => {
    if (projectIds != null && projectIds.length == 1)
      'project': '${projectIds.single}',
  };

  bool _inProjects(int projectId, List<int>? projectIds) =>
      projectIds == null || projectIds.contains(projectId);
}

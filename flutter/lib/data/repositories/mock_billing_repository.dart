import '../../routes/routes.dart';
import '../models/app_role.dart';
import '../models/payment.dart';
import '../models/payment_method.dart';
import '../models/progress_billing.dart';
import '../models/project.dart';
import '../models/retention_release.dart';
import '../models/variation_order.dart';
import '../services/billing_calculator.dart';
import '../services/billing_rules.dart';
import '../services/business_rule_exception.dart';
import '../services/notification_service.dart';
import '../services/progress_calculator.dart';
import 'audit_log_repository.dart';
import 'billing_repository.dart';
import 'mock_billing_data.dart';
import 'project_repository.dart';
import 'schedule_repository.dart';
import 'user_repository.dart';

class MockBillingRepository implements BillingRepository {
  MockBillingRepository({
    required ProjectRepository projects,
    required ScheduleRepository schedule,
    required UserRepository users,
    required AuditLogRepository auditLog,
    NotificationService? notifications,
    DateTime Function()? clock,
  }) : _projects = projects,
       _schedule = schedule,
       _users = users,
       _auditLog = auditLog,
       _notifications = notifications,
       _clock = clock ?? DateTime.now;

  final ProjectRepository _projects;
  final ScheduleRepository _schedule;
  final UserRepository _users;
  final AuditLogRepository _auditLog;
  final NotificationService? _notifications;
  final DateTime Function() _clock;

  final _billings = [...MockBillingData.billings];
  final _payments = [...MockBillingData.payments];
  final _vos = [...MockBillingData.variationOrders];
  final _releases = <RetentionRelease>[];

  static int _next(Iterable<int> ids) =>
      ids.fold(0, (m, id) => id > m ? id : m) + 1;

  // ---- Billings

  @override
  Future<List<ProgressBilling>> getBillings({
    List<int>? projectIds,
    List<BillingStatus>? statuses,
  }) async =>
      _billings
          .where(
            (b) =>
                (projectIds == null || projectIds.contains(b.projectId)) &&
                (statuses == null || statuses.contains(b.status)),
          )
          .toList()
        ..sort((a, b) => b.periodEnd.compareTo(a.periodEnd));

  @override
  Future<BillingDetail?> getBilling(int id) async {
    final i = _billings.indexWhere((b) => b.id == id);
    if (i < 0) return null;
    return BillingDetail(
      billing: _billings[i],
      payments: _payments.where((p) => p.progressBillingId == id).toList(),
      history: await _auditLog.getFor('progress_billing', id),
    );
  }

  /// Gross earned on the latest billing that was not rejected.
  double _previousGross(int projectId) => _billings
      .where(
        (b) =>
            b.projectId == projectId &&
            b.status != BillingStatus.rejected &&
            b.status != BillingStatus.draft,
      )
      .fold(0.0, (m, b) => b.grossEarned > m ? b.grossEarned : m);

  DateTime? _previousPeriodEnd(int projectId) {
    DateTime? latest;
    for (final b in _billings) {
      if (b.projectId != projectId || b.status == BillingStatus.rejected) {
        continue;
      }
      if (latest == null || b.periodEnd.isAfter(latest)) latest = b.periodEnd;
    }
    return latest;
  }

  Future<Project> _project(int id) async {
    final p = await _projects.getProject(id);
    if (p == null) throw const BusinessRuleException('Project not found.');
    return p;
  }

  @override
  Future<BillingComputation> previewBilling(
    int projectId,
    DateTime periodEnd,
  ) async {
    final project = await _project(projectId);
    final progress = computeProjectProgress(
      project: project,
      categories: await _schedule.getCategories(projectId),
      todos: await _schedule.getTodos(projectId),
      asOf: periodEnd,
    );
    return computeBilling(
      project: project,
      progress: progress,
      previousGross: _previousGross(projectId),
    );
  }

  @override
  Future<ProgressBilling> createBilling(
    int projectId,
    DateTime periodEnd, {
    required int userId,
  }) async {
    final project = await _project(projectId);
    BillingRules.enforce(BillingRules.requireBillable(project));
    await _requireRole(projectId, userId, AppRole.pm);
    if (_billings.any((b) => b.projectId == projectId && b.status.inProgress)) {
      throw const BusinessRuleException(
        'This project already has a billing in progress. It must be paid or '
        'rejected first.',
      );
    }
    BillingRules.enforce(
      BillingRules.validatePeriodEnd(
        periodEnd,
        _clock(),
        _previousPeriodEnd(projectId),
      ),
    );
    final c = await previewBilling(projectId, periodEnd);
    BillingRules.enforce(
      BillingRules.validateAccomplishment(c.pctAccomplished, c.thisPeriod),
    );
    final billing = ProgressBilling(
      id: _next(_billings.map((b) => b.id)),
      projectId: projectId,
      billingNo:
          _billings
              .where((b) => b.projectId == projectId)
              .fold(0, (m, b) => b.billingNo > m ? b.billingNo : m) +
          1,
      periodEnd: DateTime(periodEnd.year, periodEnd.month, periodEnd.day),
      pctAccomplished: c.pctAccomplished,
      grossEarned: c.grossEarned,
      lessPrevious: c.lessPrevious,
      lessDpRecoupment: c.lessDpRecoupment,
      lessRetention: c.lessRetention,
      netDue: c.netDue,
      status: BillingStatus.draft,
      createdAt: _clock(),
    );
    _billings.add(billing);
    await _log(userId, 'billing_created', billing.id);
    return billing;
  }

  @override
  Future<ProgressBilling> submitBilling(int id, {required int userId}) async {
    final b = _billing(id);
    if (b.status != BillingStatus.draft && b.status != BillingStatus.disputed) {
      throw const BusinessRuleException(
        'Only draft or disputed billings can be submitted.',
      );
    }
    await _requireRole(b.projectId, userId, AppRole.pm);
    final project = await _project(b.projectId);
    await _notifyRole(
      AppRole.owner,
      'billing',
      'Progress billing #${b.billingNo} for ${project.code} needs your approval.',
      AppRoutes.billing(id),
    );
    return _setStatus(
      id,
      BillingStatus.pendingOwner,
      userId,
      'billing_submitted',
    );
  }

  @override
  Future<ProgressBilling> cancelBilling(int id, {required int userId}) async {
    final b = _billing(id);
    if (b.status != BillingStatus.draft && b.status != BillingStatus.disputed) {
      throw const BusinessRuleException(
        'Only draft or disputed billings can be withdrawn.',
      );
    }
    await _requireRole(b.projectId, userId, AppRole.pm);
    return _setStatus(id, BillingStatus.rejected, userId, 'billing_withdrawn');
  }

  @override
  Future<ProgressBilling> ownerApprove(int id, {required int userId}) async {
    final b = _billing(id);
    _expect(b.status, BillingStatus.pendingOwner);
    final project = await _project(b.projectId);
    await _notifications?.notifyProjectRole(
      b.projectId,
      AppRole.client,
      type: 'billing',
      message:
          'Progress billing #${b.billingNo} for ${project.name} is ready for '
          'your review.',
      link: AppRoutes.clientBilling(id),
    );
    return _setStatus(
      id,
      BillingStatus.pendingClient,
      userId,
      'billing_owner_approved',
    );
  }

  @override
  Future<ProgressBilling> ownerReject(
    int id, {
    required int userId,
    required String reason,
  }) async {
    final b = _billing(id);
    _expect(b.status, BillingStatus.pendingOwner);
    _requireReason(reason);
    await _notifications?.notifyProjectRole(
      b.projectId,
      AppRole.pm,
      type: 'billing',
      message: 'Billing #${b.billingNo} was rejected by the owner: $reason',
      link: AppRoutes.billing(id),
    );
    return _setStatus(
      id,
      BillingStatus.rejected,
      userId,
      'billing_owner_rejected',
      reason: reason,
    );
  }

  @override
  Future<ProgressBilling> clientApprove(int id, {required int userId}) async {
    final b = _billing(id);
    _expect(b.status, BillingStatus.pendingClient);
    await _requireRole(b.projectId, userId, AppRole.client);
    await _notifyRole(
      AppRole.accountant,
      'billing',
      'The client approved billing #${b.billingNo}; record their payment.',
      AppRoutes.billing(id),
    );
    return _setStatus(
      id,
      BillingStatus.approved,
      userId,
      'billing_client_approved',
    );
  }

  @override
  Future<ProgressBilling> clientDispute(
    int id, {
    required int userId,
    required String reason,
  }) async {
    final b = _billing(id);
    _expect(b.status, BillingStatus.pendingClient);
    await _requireRole(b.projectId, userId, AppRole.client);
    _requireReason(reason);
    await _notifications?.notifyProjectRole(
      b.projectId,
      AppRole.pm,
      type: 'billing',
      message: 'The client disputed billing #${b.billingNo}: $reason',
      link: AppRoutes.billing(id),
    );
    return _setStatus(
      id,
      BillingStatus.disputed,
      userId,
      'billing_client_disputed',
      reason: reason,
    );
  }

  @override
  Future<Payment> recordPayment(
    int billingId, {
    required double amount,
    required DateTime paidOn,
    required PaymentMethod method,
    String? referenceNo,
    required int userId,
  }) async {
    final detail = (await getBilling(billingId))!;
    if (detail.billing.status != BillingStatus.approved) {
      throw const BusinessRuleException(
        'Payments are recorded only on client-approved billings.',
      );
    }
    BillingRules.enforce(BillingRules.validatePayment(amount, detail.balance));
    final payment = Payment(
      id: _next(_payments.map((p) => p.id)),
      progressBillingId: billingId,
      amount: amount,
      paidOn: paidOn,
      method: method,
      referenceNo: referenceNo,
      createdAt: _clock(),
    );
    _payments.add(payment);
    await _log(
      userId,
      'billing_payment_recorded',
      billingId,
      details: {'amount': amount},
    );
    if (detail.balance - amount <= 0.005) {
      await _setStatus(billingId, BillingStatus.paid, userId, 'billing_paid');
    }
    return payment;
  }

  @override
  Future<List<Payment>> getPayments({List<int>? projectIds}) async {
    final ids = {
      for (final b in _billings)
        if (projectIds == null || projectIds.contains(b.projectId)) b.id,
    };
    return _payments.where((p) => ids.contains(p.progressBillingId)).toList()
      ..sort((a, b) => b.paidOn.compareTo(a.paidOn));
  }

  @override
  Future<BilledSummary> billedSummary({List<int>? projectIds}) async {
    final billed = _billings.where(
      (b) =>
          b.status.isBilled &&
          (projectIds == null || projectIds.contains(b.projectId)),
    );
    final payments = await getPayments(projectIds: projectIds);
    return BilledSummary(
      billed: billed.fold(0, (s, b) => s + b.netDue),
      collected: payments.fold(0, (s, p) => s + p.amount),
    );
  }

  // ---- Variation orders

  @override
  Future<List<VariationOrder>> getVariationOrders({
    List<int>? projectIds,
    List<VariationOrderStatus>? statuses,
  }) async =>
      _vos
          .where(
            (v) =>
                (projectIds == null || projectIds.contains(v.projectId)) &&
                (statuses == null || statuses.contains(v.status)),
          )
          .toList()
        ..sort(
          (a, b) => (b.createdAt ?? DateTime(0)).compareTo(
            a.createdAt ?? DateTime(0),
          ),
        );

  @override
  Future<VariationOrderDetail?> getVariationOrder(int id) async {
    final i = _vos.indexWhere((v) => v.id == id);
    if (i < 0) return null;
    return VariationOrderDetail(
      _vos[i],
      await _auditLog.getFor('variation_order', id),
    );
  }

  double _totalBilled(int projectId) => _previousGross(projectId);

  @override
  Future<VariationOrder> saveVariationOrder(
    VariationOrder vo, {
    required int userId,
  }) async {
    final project = await _project(vo.projectId);
    final isPm = await _projects.isAssigned(vo.projectId, userId, AppRole.pm);
    final isSite = await _projects.isAssigned(
      vo.projectId,
      userId,
      AppRole.siteEngineer,
    );
    if (!isPm && !isSite) {
      throw const BusinessRuleException(
        'Only the PM or site engineer of this project can raise a VO.',
      );
    }
    BillingRules.enforce(BillingRules.validateVoDescription(vo.description));
    BillingRules.enforce(BillingRules.validateVoAmount(vo.type, vo.amount));
    final amount = BillingRules.signedAmount(vo.type, vo.amount);
    BillingRules.enforce(
      BillingRules.validateContractAfterVo(
        contractAmount: project.contractAmount,
        voAmount: amount,
        totalBilled: _totalBilled(vo.projectId),
      ),
    );
    if (vo.id == 0) {
      final count = _vos.where((v) => v.projectId == vo.projectId).length;
      final created = vo.copyWith(
        id: _next(_vos.map((v) => v.id)),
        voNo: 'VO-${(count + 1).toString().padLeft(2, '0')}',
        amount: amount,
        description: vo.description.trim(),
        status: VariationOrderStatus.proposed,
      );
      _vos.add(created);
      await _logVo(userId, 'vo_proposed', created.id);
      if (!isPm) {
        await _notifications?.notifyProjectRole(
          vo.projectId,
          AppRole.pm,
          type: 'variation_order',
          message:
              '${created.voNo} was proposed for ${project.code}. Prepare it.',
          link: AppRoutes.variationOrder(created.id),
        );
      }
      return created;
    }
    final i = _voIndex(vo.id);
    if (_vos[i].status != VariationOrderStatus.proposed) {
      throw const BusinessRuleException('Only proposed VOs can be edited.');
    }
    final updated = _vos[i].copyWith(
      type: vo.type,
      description: vo.description.trim(),
      amount: amount,
      daysImpact: vo.daysImpact,
    );
    _vos[i] = updated;
    return updated;
  }

  @override
  Future<VariationOrder> submitVariationOrder(
    int id, {
    required int userId,
  }) async {
    final i = _voIndex(id);
    final vo = _vos[i];
    if (vo.status != VariationOrderStatus.proposed) {
      throw const BusinessRuleException('Only proposed VOs can be submitted.');
    }
    await _requireRole(vo.projectId, userId, AppRole.pm);
    _vos[i] = vo.copyWith(status: VariationOrderStatus.pendingOwner);
    await _logVo(userId, 'vo_submitted', id);
    await _notifyRole(
      AppRole.owner,
      'variation_order',
      '${vo.voNo} needs your approval.',
      AppRoutes.variationOrder(id),
    );
    return _vos[i];
  }

  @override
  Future<VariationOrder> ownerApproveVo(int id, {required int userId}) async {
    final i = _voIndex(id);
    final vo = _vos[i];
    if (vo.status != VariationOrderStatus.pendingOwner) {
      throw const BusinessRuleException(
        'This VO is not waiting for the owner.',
      );
    }
    _vos[i] = vo.copyWith(
      status: VariationOrderStatus.pendingClient,
      approvedByOwner: () => userId,
    );
    await _logVo(userId, 'vo_owner_approved', id);
    await _notifications?.notifyProjectRole(
      vo.projectId,
      AppRole.client,
      type: 'variation_order',
      message: '${vo.voNo} is waiting for your approval.',
      link: AppRoutes.clientVariationOrder(id),
    );
    return _vos[i];
  }

  @override
  Future<VariationOrder> ownerRejectVo(
    int id, {
    required int userId,
    required String reason,
  }) async {
    final i = _voIndex(id);
    if (_vos[i].status != VariationOrderStatus.pendingOwner) {
      throw const BusinessRuleException(
        'This VO is not waiting for the owner.',
      );
    }
    _requireReason(reason);
    _vos[i] = _vos[i].copyWith(status: VariationOrderStatus.rejected);
    await _logVo(userId, 'vo_owner_rejected', id, reason: reason);
    return _vos[i];
  }

  @override
  Future<VariationOrder> clientApproveVo(int id, {required int userId}) async {
    final i = _voIndex(id);
    final vo = _vos[i];
    if (vo.status != VariationOrderStatus.pendingClient) {
      throw const BusinessRuleException(
        'This VO is not waiting for the client.',
      );
    }
    await _requireRole(vo.projectId, userId, AppRole.client);
    final project = await _project(vo.projectId);
    BillingRules.enforce(
      BillingRules.validateContractAfterVo(
        contractAmount: project.contractAmount,
        voAmount: vo.amount,
        totalBilled: _totalBilled(vo.projectId),
      ),
    );
    await _projects.applyVariation(
      vo.projectId,
      amountDelta: vo.amount,
      daysImpact: vo.daysImpact,
    );
    _vos[i] = vo.copyWith(
      status: VariationOrderStatus.approved,
      approvedByClient: () => userId,
    );
    await _logVo(userId, 'vo_client_approved', id);
    await _notifications?.notifyProjectRole(
      vo.projectId,
      AppRole.pm,
      type: 'variation_order',
      message:
          '${vo.voNo} is approved. The contract amount and target end date '
          'are updated; adjust categories and to-dos.',
      link: AppRoutes.variationOrder(id),
    );
    return _vos[i];
  }

  @override
  Future<VariationOrder> clientRejectVo(
    int id, {
    required int userId,
    required String reason,
  }) async {
    final i = _voIndex(id);
    final vo = _vos[i];
    if (vo.status != VariationOrderStatus.pendingClient) {
      throw const BusinessRuleException(
        'This VO is not waiting for the client.',
      );
    }
    await _requireRole(vo.projectId, userId, AppRole.client);
    _requireReason(reason);
    _vos[i] = vo.copyWith(status: VariationOrderStatus.rejected);
    await _logVo(userId, 'vo_client_rejected', id, reason: reason);
    return _vos[i];
  }

  // ---- Retention

  @override
  Future<({double held, double released})> retentionFor(int projectId) async {
    final held = _billings
        .where(
          (b) =>
              b.projectId == projectId &&
              (b.status == BillingStatus.approved ||
                  b.status == BillingStatus.paid),
        )
        .fold(0.0, (s, b) => s + b.lessRetention);
    final released = _releases
        .where((r) => r.projectId == projectId)
        .fold(0.0, (s, r) => s + r.amount);
    return (held: held, released: released);
  }

  @override
  Future<List<RetentionRelease>> getRetentionReleases({
    List<int>? projectIds,
  }) async => _releases
      .where((r) => projectIds == null || projectIds.contains(r.projectId))
      .toList();

  @override
  Future<RetentionRelease> releaseRetention(
    int projectId, {
    required double amount,
    required DateTime releasedOn,
    required PaymentMethod method,
    String? referenceNo,
    required int userId,
  }) async {
    final project = await _project(projectId);
    BillingRules.enforce(BillingRules.canReleaseRetention(project));
    final r = await retentionFor(projectId);
    BillingRules.enforce(
      BillingRules.validatePayment(amount, r.held - r.released),
    );
    final release = RetentionRelease(
      id: _next(_releases.map((x) => x.id)),
      projectId: projectId,
      amount: amount,
      releasedOn: releasedOn,
      method: method,
      referenceNo: referenceNo,
      createdAt: _clock(),
    );
    _releases.add(release);
    await _auditLog.record(
      userId: userId,
      action: 'retention_released',
      entity: 'project',
      entityId: projectId,
      details: {'amount': amount},
    );
    return release;
  }

  // ---- Helpers

  ProgressBilling _billing(int id) => _billings.firstWhere(
    (b) => b.id == id,
    orElse: () => throw const BusinessRuleException('Billing not found.'),
  );

  void _expect(BillingStatus actual, BillingStatus expected) {
    if (actual != expected) {
      throw BusinessRuleException(
        'This billing is ${actual.label.toLowerCase()}, not '
        '${expected.label.toLowerCase()}.',
      );
    }
  }

  void _requireReason(String reason) {
    if (reason.trim().isEmpty) {
      throw const BusinessRuleException('Give a reason.');
    }
  }

  Future<void> _requireRole(int projectId, int userId, AppRole role) async {
    if (!await _projects.isAssigned(projectId, userId, role)) {
      throw BusinessRuleException(
        'Only the ${role.label.toLowerCase()} of this project can do this.',
      );
    }
  }

  Future<ProgressBilling> _setStatus(
    int id,
    BillingStatus status,
    int userId,
    String action, {
    String? reason,
  }) async {
    final i = _billings.indexWhere((b) => b.id == id);
    _billings[i] = _billings[i].copyWith(status: status);
    await _log(userId, action, id, details: {'reason': ?reason?.trim()});
    return _billings[i];
  }

  Future<void> _log(
    int userId,
    String action,
    int id, {
    Map<String, dynamic> details = const {},
  }) => _auditLog.record(
    userId: userId,
    action: action,
    entity: 'progress_billing',
    entityId: id,
    details: details,
  );

  Future<void> _logVo(int userId, String action, int id, {String? reason}) =>
      _auditLog.record(
        userId: userId,
        action: action,
        entity: 'variation_order',
        entityId: id,
        details: {'reason': ?reason?.trim()},
      );

  int _voIndex(int id) {
    final i = _vos.indexWhere((v) => v.id == id);
    if (i < 0) throw const BusinessRuleException('Variation order not found.');
    return i;
  }

  Future<void> _notifyRole(
    AppRole role,
    String type,
    String message,
    String link,
  ) async {
    final users = await _users.getUsersWithRole(role);
    await _notifications?.notify(
      users.map((u) => u.id),
      type: type,
      message: message,
      link: link,
    );
  }
}

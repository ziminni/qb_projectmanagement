import '../models/audit_log.dart';
import '../models/payment.dart';
import '../models/payment_method.dart';
import '../models/progress_billing.dart';
import '../models/retention_release.dart';
import '../models/variation_order.dart';
import '../services/billing_calculator.dart';

class BillingDetail {
  const BillingDetail({
    required this.billing,
    required this.payments,
    required this.history,
  });

  final ProgressBilling billing;
  final List<Payment> payments;

  /// Approvals, rejections and disputes with their reasons, oldest first.
  final List<AuditLog> history;

  double get paid => payments.fold(0, (s, p) => s + p.amount);
  double get balance => billing.netDue - paid;
}

class VariationOrderDetail {
  const VariationOrderDetail(this.order, this.history);

  final VariationOrder order;
  final List<AuditLog> history;
}

class BilledSummary {
  const BilledSummary({required this.billed, required this.collected});

  /// Net due on billings sent to clients.
  final double billed;
  final double collected;
}

abstract interface class BillingRepository {
  Future<List<ProgressBilling>> getBillings({
    List<int>? projectIds,
    List<BillingStatus>? statuses,
  });

  Future<BillingDetail?> getBilling(int id);

  /// What a billing for [periodEnd] would show, without saving it.
  Future<BillingComputation> previewBilling(int projectId, DateTime periodEnd);

  /// PM generates a Draft billing from verified progress.
  Future<ProgressBilling> createBilling(
    int projectId,
    DateTime periodEnd, {
    required int userId,
  });

  /// Owner sends a draft (or a disputed billing) to the client.
  Future<ProgressBilling> submitBilling(int id, {required int userId});

  /// Owner withdraws a draft or disputed billing.
  Future<ProgressBilling> cancelBilling(int id, {required int userId});

  Future<ProgressBilling> clientApprove(int id, {required int userId});

  Future<ProgressBilling> clientDispute(
    int id, {
    required int userId,
    required String reason,
  });

  /// Accountant records the client's payment; a billing paid in full is
  /// marked Paid.
  Future<Payment> recordPayment(
    int billingId, {
    required double amount,
    required DateTime paidOn,
    required PaymentMethod method,
    String? referenceNo,
    required int userId,
  });

  Future<List<Payment>> getPayments({List<int>? projectIds});

  Future<BilledSummary> billedSummary({List<int>? projectIds});

  Future<List<VariationOrder>> getVariationOrders({
    List<int>? projectIds,
    List<VariationOrderStatus>? statuses,
  });

  Future<VariationOrderDetail?> getVariationOrder(int id);

  /// Site engineer or owner proposes a VO (id 0) or edits a proposed one.
  Future<VariationOrder> saveVariationOrder(
    VariationOrder vo, {
    required int userId,
  });

  /// Owner sends a proposed VO to the client.
  Future<VariationOrder> submitVariationOrder(int id, {required int userId});

  /// Owner turns down a proposed VO.
  Future<VariationOrder> ownerRejectVo(
    int id, {
    required int userId,
    required String reason,
  });

  /// Client approval applies the VO to the contract amount and schedule.
  Future<VariationOrder> clientApproveVo(int id, {required int userId});

  Future<VariationOrder> clientRejectVo(
    int id, {
    required int userId,
    required String reason,
  });

  /// Retention withheld on approved billings, less releases.
  Future<({double held, double released})> retentionFor(int projectId);

  Future<List<RetentionRelease>> getRetentionReleases({List<int>? projectIds});

  Future<RetentionRelease> releaseRetention(
    int projectId, {
    required double amount,
    required DateTime releasedOn,
    required PaymentMethod method,
    String? referenceNo,
    required int userId,
  });
}

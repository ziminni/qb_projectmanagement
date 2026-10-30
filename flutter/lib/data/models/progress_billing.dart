import 'json_utils.dart';

enum BillingStatus implements JsonEnum {
  draft('draft', 'Draft'),
  pendingClient('pending_client', 'Waiting for client'),
  disputed('disputed', 'Disputed'),
  approved('approved', 'Approved by client'),
  paid('paid', 'Paid'),
  rejected('rejected', 'Withdrawn');

  const BillingStatus(this.apiValue, this.label);

  @override
  final String apiValue;
  final String label;

  /// Not yet Paid or Rejected; only one per project at a time.
  bool get inProgress =>
      this != BillingStatus.paid && this != BillingStatus.rejected;

  /// Sent to the client, so it counts as billed.
  bool get isBilled => const [
    BillingStatus.pendingClient,
    BillingStatus.disputed,
    BillingStatus.approved,
    BillingStatus.paid,
  ].contains(this);

  static BillingStatus fromJson(Object? raw) => enumFromApi(values, raw);

  String toJson() => apiValue;
}

/// A row in `progress_billings`. [grossEarned] is cumulative to the period
/// end; the deductions apply to this period's portion.
class ProgressBilling {
  const ProgressBilling({
    required this.id,
    required this.projectId,
    required this.billingNo,
    required this.periodEnd,
    required this.pctAccomplished,
    required this.grossEarned,
    required this.lessPrevious,
    required this.lessDpRecoupment,
    required this.lessRetention,
    required this.netDue,
    required this.status,
    this.createdAt,
    this.updatedAt,
  });

  final int id;
  final int projectId;
  final int billingNo;
  final DateTime periodEnd;

  /// Cumulative accomplishment, 0–1.
  final double pctAccomplished;
  final double grossEarned;
  final double lessPrevious;
  final double lessDpRecoupment;
  final double lessRetention;
  final double netDue;
  final BillingStatus status;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Gross earned this period, before deductions.
  double get thisPeriod => grossEarned - lessPrevious;

  ProgressBilling copyWith({BillingStatus? status}) => ProgressBilling(
    id: id,
    projectId: projectId,
    billingNo: billingNo,
    periodEnd: periodEnd,
    pctAccomplished: pctAccomplished,
    grossEarned: grossEarned,
    lessPrevious: lessPrevious,
    lessDpRecoupment: lessDpRecoupment,
    lessRetention: lessRetention,
    netDue: netDue,
    status: status ?? this.status,
    createdAt: createdAt,
    updatedAt: DateTime.now(),
  );

  factory ProgressBilling.fromJson(Map<String, dynamic> json) =>
      ProgressBilling(
        id: json['id'] as int,
        projectId: json['project_id'] as int,
        billingNo: json['billing_no'] as int,
        periodEnd: JsonUtils.toDate(json['period_end']),
        pctAccomplished: JsonUtils.toDouble(json['pct_accomplished']),
        grossEarned: JsonUtils.toDouble(json['gross_earned']),
        lessPrevious: JsonUtils.toDouble(json['less_previous']),
        lessDpRecoupment: JsonUtils.toDouble(json['less_dp_recoupment']),
        lessRetention: JsonUtils.toDouble(json['less_retention']),
        netDue: JsonUtils.toDouble(json['net_due']),
        status: BillingStatus.fromJson(json['status']),
        createdAt: JsonUtils.toDateOrNull(json['created_at']),
        updatedAt: JsonUtils.toDateOrNull(json['updated_at']),
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'project_id': projectId,
    'billing_no': billingNo,
    'period_end': JsonUtils.fromDate(periodEnd),
    'pct_accomplished': pctAccomplished,
    'gross_earned': grossEarned,
    'less_previous': lessPrevious,
    'less_dp_recoupment': lessDpRecoupment,
    'less_retention': lessRetention,
    'net_due': netDue,
    'status': status.toJson(),
    'created_at': JsonUtils.fromDateTimeOrNull(createdAt),
    'updated_at': JsonUtils.fromDateTimeOrNull(updatedAt),
  };
}

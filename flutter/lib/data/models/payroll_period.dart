import 'json_utils.dart';

enum PayrollStatus implements JsonEnum {
  open('open', 'Open'),
  verified('verified', 'Verified by PM'),
  processed('processed', 'Processed');

  const PayrollStatus(this.apiValue, this.label);

  @override
  final String apiValue;
  final String label;

  static PayrollStatus fromJson(Object? raw) => enumFromApi(values, raw);

  String toJson() => apiValue;
}

/// A row in `payroll_periods`: a weekly or 15-day cut-off for one project.
class PayrollPeriod {
  const PayrollPeriod({
    required this.id,
    required this.projectId,
    required this.periodStart,
    required this.periodEnd,
    required this.status,
    this.createdAt,
    this.updatedAt,
  });

  final int id;
  final int projectId;
  final DateTime periodStart;
  final DateTime periodEnd;
  final PayrollStatus status;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool contains(DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    return !d.isBefore(periodStart) && !d.isAfter(periodEnd);
  }

  PayrollPeriod copyWith({PayrollStatus? status}) => PayrollPeriod(
    id: id,
    projectId: projectId,
    periodStart: periodStart,
    periodEnd: periodEnd,
    status: status ?? this.status,
    createdAt: createdAt,
    updatedAt: DateTime.now(),
  );

  factory PayrollPeriod.fromJson(Map<String, dynamic> json) => PayrollPeriod(
    id: json['id'] as int,
    projectId: json['project_id'] as int,
    periodStart: JsonUtils.toDate(json['period_start']),
    periodEnd: JsonUtils.toDate(json['period_end']),
    status: PayrollStatus.fromJson(json['status']),
    createdAt: JsonUtils.toDateOrNull(json['created_at']),
    updatedAt: JsonUtils.toDateOrNull(json['updated_at']),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'project_id': projectId,
    'period_start': JsonUtils.fromDate(periodStart),
    'period_end': JsonUtils.fromDate(periodEnd),
    'status': status.toJson(),
    'created_at': JsonUtils.fromDateTimeOrNull(createdAt),
    'updated_at': JsonUtils.fromDateTimeOrNull(updatedAt),
  };
}

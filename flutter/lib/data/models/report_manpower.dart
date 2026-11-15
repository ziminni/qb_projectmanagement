import 'json_utils.dart';

/// A row in `report_manpower`: headcount per trade on a report.
class ReportManpower {
  const ReportManpower({
    required this.id,
    required this.dailyReportId,
    required this.trade,
    required this.headcount,
    this.createdAt,
    this.updatedAt,
  });

  final int id;
  final int dailyReportId;
  final String trade;
  final int headcount;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory ReportManpower.fromJson(Map<String, dynamic> json) => ReportManpower(
    id: json['id'] as int,
    dailyReportId: json['daily_report_id'] as int,
    trade: json['trade'] as String,
    headcount: json['headcount'] as int,
    createdAt: JsonUtils.toDateOrNull(json['created_at']),
    updatedAt: JsonUtils.toDateOrNull(json['updated_at']),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'daily_report_id': dailyReportId,
    'trade': trade,
    'headcount': headcount,
    'created_at': JsonUtils.fromDateTimeOrNull(createdAt),
    'updated_at': JsonUtils.fromDateTimeOrNull(updatedAt),
  };
}

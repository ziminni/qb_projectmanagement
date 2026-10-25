import 'json_utils.dart';

/// A row in `equipment_logs`. [dailyReportId] is an addition to the design
/// document so equipment use can be recorded in the daily report.
class EquipmentLog {
  const EquipmentLog({
    required this.id,
    required this.equipmentId,
    required this.projectId,
    required this.logDate,
    required this.hoursUsed,
    this.dailyReportId,
    this.createdAt,
    this.updatedAt,
  });

  final int id;
  final int equipmentId;
  final int projectId;
  final DateTime logDate;
  final double hoursUsed;
  final int? dailyReportId;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory EquipmentLog.fromJson(Map<String, dynamic> json) => EquipmentLog(
    id: json['id'] as int,
    equipmentId: json['equipment_id'] as int,
    projectId: json['project_id'] as int,
    logDate: JsonUtils.toDate(json['log_date']),
    hoursUsed: JsonUtils.toDouble(json['hours_used']),
    dailyReportId: json['daily_report_id'] as int?,
    createdAt: JsonUtils.toDateOrNull(json['created_at']),
    updatedAt: JsonUtils.toDateOrNull(json['updated_at']),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'equipment_id': equipmentId,
    'project_id': projectId,
    'log_date': JsonUtils.fromDate(logDate),
    'hours_used': hoursUsed,
    'daily_report_id': dailyReportId,
    'created_at': JsonUtils.fromDateTimeOrNull(createdAt),
    'updated_at': JsonUtils.fromDateTimeOrNull(updatedAt),
  };
}

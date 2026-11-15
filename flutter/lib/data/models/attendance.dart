import 'json_utils.dart';

enum AttendanceStatus implements JsonEnum {
  present('present', 'Present', 1),
  halfDay('half_day', 'Half day', 0.5),
  absent('absent', 'Absent', 0);

  const AttendanceStatus(this.apiValue, this.label, this.dayFraction);

  @override
  final String apiValue;
  final String label;

  /// Days of pay this status earns.
  final double dayFraction;

  static AttendanceStatus fromJson(Object? raw) => enumFromApi(values, raw);

  String toJson() => apiValue;
}

/// A row in `attendance`: one worker on one project on one day.
class Attendance {
  const Attendance({
    required this.id,
    required this.projectId,
    required this.workerId,
    required this.workDate,
    required this.status,
    this.overtimeHours = 0,
    required this.recordedBy,
    this.createdAt,
    this.updatedAt,
  });

  final int id;
  final int projectId;
  final int workerId;
  final DateTime workDate;
  final AttendanceStatus status;
  final double overtimeHours;
  final int recordedBy;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory Attendance.fromJson(Map<String, dynamic> json) => Attendance(
    id: json['id'] as int,
    projectId: json['project_id'] as int,
    workerId: json['worker_id'] as int,
    workDate: JsonUtils.toDate(json['work_date']),
    status: AttendanceStatus.fromJson(json['status']),
    overtimeHours: JsonUtils.toDouble(json['overtime_hours'] ?? 0),
    recordedBy: json['recorded_by'] as int,
    createdAt: JsonUtils.toDateOrNull(json['created_at']),
    updatedAt: JsonUtils.toDateOrNull(json['updated_at']),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'project_id': projectId,
    'worker_id': workerId,
    'work_date': JsonUtils.fromDate(workDate),
    'status': status.toJson(),
    'overtime_hours': overtimeHours,
    'recorded_by': recordedBy,
    'created_at': JsonUtils.fromDateTimeOrNull(createdAt),
    'updated_at': JsonUtils.fromDateTimeOrNull(updatedAt),
  };
}

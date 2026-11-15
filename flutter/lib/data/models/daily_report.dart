import 'json_utils.dart';

enum DailyReportStatus implements JsonEnum {
  draft('draft', 'Draft'),
  submitted('submitted', 'Submitted'),
  approved('approved', 'Approved'),
  returned('returned', 'Returned');

  const DailyReportStatus(this.apiValue, this.label);

  @override
  final String apiValue;
  final String label;

  /// Reports are editable only while Draft or Returned.
  bool get isEditable =>
      this == DailyReportStatus.draft || this == DailyReportStatus.returned;

  static DailyReportStatus fromJson(Object? raw) => enumFromApi(values, raw);

  String toJson() => apiValue;
}

enum Weather implements JsonEnum {
  sunny('sunny', 'Sunny'),
  cloudy('cloudy', 'Cloudy'),
  lightRain('light_rain', 'Light rain'),
  heavyRain('heavy_rain', 'Heavy rain'),
  typhoon('typhoon', 'Typhoon');

  const Weather(this.apiValue, this.label);

  @override
  final String apiValue;
  final String label;

  static Weather fromJson(Object? raw) => enumFromApi(values, raw);

  String toJson() => apiValue;
}

/// A row in `daily_reports`. [toolboxMeetingHeld] is an addition for the
/// design document's safety-compliance checkbox.
class DailyReport {
  const DailyReport({
    required this.id,
    required this.projectId,
    required this.reportDate,
    required this.weather,
    required this.status,
    required this.submittedBy,
    this.reviewedBy,
    this.remarks,
    this.toolboxMeetingHeld = false,
    this.createdAt,
    this.updatedAt,
  });

  final int id;
  final int projectId;
  final DateTime reportDate;
  final Weather weather;
  final DailyReportStatus status;

  /// The site engineer who wrote the report.
  final int submittedBy;
  final int? reviewedBy;

  /// The PM's remarks; required when a report is returned.
  final String? remarks;
  final bool toolboxMeetingHeld;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  DailyReport copyWith({
    int? id,
    DateTime? reportDate,
    Weather? weather,
    DailyReportStatus? status,
    int? Function()? reviewedBy,
    String? Function()? remarks,
    bool? toolboxMeetingHeld,
    DateTime? updatedAt,
  }) => DailyReport(
    id: id ?? this.id,
    projectId: projectId,
    reportDate: reportDate ?? this.reportDate,
    weather: weather ?? this.weather,
    status: status ?? this.status,
    submittedBy: submittedBy,
    reviewedBy: reviewedBy != null ? reviewedBy() : this.reviewedBy,
    remarks: remarks != null ? remarks() : this.remarks,
    toolboxMeetingHeld: toolboxMeetingHeld ?? this.toolboxMeetingHeld,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  factory DailyReport.fromJson(Map<String, dynamic> json) => DailyReport(
    id: json['id'] as int,
    projectId: json['project_id'] as int,
    reportDate: JsonUtils.toDate(json['report_date']),
    weather: Weather.fromJson(json['weather']),
    status: DailyReportStatus.fromJson(json['status']),
    submittedBy: json['submitted_by'] as int,
    reviewedBy: json['reviewed_by'] as int?,
    remarks: json['remarks'] as String?,
    toolboxMeetingHeld: json['toolbox_meeting_held'] as bool? ?? false,
    createdAt: JsonUtils.toDateOrNull(json['created_at']),
    updatedAt: JsonUtils.toDateOrNull(json['updated_at']),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'project_id': projectId,
    'report_date': JsonUtils.fromDate(reportDate),
    'weather': weather.toJson(),
    'status': status.toJson(),
    'submitted_by': submittedBy,
    'reviewed_by': reviewedBy,
    'remarks': remarks,
    'toolbox_meeting_held': toolboxMeetingHeld,
    'created_at': JsonUtils.fromDateTimeOrNull(createdAt),
    'updated_at': JsonUtils.fromDateTimeOrNull(updatedAt),
  };
}

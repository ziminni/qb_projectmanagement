import 'json_utils.dart';

enum IssueType implements JsonEnum {
  delay('delay', 'Delay'),
  safety('safety', 'Safety / incident'),
  other('other', 'Other');

  const IssueType(this.apiValue, this.label);

  @override
  final String apiValue;
  final String label;

  static IssueType fromJson(Object? raw) => enumFromApi(values, raw);

  String toJson() => apiValue;
}

enum IssueReason implements JsonEnum {
  rainTyphoon('rain_typhoon', 'Rain / typhoon'),
  material('material', 'Material'),
  labor('labor', 'Labor'),
  client('client', 'Client'),
  other('other', 'Other');

  const IssueReason(this.apiValue, this.label);

  @override
  final String apiValue;
  final String label;

  static IssueReason fromJson(Object? raw) => enumFromApi(values, raw);

  String toJson() => apiValue;
}

/// A row in `issues`. Rain and typhoon delays support time-extension
/// requests through [daysLost].
class Issue {
  const Issue({
    required this.id,
    required this.projectId,
    this.dailyReportId,
    required this.type,
    required this.reason,
    required this.description,
    this.daysLost = 0,
    this.createdAt,
    this.updatedAt,
  });

  final int id;
  final int projectId;
  final int? dailyReportId;
  final IssueType type;
  final IssueReason reason;
  final String description;
  final double daysLost;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory Issue.fromJson(Map<String, dynamic> json) => Issue(
    id: json['id'] as int,
    projectId: json['project_id'] as int,
    dailyReportId: json['daily_report_id'] as int?,
    type: IssueType.fromJson(json['type']),
    reason: IssueReason.fromJson(json['reason']),
    description: json['description'] as String,
    daysLost: JsonUtils.toDouble(json['days_lost'] ?? 0),
    createdAt: JsonUtils.toDateOrNull(json['created_at']),
    updatedAt: JsonUtils.toDateOrNull(json['updated_at']),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'project_id': projectId,
    'daily_report_id': dailyReportId,
    'type': type.toJson(),
    'reason': reason.toJson(),
    'description': description,
    'days_lost': daysLost,
    'created_at': JsonUtils.fromDateTimeOrNull(createdAt),
    'updated_at': JsonUtils.fromDateTimeOrNull(updatedAt),
  };
}

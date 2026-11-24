import 'json_utils.dart';

enum ProjectStatus implements JsonEnum {
  /// Sent to the client; the site engineer gets it once the client accepts.
  requested('requested', 'Waiting for client'),

  /// The client asked for revisions; the owner edits and sends it again.
  changesRequested('changes_requested', 'Changes requested'),

  /// The client accepted; waiting for the site engineer.
  siteEngineerPending('site_engineer_pending', 'Waiting for site engineer'),
  accepted('accepted', 'Accepted'),
  ongoing('ongoing', 'Ongoing'),
  completed('completed', 'Completed'),
  closed('closed', 'Closed'),
  onHold('on_hold', 'On hold');

  const ProjectStatus(this.apiValue, this.label);

  @override
  final String apiValue;
  final String label;

  static ProjectStatus fromJson(Object? raw) => enumFromApi(values, raw);

  String toJson() => apiValue;
}

/// A row in `projects`.
class Project {
  const Project({
    required this.id,
    required this.code,
    required this.name,
    required this.location,
    this.latitude,
    this.longitude,
    required this.clientId,
    required this.contractAmount,
    required this.downPaymentPct,
    required this.retentionPct,
    required this.startDate,
    this.timelineStartDate,
    required this.targetEndDate,
    this.actualEndDate,
    required this.status,
    this.createdAt,
    this.updatedAt,
  });

  final int id;
  final String code;
  final String name;
  final String location;

  /// The site's map pin, when the owner placed one.
  final double? latitude;
  final double? longitude;
  final int clientId;
  final double contractAmount;
  final double downPaymentPct;
  final double retentionPct;
  final DateTime startDate;
  final DateTime? timelineStartDate;
  final DateTime targetEndDate;
  final DateTime? actualEndDate;
  final ProjectStatus status;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory Project.fromJson(Map<String, dynamic> json) => Project(
    id: json['id'] as int,
    code: json['code'] as String,
    name: json['name'] as String,
    location: json['location'] as String,
    latitude: JsonUtils.toDoubleOrNull(json['latitude']),
    longitude: JsonUtils.toDoubleOrNull(json['longitude']),
    clientId: json['client_id'] as int,
    // The server omits these for roles that may not see money; an absent key
    // is 0 rather than a crash (decision 06, ruling 1).
    contractAmount: JsonUtils.toDouble(json['contract_amount'] ?? 0),
    downPaymentPct: JsonUtils.toDouble(json['down_payment_pct'] ?? 0),
    retentionPct: JsonUtils.toDouble(json['retention_pct'] ?? 0),
    startDate: JsonUtils.toDate(json['start_date']),
    timelineStartDate: JsonUtils.toDateOrNull(json['timeline_start_date']),
    targetEndDate: JsonUtils.toDate(json['target_end_date']),
    actualEndDate: JsonUtils.toDateOrNull(json['actual_end_date']),
    status: ProjectStatus.fromJson(json['status']),
    createdAt: JsonUtils.toDateOrNull(json['created_at']),
    updatedAt: JsonUtils.toDateOrNull(json['updated_at']),
  );

  bool get hasPin => latitude != null && longitude != null;

  Map<String, dynamic> toJson() => {
    'id': id,
    'code': code,
    'name': name,
    'location': location,
    'latitude': latitude,
    'longitude': longitude,
    'client_id': clientId,
    'contract_amount': contractAmount,
    'down_payment_pct': downPaymentPct,
    'retention_pct': retentionPct,
    'start_date': JsonUtils.fromDate(startDate),
    'timeline_start_date': JsonUtils.fromDateOrNull(timelineStartDate),
    'target_end_date': JsonUtils.fromDate(targetEndDate),
    'actual_end_date': JsonUtils.fromDateOrNull(actualEndDate),
    'status': status.toJson(),
    'created_at': JsonUtils.fromDateTimeOrNull(createdAt),
    'updated_at': JsonUtils.fromDateTimeOrNull(updatedAt),
  };
}

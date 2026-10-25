import 'json_utils.dart';

enum ProjectStatus implements JsonEnum {
  draft('draft', 'Draft'),
  bidding('bidding', 'Bidding'),
  awarded('awarded', 'Awarded'),
  ongoing('ongoing', 'Ongoing'),
  completed('completed', 'Completed'),
  closed('closed', 'Closed'),
  onHold('on_hold', 'On hold'),
  lostBid('lost_bid', 'Lost bid');

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
    required this.clientId,
    required this.contractAmount,
    required this.downPaymentPct,
    required this.retentionPct,
    required this.startDate,
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
  final int clientId;
  final double contractAmount;
  final double downPaymentPct;
  final double retentionPct;
  final DateTime startDate;
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
    clientId: json['client_id'] as int,
    contractAmount: JsonUtils.toDouble(json['contract_amount']),
    downPaymentPct: JsonUtils.toDouble(json['down_payment_pct']),
    retentionPct: JsonUtils.toDouble(json['retention_pct']),
    startDate: JsonUtils.toDate(json['start_date']),
    targetEndDate: JsonUtils.toDate(json['target_end_date']),
    actualEndDate: JsonUtils.toDateOrNull(json['actual_end_date']),
    status: ProjectStatus.fromJson(json['status']),
    createdAt: JsonUtils.toDateOrNull(json['created_at']),
    updatedAt: JsonUtils.toDateOrNull(json['updated_at']),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'code': code,
    'name': name,
    'location': location,
    'client_id': clientId,
    'contract_amount': contractAmount,
    'down_payment_pct': downPaymentPct,
    'retention_pct': retentionPct,
    'start_date': JsonUtils.fromDate(startDate),
    'target_end_date': JsonUtils.fromDate(targetEndDate),
    'actual_end_date': JsonUtils.fromDateOrNull(actualEndDate),
    'status': status.toJson(),
    'created_at': JsonUtils.fromDateTimeOrNull(createdAt),
    'updated_at': JsonUtils.fromDateTimeOrNull(updatedAt),
  };
}

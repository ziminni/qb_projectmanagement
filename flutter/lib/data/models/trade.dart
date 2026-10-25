import 'json_utils.dart';

/// A row in `trades`. Not in the design document's table list; it backs the
/// admin's trades master list used by daily-report manpower and workers.
class Trade {
  const Trade({
    required this.id,
    required this.name,
    this.createdAt,
    this.updatedAt,
  });

  final int id;
  final String name;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory Trade.fromJson(Map<String, dynamic> json) => Trade(
    id: json['id'] as int,
    name: json['name'] as String,
    createdAt: JsonUtils.toDateOrNull(json['created_at']),
    updatedAt: JsonUtils.toDateOrNull(json['updated_at']),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'created_at': JsonUtils.fromDateTimeOrNull(createdAt),
    'updated_at': JsonUtils.fromDateTimeOrNull(updatedAt),
  };
}

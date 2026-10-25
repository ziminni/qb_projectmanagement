import 'json_utils.dart';

/// A row in `categories`. Progress, status and weight are computed by
/// `computeProjectProgress`, never stored.
class Category {
  const Category({
    required this.id,
    required this.projectId,
    required this.name,
    this.budget,
    required this.sortOrder,
    this.createdAt,
    this.updatedAt,
  });

  final int id;
  final int projectId;
  final String name;

  /// Optional; categories without a budget fall back to equal weights.
  final double? budget;
  final int sortOrder;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get hasBudget => budget != null && budget! > 0;

  Category copyWith({
    int? id,
    String? name,
    double? Function()? budget,
    int? sortOrder,
    DateTime? updatedAt,
  }) => Category(
    id: id ?? this.id,
    projectId: projectId,
    name: name ?? this.name,
    budget: budget != null ? budget() : this.budget,
    sortOrder: sortOrder ?? this.sortOrder,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  factory Category.fromJson(Map<String, dynamic> json) => Category(
    id: json['id'] as int,
    projectId: json['project_id'] as int,
    name: json['name'] as String,
    budget: JsonUtils.toDoubleOrNull(json['budget']),
    sortOrder: json['sort_order'] as int,
    createdAt: JsonUtils.toDateOrNull(json['created_at']),
    updatedAt: JsonUtils.toDateOrNull(json['updated_at']),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'project_id': projectId,
    'name': name,
    'budget': budget,
    'sort_order': sortOrder,
    'created_at': JsonUtils.fromDateTimeOrNull(createdAt),
    'updated_at': JsonUtils.fromDateTimeOrNull(updatedAt),
  };
}

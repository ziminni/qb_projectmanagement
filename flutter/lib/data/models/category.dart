import 'json_utils.dart';

/// A row in `categories`. Progress, status and weight are computed by
/// `computeProjectProgress`, never stored.
class Category {
  const Category({
    required this.id,
    required this.projectId,
    required this.name,
    this.budget,
    this.laborBudget,
    this.equipmentBudget,
    this.materialBudget,
    this.dupaBreakdown,
    this.weight,
    this.plannedWeeks,
    this.plannedDays,
    this.dayToStart,
    this.startDate,
    this.endDate,
    required this.sortOrder,
    this.createdAt,
    this.updatedAt,
  });

  final int id;
  final int projectId;
  final String name;

  /// Optional; categories without a budget fall back to equal weights.
  final double? budget;
  final double? laborBudget;
  final double? equipmentBudget;
  final double? materialBudget;
  final Map<String, dynamic>? dupaBreakdown;

  /// The category's share of the project (0–1), computed by the server from
  /// the budget so a role that may not see budgets still gets the same
  /// progress bar. Null offline, where [budget] carries the weight instead.
  final double? weight;
  final String? plannedWeeks;
  final int? plannedDays;
  final int? dayToStart;
  final DateTime? startDate;
  final DateTime? endDate;
  final int sortOrder;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get hasBudget => budget != null && budget! > 0;
  bool get hasCostBreakdown =>
      laborBudget != null || equipmentBudget != null || materialBudget != null;
  bool get hasDupaBreakdown =>
      dupaBreakdown != null && dupaBreakdown!.isNotEmpty;

  Category copyWith({
    int? id,
    String? name,
    double? Function()? budget,
    String? Function()? plannedWeeks,
    int? Function()? plannedDays,
    int? Function()? dayToStart,
    DateTime? Function()? startDate,
    DateTime? Function()? endDate,
    int? sortOrder,
    DateTime? updatedAt,
  }) => Category(
    id: id ?? this.id,
    projectId: projectId,
    name: name ?? this.name,
    budget: budget != null ? budget() : this.budget,
    laborBudget: laborBudget,
    equipmentBudget: equipmentBudget,
    materialBudget: materialBudget,
    dupaBreakdown: dupaBreakdown,
    weight: weight,
    plannedWeeks: plannedWeeks != null ? plannedWeeks() : this.plannedWeeks,
    plannedDays: plannedDays != null ? plannedDays() : this.plannedDays,
    dayToStart: dayToStart != null ? dayToStart() : this.dayToStart,
    startDate: startDate != null ? startDate() : this.startDate,
    endDate: endDate != null ? endDate() : this.endDate,
    sortOrder: sortOrder ?? this.sortOrder,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  factory Category.fromJson(Map<String, dynamic> json) => Category(
    id: json['id'] as int,
    projectId: json['project_id'] as int,
    name: json['name'] as String,
    budget: JsonUtils.toDoubleOrNull(json['budget']),
    laborBudget: JsonUtils.toDoubleOrNull(json['labor_budget']),
    equipmentBudget: JsonUtils.toDoubleOrNull(json['equipment_budget']),
    materialBudget: JsonUtils.toDoubleOrNull(json['material_budget']),
    dupaBreakdown: json['dupa_breakdown'] is Map<String, dynamic>
        ? json['dupa_breakdown'] as Map<String, dynamic>
        : null,
    weight: JsonUtils.toDoubleOrNull(json['weight']),
    plannedWeeks: (json['planned_weeks'] as String?)?.trim().isEmpty == true
        ? null
        : json['planned_weeks'] as String?,
    plannedDays: json['planned_days'] as int?,
    dayToStart: json['day_to_start'] as int?,
    startDate: JsonUtils.toDateOrNull(json['start_date']),
    endDate: JsonUtils.toDateOrNull(json['end_date']),
    sortOrder: json['sort_order'] as int,
    createdAt: JsonUtils.toDateOrNull(json['created_at']),
    updatedAt: JsonUtils.toDateOrNull(json['updated_at']),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'project_id': projectId,
    'name': name,
    'budget': budget,
    'weight': weight,
    'planned_weeks': plannedWeeks ?? '',
    'planned_days': plannedDays,
    'day_to_start': dayToStart,
    'start_date': JsonUtils.fromDateOrNull(startDate),
    'end_date': JsonUtils.fromDateOrNull(endDate),
    'sort_order': sortOrder,
    'created_at': JsonUtils.fromDateTimeOrNull(createdAt),
    'updated_at': JsonUtils.fromDateTimeOrNull(updatedAt),
  };
}

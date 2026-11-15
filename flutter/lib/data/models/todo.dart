import 'json_utils.dart';

/// A row in `todos`. Only verified to-dos count toward progress.
class Todo {
  const Todo({
    required this.id,
    required this.categoryId,
    required this.title,
    required this.startDate,
    required this.endDate,
    this.isDone = false,
    this.doneBy,
    this.doneAt,
    this.isVerified = false,
    this.verifiedBy,
    this.verifiedAt,
    this.dailyReportId,
    this.createdAt,
    this.updatedAt,
  });

  final int id;
  final int categoryId;
  final String title;
  final DateTime startDate;
  final DateTime endDate;
  final bool isDone;
  final int? doneBy;
  final DateTime? doneAt;
  final bool isVerified;
  final int? verifiedBy;
  final DateTime? verifiedAt;
  final int? dailyReportId;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Done on site but not yet verified by the PM.
  bool get isAwaitingVerification => isDone && !isVerified;

  Todo copyWith({
    int? id,
    int? categoryId,
    String? title,
    DateTime? startDate,
    DateTime? endDate,
    bool? isDone,
    int? Function()? doneBy,
    DateTime? Function()? doneAt,
    bool? isVerified,
    int? Function()? verifiedBy,
    DateTime? Function()? verifiedAt,
    int? Function()? dailyReportId,
    DateTime? updatedAt,
  }) => Todo(
    id: id ?? this.id,
    categoryId: categoryId ?? this.categoryId,
    title: title ?? this.title,
    startDate: startDate ?? this.startDate,
    endDate: endDate ?? this.endDate,
    isDone: isDone ?? this.isDone,
    doneBy: doneBy != null ? doneBy() : this.doneBy,
    doneAt: doneAt != null ? doneAt() : this.doneAt,
    isVerified: isVerified ?? this.isVerified,
    verifiedBy: verifiedBy != null ? verifiedBy() : this.verifiedBy,
    verifiedAt: verifiedAt != null ? verifiedAt() : this.verifiedAt,
    dailyReportId: dailyReportId != null ? dailyReportId() : this.dailyReportId,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  factory Todo.fromJson(Map<String, dynamic> json) => Todo(
    id: json['id'] as int,
    categoryId: json['category_id'] as int,
    title: json['title'] as String,
    startDate: JsonUtils.toDate(json['start_date']),
    endDate: JsonUtils.toDate(json['end_date']),
    isDone: json['is_done'] as bool? ?? false,
    doneBy: json['done_by'] as int?,
    doneAt: JsonUtils.toDateOrNull(json['done_at']),
    isVerified: json['is_verified'] as bool? ?? false,
    verifiedBy: json['verified_by'] as int?,
    verifiedAt: JsonUtils.toDateOrNull(json['verified_at']),
    dailyReportId: json['daily_report_id'] as int?,
    createdAt: JsonUtils.toDateOrNull(json['created_at']),
    updatedAt: JsonUtils.toDateOrNull(json['updated_at']),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'category_id': categoryId,
    'title': title,
    'start_date': JsonUtils.fromDate(startDate),
    'end_date': JsonUtils.fromDate(endDate),
    'is_done': isDone,
    'done_by': doneBy,
    'done_at': JsonUtils.fromDateTimeOrNull(doneAt),
    'is_verified': isVerified,
    'verified_by': verifiedBy,
    'verified_at': JsonUtils.fromDateTimeOrNull(verifiedAt),
    'daily_report_id': dailyReportId,
    'created_at': JsonUtils.fromDateTimeOrNull(createdAt),
    'updated_at': JsonUtils.fromDateTimeOrNull(updatedAt),
  };
}

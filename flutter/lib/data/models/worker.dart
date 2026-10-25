import 'json_utils.dart';

/// A row in `workers`.
class Worker {
  const Worker({
    required this.id,
    required this.fullName,
    required this.trade,
    required this.dailyRate,
    this.sssNo,
    this.philhealthNo,
    this.pagibigNo,
    this.isActive = true,
    this.createdAt,
    this.updatedAt,
  });

  final int id;
  final String fullName;
  final String trade;
  final double dailyRate;
  final String? sssNo;
  final String? philhealthNo;
  final String? pagibigNo;
  final bool isActive;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  Worker copyWith({
    int? id,
    String? fullName,
    String? trade,
    double? dailyRate,
    String? Function()? sssNo,
    String? Function()? philhealthNo,
    String? Function()? pagibigNo,
    bool? isActive,
  }) => Worker(
    id: id ?? this.id,
    fullName: fullName ?? this.fullName,
    trade: trade ?? this.trade,
    dailyRate: dailyRate ?? this.dailyRate,
    sssNo: sssNo != null ? sssNo() : this.sssNo,
    philhealthNo: philhealthNo != null ? philhealthNo() : this.philhealthNo,
    pagibigNo: pagibigNo != null ? pagibigNo() : this.pagibigNo,
    isActive: isActive ?? this.isActive,
    createdAt: createdAt,
    updatedAt: DateTime.now(),
  );

  factory Worker.fromJson(Map<String, dynamic> json) => Worker(
    id: json['id'] as int,
    fullName: json['full_name'] as String,
    trade: json['trade'] as String,
    dailyRate: JsonUtils.toDouble(json['daily_rate']),
    sssNo: json['sss_no'] as String?,
    philhealthNo: json['philhealth_no'] as String?,
    pagibigNo: json['pagibig_no'] as String?,
    isActive: json['is_active'] as bool? ?? true,
    createdAt: JsonUtils.toDateOrNull(json['created_at']),
    updatedAt: JsonUtils.toDateOrNull(json['updated_at']),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'full_name': fullName,
    'trade': trade,
    'daily_rate': dailyRate,
    'sss_no': sssNo,
    'philhealth_no': philhealthNo,
    'pagibig_no': pagibigNo,
    'is_active': isActive,
    'created_at': JsonUtils.fromDateTimeOrNull(createdAt),
    'updated_at': JsonUtils.fromDateTimeOrNull(updatedAt),
  };
}

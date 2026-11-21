import 'json_utils.dart';

/// A row in `workers`.
class Worker {
  const Worker({
    required this.id,
    required this.fullName,
    required this.trade,
    required this.dailyRate,
    this.cashAdvanceBalance = 0,
    this.address,
    this.phone,
    this.sssNo,
    this.philhealthNo,
    this.pagibigNo,
    this.isActive = true,
    this.dailyRateHidden = false,
    this.createdAt,
    this.updatedAt,
  });

  final int id;
  final String fullName;
  final String trade;
  final double dailyRate;

  /// Running cash advance (vale) balance that auto-deducts across paydays.
  final double cashAdvanceBalance;
  final String? address;
  final String? phone;

  /// True when the server withheld the wage because this role may not see
  /// money: [dailyRate] is then 0 because there was nothing to decode, not a
  /// rate anyone quoted (phase-4 contract, "absence is not authoritative
  /// zero").
  final bool dailyRateHidden;
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
    double? cashAdvanceBalance,
    String? Function()? address,
    String? Function()? phone,
    String? Function()? sssNo,
    String? Function()? philhealthNo,
    String? Function()? pagibigNo,
    bool? isActive,
    bool? dailyRateHidden,
  }) => Worker(
    id: id ?? this.id,
    fullName: fullName ?? this.fullName,
    trade: trade ?? this.trade,
    dailyRate: dailyRate ?? this.dailyRate,
    cashAdvanceBalance: cashAdvanceBalance ?? this.cashAdvanceBalance,
    address: address != null ? address() : this.address,
    phone: phone != null ? phone() : this.phone,
    sssNo: sssNo != null ? sssNo() : this.sssNo,
    philhealthNo: philhealthNo != null ? philhealthNo() : this.philhealthNo,
    pagibigNo: pagibigNo != null ? pagibigNo() : this.pagibigNo,
    isActive: isActive ?? this.isActive,
    dailyRateHidden: dailyRateHidden ?? this.dailyRateHidden,
    createdAt: createdAt,
    updatedAt: DateTime.now(),
  );

  /// [rateHidden] is what a role without finance access receives: the server
  /// drops `daily_rate` and the government identifiers rather than sending a
  /// fictional zero (phase-4 contract).
  factory Worker.fromJson(
    Map<String, dynamic> json, {
    bool rateHidden = false,
  }) => Worker(
    id: json['id'] as int,
    fullName: json['full_name'] as String,
    trade: json['trade'] as String,
    dailyRate: JsonUtils.toFinanceDouble(
      json['daily_rate'],
      omitted: rateHidden,
    ),
    cashAdvanceBalance: rateHidden
        ? 0
        : (json['cash_advance_balance'] == null
              ? 0
              : JsonUtils.toDouble(json['cash_advance_balance'])),
    address: json['address'] as String?,
    phone: json['phone'] as String?,
    sssNo: json['sss_no'] as String?,
    philhealthNo: json['philhealth_no'] as String?,
    pagibigNo: json['pagibig_no'] as String?,
    isActive: json['is_active'] as bool? ?? true,
    dailyRateHidden: rateHidden,
    createdAt: JsonUtils.toDateOrNull(json['created_at']),
    updatedAt: JsonUtils.toDateOrNull(json['updated_at']),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'full_name': fullName,
    'trade': trade,
    if (address != null) 'address': address,
    if (phone != null) 'phone': phone,
    // Never send a rate the server withheld: an omitted key is honest, 0 is a
    // wage nobody quoted.
    if (!dailyRateHidden) 'daily_rate': dailyRate,
    if (!dailyRateHidden) 'sss_no': sssNo,
    if (!dailyRateHidden) 'philhealth_no': philhealthNo,
    if (!dailyRateHidden) 'pagibig_no': pagibigNo,
    'is_active': isActive,
    'created_at': JsonUtils.fromDateTimeOrNull(createdAt),
    'updated_at': JsonUtils.fromDateTimeOrNull(updatedAt),
  };
}

import 'json_utils.dart';

/// A row in `company_settings`. Not in the design document's table list; it
/// holds the admin settings screen's values (default retention and down
/// payment %, behind-schedule threshold).
class CompanySettings {
  const CompanySettings({
    required this.id,
    required this.companyId,
    required this.defaultRetentionPct,
    required this.defaultDownPaymentPct,
    required this.behindScheduleThresholdPct,
    this.createdAt,
    this.updatedAt,
  });

  final int id;
  final int companyId;

  final double defaultRetentionPct;
  final double defaultDownPaymentPct;

  /// Percentage points behind plan before a project is flagged.
  final double behindScheduleThresholdPct;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  CompanySettings copyWith({
    double? defaultRetentionPct,
    double? defaultDownPaymentPct,
    double? behindScheduleThresholdPct,
    DateTime? updatedAt,
  }) => CompanySettings(
    id: id,
    companyId: companyId,
    defaultRetentionPct: defaultRetentionPct ?? this.defaultRetentionPct,
    defaultDownPaymentPct: defaultDownPaymentPct ?? this.defaultDownPaymentPct,
    behindScheduleThresholdPct:
        behindScheduleThresholdPct ?? this.behindScheduleThresholdPct,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  factory CompanySettings.fromJson(Map<String, dynamic> json) =>
      CompanySettings(
        id: json['id'] as int,
        companyId: json['company_id'] as int,
        defaultRetentionPct: JsonUtils.toDouble(json['default_retention_pct']),
        defaultDownPaymentPct: JsonUtils.toDouble(
          json['default_down_payment_pct'],
        ),
        behindScheduleThresholdPct: JsonUtils.toDouble(
          json['behind_schedule_threshold_pct'],
        ),
        createdAt: JsonUtils.toDateOrNull(json['created_at']),
        updatedAt: JsonUtils.toDateOrNull(json['updated_at']),
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'company_id': companyId,
    'default_retention_pct': defaultRetentionPct,
    'default_down_payment_pct': defaultDownPaymentPct,
    'behind_schedule_threshold_pct': behindScheduleThresholdPct,
    'created_at': JsonUtils.fromDateTimeOrNull(createdAt),
    'updated_at': JsonUtils.fromDateTimeOrNull(updatedAt),
  };
}

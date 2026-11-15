import 'json_utils.dart';

/// A row in `report_material_usage`. Approved usage is deducted from site
/// inventory.
class ReportMaterialUsage {
  const ReportMaterialUsage({
    required this.id,
    required this.dailyReportId,
    required this.materialId,
    required this.quantity,
    this.createdAt,
    this.updatedAt,
  });

  final int id;
  final int dailyReportId;
  final int materialId;
  final double quantity;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory ReportMaterialUsage.fromJson(Map<String, dynamic> json) =>
      ReportMaterialUsage(
        id: json['id'] as int,
        dailyReportId: json['daily_report_id'] as int,
        materialId: json['material_id'] as int,
        quantity: JsonUtils.toDouble(json['quantity']),
        createdAt: JsonUtils.toDateOrNull(json['created_at']),
        updatedAt: JsonUtils.toDateOrNull(json['updated_at']),
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'daily_report_id': dailyReportId,
    'material_id': materialId,
    'quantity': quantity,
    'created_at': JsonUtils.fromDateTimeOrNull(createdAt),
    'updated_at': JsonUtils.fromDateTimeOrNull(updatedAt),
  };
}

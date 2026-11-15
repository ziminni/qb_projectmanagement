import 'json_utils.dart';

/// A row in `report_photos`.
class ReportPhoto {
  const ReportPhoto({
    required this.id,
    required this.dailyReportId,
    required this.fileUrl,
    this.caption,
    this.latitude,
    this.longitude,
    this.takenAt,
    this.createdAt,
    this.updatedAt,
  });

  final int id;
  final int dailyReportId;
  final String fileUrl;
  final String? caption;
  final double? latitude;
  final double? longitude;
  final DateTime? takenAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory ReportPhoto.fromJson(Map<String, dynamic> json) => ReportPhoto(
    id: json['id'] as int,
    dailyReportId: json['daily_report_id'] as int,
    fileUrl: json['file_url'] as String,
    caption: json['caption'] as String?,
    latitude: JsonUtils.toDoubleOrNull(json['latitude']),
    longitude: JsonUtils.toDoubleOrNull(json['longitude']),
    takenAt: JsonUtils.toDateOrNull(json['taken_at']),
    createdAt: JsonUtils.toDateOrNull(json['created_at']),
    updatedAt: JsonUtils.toDateOrNull(json['updated_at']),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'daily_report_id': dailyReportId,
    'file_url': fileUrl,
    'caption': caption,
    'latitude': latitude,
    'longitude': longitude,
    'taken_at': JsonUtils.fromDateTimeOrNull(takenAt),
    'created_at': JsonUtils.fromDateTimeOrNull(createdAt),
    'updated_at': JsonUtils.fromDateTimeOrNull(updatedAt),
  };
}

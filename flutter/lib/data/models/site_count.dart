import 'json_utils.dart';

/// A row in `site_counts`: one material counted on site before a material
/// request. The site engineer must count every material the system thinks
/// is on site, so the owner sees both figures before ordering more.
class SiteCount {
  const SiteCount({
    required this.id,
    required this.materialRequestId,
    this.materialId,
    required this.name,
    required this.unit,
    required this.expected,
    required this.counted,
  });

  final int id;
  final int materialRequestId;

  /// Null for materials bought outside the price list.
  final int? materialId;
  final String name;
  final String unit;

  /// On hand by the system: received − damaged − used on approved reports.
  final double expected;

  /// What the site engineer actually counted.
  final double counted;

  double get difference => counted - expected;

  factory SiteCount.fromJson(Map<String, dynamic> json) => SiteCount(
    id: json['id'] as int,
    materialRequestId: json['material_request_id'] as int,
    materialId: json['material_id'] as int?,
    name: json['name'] as String,
    unit: json['unit'] as String? ?? '',
    expected: JsonUtils.toDouble(json['expected']),
    counted: JsonUtils.toDouble(json['counted']),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'material_request_id': materialRequestId,
    'material_id': materialId,
    'name': name,
    'unit': unit,
    'expected': expected,
    'counted': counted,
  };
}

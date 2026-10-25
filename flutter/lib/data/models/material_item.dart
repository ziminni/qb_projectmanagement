import 'json_utils.dart';

/// A row in `materials`. Named `MaterialItem` to avoid clashing with
/// Flutter's `Material` widget.
class MaterialItem {
  const MaterialItem({
    required this.id,
    required this.name,
    required this.unit,
    required this.defaultUnitCost,
    this.storeSku,
    this.createdAt,
    this.updatedAt,
  });

  final int id;
  final String name;
  final String unit;
  final double defaultUnitCost;

  /// For the future hardware store link.
  final String? storeSku;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  MaterialItem copyWith({
    int? id,
    String? name,
    String? unit,
    double? defaultUnitCost,
    String? Function()? storeSku,
    DateTime? updatedAt,
  }) => MaterialItem(
    id: id ?? this.id,
    name: name ?? this.name,
    unit: unit ?? this.unit,
    defaultUnitCost: defaultUnitCost ?? this.defaultUnitCost,
    storeSku: storeSku != null ? storeSku() : this.storeSku,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  factory MaterialItem.fromJson(Map<String, dynamic> json) => MaterialItem(
    id: json['id'] as int,
    name: json['name'] as String,
    unit: json['unit'] as String,
    defaultUnitCost: JsonUtils.toDouble(json['default_unit_cost']),
    storeSku: json['store_sku'] as String?,
    createdAt: JsonUtils.toDateOrNull(json['created_at']),
    updatedAt: JsonUtils.toDateOrNull(json['updated_at']),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'unit': unit,
    'default_unit_cost': defaultUnitCost,
    'store_sku': storeSku,
    'created_at': JsonUtils.fromDateTimeOrNull(createdAt),
    'updated_at': JsonUtils.fromDateTimeOrNull(updatedAt),
  };
}

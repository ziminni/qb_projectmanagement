import 'json_utils.dart';

enum EquipmentOwnership implements JsonEnum {
  owned('owned', 'Owned'),
  rented('rented', 'Rented');

  const EquipmentOwnership(this.apiValue, this.label);

  @override
  final String apiValue;
  final String label;

  static EquipmentOwnership fromJson(Object? raw) => enumFromApi(values, raw);

  String toJson() => apiValue;
}

enum RateUnit implements JsonEnum {
  hour('hour', 'per hour'),
  day('day', 'per day');

  const RateUnit(this.apiValue, this.label);

  @override
  final String apiValue;
  final String label;

  static RateUnit fromJson(Object? raw) => enumFromApi(values, raw);

  String toJson() => apiValue;
}

/// A row in `equipment`.
class Equipment {
  const Equipment({
    required this.id,
    required this.name,
    required this.ownership,
    required this.rate,
    required this.rateUnit,
    this.createdAt,
    this.updatedAt,
  });

  final int id;
  final String name;
  final EquipmentOwnership ownership;
  final double rate;
  final RateUnit rateUnit;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Cost of [hours] of use. Day rates assume an 8-hour day.
  double costFor(double hours) =>
      rateUnit == RateUnit.hour ? rate * hours : rate * hours / 8;

  Equipment copyWith({
    int? id,
    String? name,
    EquipmentOwnership? ownership,
    double? rate,
    RateUnit? rateUnit,
    DateTime? updatedAt,
  }) => Equipment(
    id: id ?? this.id,
    name: name ?? this.name,
    ownership: ownership ?? this.ownership,
    rate: rate ?? this.rate,
    rateUnit: rateUnit ?? this.rateUnit,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  factory Equipment.fromJson(Map<String, dynamic> json) => Equipment(
    id: json['id'] as int,
    name: json['name'] as String,
    ownership: EquipmentOwnership.fromJson(json['ownership']),
    rate: JsonUtils.toDouble(json['rate']),
    rateUnit: RateUnit.fromJson(json['rate_unit']),
    createdAt: JsonUtils.toDateOrNull(json['created_at']),
    updatedAt: JsonUtils.toDateOrNull(json['updated_at']),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'ownership': ownership.toJson(),
    'rate': rate,
    'rate_unit': rateUnit.toJson(),
    'created_at': JsonUtils.fromDateTimeOrNull(createdAt),
    'updated_at': JsonUtils.fromDateTimeOrNull(updatedAt),
  };
}

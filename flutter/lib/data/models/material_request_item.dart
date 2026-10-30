import 'json_utils.dart';
import 'material_source.dart';

enum MaterialRequestItemStatus implements JsonEnum {
  pending('pending', 'Not ordered'),
  ordered('ordered', 'Ordered');

  const MaterialRequestItemStatus(this.apiValue, this.label);

  @override
  final String apiValue;
  final String label;

  static MaterialRequestItemStatus fromJson(Object? raw) =>
      enumFromApi(values, raw);

  String toJson() => apiValue;
}

/// A row in `material_request_items`. The owner sets [source] when it
/// orders the item; an item cannot be ordered without one.
class MaterialRequestItem {
  const MaterialRequestItem({
    required this.id,
    required this.materialRequestId,
    required this.materialId,
    required this.quantity,
    this.source,
    this.status = MaterialRequestItemStatus.pending,
    this.createdAt,
    this.updatedAt,
  });

  final int id;
  final int materialRequestId;
  final int materialId;
  final double quantity;
  final MaterialSource? source;
  final MaterialRequestItemStatus status;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  MaterialRequestItem copyWith({
    MaterialSource? source,
    MaterialRequestItemStatus? status,
  }) => MaterialRequestItem(
    id: id,
    materialRequestId: materialRequestId,
    materialId: materialId,
    quantity: quantity,
    source: source ?? this.source,
    status: status ?? this.status,
    createdAt: createdAt,
    updatedAt: DateTime.now(),
  );

  factory MaterialRequestItem.fromJson(Map<String, dynamic> json) =>
      MaterialRequestItem(
        id: json['id'] as int,
        materialRequestId: json['material_request_id'] as int,
        materialId: json['material_id'] as int,
        quantity: JsonUtils.toDouble(json['quantity']),
        source: MaterialSource.fromJsonOrNull(json['source']),
        status: MaterialRequestItemStatus.fromJson(json['status']),
        createdAt: JsonUtils.toDateOrNull(json['created_at']),
        updatedAt: JsonUtils.toDateOrNull(json['updated_at']),
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'material_request_id': materialRequestId,
    'material_id': materialId,
    'quantity': quantity,
    'source': source?.toJson(),
    'status': status.toJson(),
    'created_at': JsonUtils.fromDateTimeOrNull(createdAt),
    'updated_at': JsonUtils.fromDateTimeOrNull(updatedAt),
  };
}

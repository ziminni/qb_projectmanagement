import 'json_utils.dart';

/// Where an item is bought. Own-store orders are entered manually for now
/// and will later go to the hardware store POS through its API.
enum MaterialSource implements JsonEnum {
  ownStore('own_store', 'Own store'),
  external('external', 'Other supplier');

  const MaterialSource(this.apiValue, this.label);

  @override
  final String apiValue;
  final String label;

  static MaterialSource fromJson(Object? raw) => enumFromApi(values, raw);

  static MaterialSource? fromJsonOrNull(Object? raw) =>
      raw == null ? null : fromJson(raw);

  String toJson() => apiValue;
}

/// Shared JSON parsing helpers. Django serializes decimals as strings and
/// date-only fields as `yyyy-MM-dd`, so models parse through these.
abstract final class JsonUtils {
  static double toDouble(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.parse(value);
    throw FormatException('Expected a number, got $value');
  }

  static double? toDoubleOrNull(Object? value) =>
      value == null ? null : toDouble(value);

  static DateTime toDate(Object? value) => DateTime.parse(value as String);

  static DateTime? toDateOrNull(Object? value) =>
      value == null ? null : toDate(value);

  /// Serializes a date-only field.
  static String fromDate(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  static String? fromDateOrNull(DateTime? value) =>
      value == null ? null : fromDate(value);

  static String fromDateTime(DateTime value) => value.toUtc().toIso8601String();

  static String? fromDateTimeOrNull(DateTime? value) =>
      value == null ? null : fromDateTime(value);
}

/// Base for enums that serialize to a snake_case API value.
abstract interface class JsonEnum {
  String get apiValue;
}

T enumFromApi<T extends JsonEnum>(List<T> values, Object? raw) =>
    values.firstWhere(
      (v) => v.apiValue == raw,
      orElse: () => throw FormatException('Unknown value "$raw" for $T'),
    );

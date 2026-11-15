/// Parsing helpers for form fields.
abstract final class InputParsers {
  /// Parses a peso amount or quantity, ignoring commas, spaces and "₱".
  static double? amount(String? text) {
    final cleaned = (text ?? '').replaceAll(RegExp(r'[,\s₱]'), '');
    return cleaned.isEmpty ? null : double.tryParse(cleaned);
  }

  /// Text for an amount field: whole numbers without decimals.
  static String amountText(double? value) {
    if (value == null) return '';
    return value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(2);
  }

  static int? integer(String? text) =>
      int.tryParse((text ?? '').replaceAll(RegExp(r'[,\s]'), ''));

  /// Null for blank text, otherwise the trimmed text.
  static String? optional(String? text) {
    final t = text?.trim() ?? '';
    return t.isEmpty ? null : t;
  }
}

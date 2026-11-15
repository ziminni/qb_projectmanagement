import 'business_rule_exception.dart';

/// Validation for the company profile, settings and master lists.
abstract final class MasterDataRules {
  static final _tin = RegExp(r'^\d{3}-\d{3}-\d{3}(-\d{3,5})?$');
  static final _email = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  static String? required(String? value, String label) =>
      (value == null || value.trim().isEmpty) ? 'Enter the $label.' : null;

  /// BIR TIN: 000-000-000 with an optional branch code.
  static String? validateTin(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Enter the TIN.';
    if (!_tin.hasMatch(v)) return 'Use the format 000-000-000-000.';
    return null;
  }

  static String? validateOptionalEmail(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return null;
    return _email.hasMatch(v) ? null : 'Enter a valid email address.';
  }

  static String? validateAmount(double? value, String label) {
    if (value == null) return 'Enter the $label.';
    if (value < 0) return 'The $label cannot be negative.';
    return null;
  }

  static String? validatePercent(double? value, String label) {
    if (value == null) return 'Enter the $label.';
    if (value < 0 || value > 100) return 'The $label must be 0–100%.';
    return null;
  }

  /// Days until [expiry]; negative once expired.
  static int daysUntil(DateTime expiry, DateTime today) => DateTime(
    expiry.year,
    expiry.month,
    expiry.day,
  ).difference(DateTime(today.year, today.month, today.day)).inDays;

  /// Reminder shown when the PCAB license expires within 60 days.
  static String? pcabReminder(DateTime expiry, DateTime today) {
    final days = daysUntil(expiry, today);
    if (days < 0) {
      return 'The PCAB license expired ${-days} days ago. Renew it now.';
    }
    if (days == 0) return 'The PCAB license expires today.';
    if (days <= 60) return 'The PCAB license expires in $days days.';
    return null;
  }

  static void enforce(String? error) {
    if (error != null) throw BusinessRuleException(error);
  }
}

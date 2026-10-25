import '../models/daily_report.dart';
import 'business_rule_exception.dart';

/// Daily report rules from "Business rules and validations".
abstract final class DailyReportRules {
  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  /// No future dates.
  static String? validateDate(DateTime? date, DateTime today) {
    if (date == null) return 'Choose the report date.';
    if (_day(date).isAfter(_day(today))) {
      return 'A daily report cannot be dated in the future.';
    }
    return null;
  }

  static String? validateHeadcount(int? value) => (value == null || value <= 0)
      ? 'Headcount must be greater than 0.'
      : null;

  static String? validateQuantity(double? value) =>
      (value == null || value <= 0) ? 'Quantity must be greater than 0.' : null;

  static String? validateHours(double? value) {
    if (value == null || value <= 0) return 'Hours must be greater than 0.';
    if (value > 24) return 'Hours cannot exceed 24 in a day.';
    return null;
  }

  static String? validateDaysLost(double? value) =>
      (value == null || value < 0) ? 'Days lost cannot be negative.' : null;

  /// Editable only while Draft or Returned. Approved reports are locked.
  static String? canEdit(DailyReport report) => report.status.isEditable
      ? null
      : 'This report is ${report.status.label.toLowerCase()} and can no '
            'longer be edited.';

  static String? canSubmit(DailyReport report) => report.status.isEditable
      ? null
      : 'Only draft or returned reports can be submitted.';

  static String? canReview(DailyReport report) =>
      report.status == DailyReportStatus.submitted
      ? null
      : 'Only submitted reports can be approved or returned.';

  /// Returning a report requires remarks.
  static String? validateReturnRemarks(String? remarks) =>
      (remarks == null || remarks.trim().isEmpty)
      ? 'Add remarks so the site engineer knows what to fix.'
      : null;

  static void enforce(String? error) {
    if (error != null) throw BusinessRuleException(error);
  }
}

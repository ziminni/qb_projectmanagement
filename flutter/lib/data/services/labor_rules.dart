import '../models/payroll_period.dart';
import 'business_rule_exception.dart';

abstract final class LaborRules {
  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  static String? validateDailyRate(double? rate) =>
      (rate == null || rate <= 0) ? 'Daily rate must be greater than 0.' : null;

  static String? validateOvertime(double? hours) {
    if (hours == null || hours < 0) return 'Overtime cannot be negative.';
    if (hours > 12) return 'Overtime cannot exceed 12 hours a day.';
    return null;
  }

  static String? validateWorkDate(DateTime date, DateTime today) =>
      _day(date).isAfter(_day(today))
      ? 'Attendance cannot be recorded for a future date.'
      : null;

  /// Payroll runs weekly or every 15 days.
  static String? validatePeriod(DateTime? start, DateTime? end) {
    if (start == null || end == null) return 'Choose the period dates.';
    if (_day(end).isBefore(_day(start))) {
      return 'The period must end on or after it starts.';
    }
    if (_day(end).difference(_day(start)).inDays + 1 > 16) {
      return 'A payroll period covers a week or 15 days, not more than 16.';
    }
    return null;
  }

  /// Attendance cannot be edited once its payroll period is Processed.
  static String? canEditAttendance(PayrollPeriod? period) =>
      period?.status == PayrollStatus.processed
      ? 'Attendance in a processed payroll period is locked.'
      : null;

  /// The PM verifies attendance at cut-off.
  static String? canVerify(PayrollPeriod p, DateTime today) {
    if (p.status != PayrollStatus.open) return 'This period is not open.';
    if (_day(today).isBefore(_day(p.periodEnd))) {
      return 'Attendance can be verified once the cut-off date has passed.';
    }
    return null;
  }

  static String? canProcess(PayrollPeriod p) =>
      p.status == PayrollStatus.verified
      ? null
      : 'The PM must verify attendance before payroll is processed.';

  static String? validateCashAdvance(double? amount, double grossPay) {
    if (amount == null || amount < 0) return 'Enter 0 or more.';
    if (amount > grossPay) return 'Cash advance cannot exceed gross pay.';
    return null;
  }

  static void enforce(String? error) {
    if (error != null) throw BusinessRuleException(error);
  }
}

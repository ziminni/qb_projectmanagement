import '../models/attendance.dart';
import '../models/payroll_line.dart';
import '../models/worker.dart';

/// Employee-share contribution rates. These are simplified flat rates, not
/// the SSS, PhilHealth and Pag-IBIG contribution tables; replace them with
/// the official tables (salary brackets, caps and employer shares) before
/// real use.
abstract final class ContributionRates {
  static const sss = 0.05;
  static const philhealth = 0.025;
  static const pagibig = 0.02;

  /// Pag-IBIG employee share is capped at ₱200 a month; ₱100 per
  /// semi-monthly period.
  static const pagibigCapPerPeriod = 100.0;

  /// Regular-day overtime premium under the Labor Code: +25%.
  static const overtimePremium = 1.25;
  static const hoursPerDay = 8;
}

double _round(double v) => (v * 100).roundToDouble() / 100;

/// Pay = daily rate × days, plus overtime, less SSS / PhilHealth / Pag-IBIG
/// and cash advances.
PayrollLine computePayrollLine({
  required int payrollPeriodId,
  required Worker worker,
  required List<Attendance> attendance,
  double cashAdvance = 0,
  int id = 0,
}) {
  final days = attendance.fold(0.0, (s, a) => s + a.status.dayFraction);
  final otHours = attendance.fold(0.0, (s, a) => s + a.overtimeHours);
  final hourly = worker.dailyRate / ContributionRates.hoursPerDay;
  final overtimePay = _round(
    otHours * hourly * ContributionRates.overtimePremium,
  );
  final gross = _round(worker.dailyRate * days + overtimePay);
  final sss = _round(gross * ContributionRates.sss);
  final philhealth = _round(gross * ContributionRates.philhealth);
  final pagibig = _round(
    (gross * ContributionRates.pagibig).clamp(
      0,
      ContributionRates.pagibigCapPerPeriod,
    ),
  );
  return PayrollLine(
    id: id,
    payrollPeriodId: payrollPeriodId,
    workerId: worker.id,
    daysWorked: days,
    overtimePay: overtimePay,
    grossPay: gross,
    sss: sss,
    philhealth: philhealth,
    pagibig: pagibig,
    cashAdvance: cashAdvance,
    netPay: _round(gross - sss - philhealth - pagibig - cashAdvance),
  );
}

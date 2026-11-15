import 'json_utils.dart';

/// A row in `payroll_lines`: one worker's pay for a period.
///
/// The mock computes SSS / PhilHealth / Pag-IBIG from the demo rate table and
/// leaves [statutoryDeductions] at zero. The CPMS server owns the amounts and
/// sends **one** statutory total plus a [deductionsPolicy] flag instead of the
/// three-column split, so in API mode the three columns are zero and the
/// screens say the policy is unconfigured rather than implying no
/// contributions are due.
class PayrollLine {
  const PayrollLine({
    required this.id,
    required this.payrollPeriodId,
    required this.workerId,
    required this.daysWorked,
    required this.overtimePay,
    required this.grossPay,
    required this.sss,
    required this.philhealth,
    required this.pagibig,
    required this.cashAdvance,
    required this.netPay,
    this.statutoryDeductions = 0,
    this.deductionsPolicy = deductionsConfigured,
    this.createdAt,
    this.updatedAt,
  });

  /// The server has no statutory contribution table yet: its lines carry a
  /// zero total and this policy, which the screens must show.
  static const String deductionsUnconfigured = 'unconfigured';

  /// Anything else means the amounts are real for the payer's policy.
  static const String deductionsConfigured = 'configured';

  final int id;
  final int payrollPeriodId;
  final int workerId;
  final double daysWorked;
  final double overtimePay;
  final double grossPay;
  final double sss;
  final double philhealth;
  final double pagibig;
  final double cashAdvance;
  final double netPay;

  /// The server's single statutory total (`statutory_deductions` on the wire).
  final double statutoryDeductions;

  /// `unconfigured` until a statutory policy exists; the screens say so.
  final String deductionsPolicy;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  double get deductions {
    final itemized = sss + philhealth + pagibig;
    final statutory = itemized > 0 ? itemized : statutoryDeductions;
    return statutory + cashAdvance;
  }

  /// A wire line: parses optional `sss`, `philhealth`, `pagibig` breakdown
  /// alongside `statutory_deductions` and `deductions_policy`. A missing money
  /// figure throws rather than reading as zero.
  factory PayrollLine.fromJson(Map<String, dynamic> json) {
    final policy = json['deductions_policy'];
    if (policy is! String) {
      throw FormatException('Expected a deductions policy, got $policy');
    }
    final sss = json.containsKey('sss') ? JsonUtils.toDouble(json['sss']) : 0.0;
    final philhealth = json.containsKey('philhealth')
        ? JsonUtils.toDouble(json['philhealth'])
        : 0.0;
    final pagibig = json.containsKey('pagibig')
        ? JsonUtils.toDouble(json['pagibig'])
        : 0.0;
    return PayrollLine(
      id: json['id'] as int,
      payrollPeriodId: json['payroll_period_id'] as int,
      workerId: json['worker_id'] as int,
      daysWorked: JsonUtils.toDouble(json['days_worked']),
      overtimePay: JsonUtils.toDouble(json['overtime_pay']),
      grossPay: JsonUtils.toDouble(json['gross_pay']),
      sss: sss,
      philhealth: philhealth,
      pagibig: pagibig,
      statutoryDeductions: JsonUtils.toDouble(json['statutory_deductions']),
      deductionsPolicy: policy,
      cashAdvance: JsonUtils.toDouble(json['cash_advance']),
      netPay: JsonUtils.toDouble(json['net_pay']),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'payroll_period_id': payrollPeriodId,
    'worker_id': workerId,
    'days_worked': daysWorked,
    'overtime_pay': overtimePay,
    'gross_pay': grossPay,
    'sss': sss,
    'philhealth': philhealth,
    'pagibig': pagibig,
    'statutory_deductions': statutoryDeductions,
    'deductions_policy': deductionsPolicy,
    'cash_advance': cashAdvance,
    'net_pay': netPay,
    'created_at': JsonUtils.fromDateTimeOrNull(createdAt),
    'updated_at': JsonUtils.fromDateTimeOrNull(updatedAt),
  };
}

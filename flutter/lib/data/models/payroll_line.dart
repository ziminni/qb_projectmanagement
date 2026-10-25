import 'json_utils.dart';

/// A row in `payroll_lines`: one worker's pay for a period.
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
    this.createdAt,
    this.updatedAt,
  });

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
  final DateTime? createdAt;
  final DateTime? updatedAt;

  double get deductions => sss + philhealth + pagibig + cashAdvance;

  factory PayrollLine.fromJson(Map<String, dynamic> json) => PayrollLine(
    id: json['id'] as int,
    payrollPeriodId: json['payroll_period_id'] as int,
    workerId: json['worker_id'] as int,
    daysWorked: JsonUtils.toDouble(json['days_worked']),
    overtimePay: JsonUtils.toDouble(json['overtime_pay']),
    grossPay: JsonUtils.toDouble(json['gross_pay']),
    sss: JsonUtils.toDouble(json['sss']),
    philhealth: JsonUtils.toDouble(json['philhealth']),
    pagibig: JsonUtils.toDouble(json['pagibig']),
    cashAdvance: JsonUtils.toDouble(json['cash_advance']),
    netPay: JsonUtils.toDouble(json['net_pay']),
    createdAt: JsonUtils.toDateOrNull(json['created_at']),
    updatedAt: JsonUtils.toDateOrNull(json['updated_at']),
  );

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
    'cash_advance': cashAdvance,
    'net_pay': netPay,
    'created_at': JsonUtils.fromDateTimeOrNull(createdAt),
    'updated_at': JsonUtils.fromDateTimeOrNull(updatedAt),
  };
}

"""Payroll arithmetic: days, overtime premium, gross, net.

Direction is one way: attendance plus the worker's current daily rate produce a
line. Two things are **not** decided here:

* statutory deductions (SSS / PhilHealth / Pag-IBIG / withholding tax) are
  unresolved owner policy, so every line carries `statutory_deductions = 0.00`
  and `deductions_policy = 'unconfigured'` until a real contribution table
  lands. The demo calculator's flat percentages
  (`flutter/lib/data/services/payroll_calculator.dart`) are never copied;
* negative net pay has no agreed handling either — net is stored as computed,
  `gross - advances - deductions`. With no deduction policy configured the only
  way to go negative is an advance larger than a recomputed gross, and
  `payroll_services.process_period` refuses that case rather than issuing it.

The +25% overtime premium is the Labor Code's regular-day premium and is a
delegated, revisable default, not statutory-deduction policy.
"""

from decimal import ROUND_HALF_UP, Decimal

from ..projects.rules import as_decimal
from .models import PayrollLine

HOURS_PER_DAY = Decimal('8')
OVERTIME_PREMIUM = Decimal('1.25')  # Labor Code regular-day premium.

SSS_RATE = Decimal('0.05')
PHILHEALTH_RATE = Decimal('0.025')
PAGIBIG_RATE = Decimal('0.02')
PAGIBIG_CAP_PER_PERIOD = Decimal('100.00')

# Days of pay each attendance status earns (`attendance.dart` dayFraction).
DAY_FRACTION = {
    'present': Decimal('1.00'),
    'half_day': Decimal('0.50'),
    'absent': Decimal('0.00'),
}


def money(value):
    """Quantize to centavos, half-up (the mock's `_round`)."""
    return Decimal(value).quantize(Decimal('0.01'), rounding=ROUND_HALF_UP)


def compute_line(worker, attendance_rows, cash_advance=Decimal('0.00')):
    """The gross/net figures for one worker's attendance in one period.

    Returns a plain dict shaped like the payroll-line wire row; nothing is
    written. `attendance_rows` must already belong to this worker.
    """
    days = sum(
        (DAY_FRACTION[row.status] for row in attendance_rows), Decimal('0.00'),
    )
    overtime_hours = sum(
        (row.overtime_hours for row in attendance_rows), Decimal('0.00'),
    )
    hourly = Decimal(worker.daily_rate) / HOURS_PER_DAY
    overtime_pay = money(overtime_hours * hourly * OVERTIME_PREMIUM)
    gross_pay = money(Decimal(worker.daily_rate) * days + overtime_pay)
    sss = money(gross_pay * SSS_RATE)
    philhealth = money(gross_pay * PHILHEALTH_RATE)
    pagibig = min(money(gross_pay * PAGIBIG_RATE), PAGIBIG_CAP_PER_PERIOD)
    deductions = money(sss + philhealth + pagibig)
    net_pay = money(gross_pay - cash_advance - deductions)
    return {
        'id': 0,
        'worker_id': worker.pk,
        'days_worked': money(days),
        'overtime_pay': overtime_pay,
        'gross_pay': gross_pay,
        'sss': sss,
        'philhealth': philhealth,
        'pagibig': pagibig,
        'cash_advance': money(cash_advance),
        'statutory_deductions': deductions,
        'deductions_policy': PayrollLine.DEDUCTIONS_CONFIGURED,
        'net_pay': net_pay,
    }


def amount(raw):
    """A finite, non-negative money amount, or None when it is neither."""
    value = as_decimal(raw)
    if value is None or value < 0:
        return None
    return money(value)

"""Payroll writes: periods, verification, cash advances, processing.

Every write is one `transaction.atomic()` with its audit row, so a refused move
leaves no row, no audit and no half-applied money.

Lock order is fixed and shared with the attendance save-day:

1. the **project** row (`select_for_update`) — the payroll/attendance join
   point, so a processing run and an attendance save for the same period can
   never interleave;
2. the **period** row;
3. the rows being written.

`services.save_day` takes the same first lock, which is what makes
"process vs. save attendance" a real serialization instead of a hope: whoever
wins makes the other either refuse (processed period) or see the new attendance
before it snapshots. The database's uniqueness constraints are the backstop.

Statutory deductions stay unconfigured here: a line's `statutory_deductions` is
`0.00` and `net = gross - advances - deductions` (see `payroll_math`). Processing
refuses an advance that a later attendance correction or rate change pushed
above the recomputed gross, so no line is ever issued with a negative net.
"""

# Pyright here runs without django-stubs, so model managers are untyped.
# pyright: reportAttributeAccessIssue=false, reportArgumentType=false

from decimal import Decimal

from django.db import IntegrityError, transaction
from django.db.models import Sum
from django.utils import timezone

from ..projects import scoping
from ..projects.models import Project
from ..projects.rules import RuleRefused
from ..users import services as user_services
from ..users.models import Role, User
from . import payroll_math
from . import payroll_rules as rules
from .models import (
    Attendance,
    PayrollAdvance,
    PayrollLine,
    PayrollPeriod,
    PayrollStatus,
)

MAX_PERIOD_DAYS = 16


def _locked_project(project):
    return Project.objects.select_for_update().get(pk=project.pk)


def _locked_period(period):
    return PayrollPeriod.objects.get(pk=period.pk) if period._state.adding else (
        PayrollPeriod.objects.select_for_update().get(pk=period.pk)
    )


def _details(period, **extra):
    """Audit details: which project and period, **never** a wage or a total."""
    return {
        'project': period.project.code,
        'period_start': period.period_start.isoformat(),
        'period_end': period.period_end.isoformat(),
        **extra,
    }


def _require_period_dates(start, end):
    if end < start:
        raise RuleRefused(rules.PERIOD_REVERSED)
    if (end - start).days + 1 > MAX_PERIOD_DAYS:
        raise RuleRefused(rules.PERIOD_TOO_LONG)


# --- Periods ----------------------------------------------------------------


def create_period(user, project, start, end):
    """A new open cut-off for `project`; overlapping periods are refused."""
    _require_period_dates(start, end)
    with transaction.atomic():
        project = _locked_project(project)
        if PayrollPeriod.objects.filter(
            project=project, period_start__lte=end, period_end__gte=start,
        ).exists():
            raise RuleRefused(rules.PERIOD_OVERLAP)
        try:
            period = PayrollPeriod.objects.create(
                project=project, period_start=start, period_end=end,
            )
        except IntegrityError as error:
            # A second simultaneous create reached the unique backstop.
            raise RuleRefused(rules.PERIOD_OVERLAP) from error
        user_services.record(
            user, 'payroll_period_created', 'payroll_period', period.pk,
            _details(period),
        )
    return period


def verify_period(user, period):
    """Owner verification at cut-off; only an open, already-ended period."""
    with transaction.atomic():
        project = _locked_project(period.project)
        period = _locked_period(period)
        if period.status != PayrollStatus.OPEN:
            raise RuleRefused(rules.PERIOD_NOT_OPEN)
        if timezone.localdate() < period.period_end:
            raise RuleRefused(rules.CUTOFF_NOT_REACHED)
        scoping.require_owner(project, user, rules.OWNER_VERIFIES)
        period.status = PayrollStatus.VERIFIED
        period.save(update_fields=['status', 'updated_at'])
        user_services.record(
            user, 'attendance_verified', 'payroll_period', period.pk,
            _details(period),
        )
        # Accountants are company-wide, not project members, so they are found by
        # role, as the mock did. Same transaction: a refused verify tells no one.
        for accountant in User.objects.filter(
            is_active=True, user_roles__role=Role.ACCOUNTANT,
        ).distinct():
            user_services.notify(
                accountant, 'payroll',
                'Attendance verified; payroll period is ready to process.',
                link=f'/payroll/{period.pk}',
            )
    return period


# --- Advances ---------------------------------------------------------------


def set_cash_advance(user, period, worker_id, amount):
    """Hold `amount` against one worker's pay in this period; return its line."""
    with transaction.atomic():
        _locked_project(period.project)
        period = _locked_period(period)
        if period.status == PayrollStatus.PROCESSED:
            raise RuleRefused(rules.PERIOD_ALREADY_PROCESSED)
        line = _line_for_worker(period, worker_id)
        if amount > line['gross_pay']:
            raise RuleRefused(rules.ADVANCE_OVER_GROSS)
        advance, _ = PayrollAdvance.objects.update_or_create(
            period=period, worker_id=worker_id, defaults={'amount': amount},
        )
        # Details carry no amount: a cash advance is still a wage figure.
        user_services.record(
            user, 'payroll_advance_set', 'payroll_advance', advance.pk,
            _details(period, worker_id=worker_id),
        )
        line['cash_advance'] = amount
        line['net_pay'] = payroll_math.money(
            line['gross_pay'] - amount - line['statutory_deductions'],
        )
    return line


# --- Processing -------------------------------------------------------------


def process_period(user, period):
    """Snapshot the verified period's pay into `PayrollLine` rows and lock it."""
    with transaction.atomic():
        _locked_project(period.project)
        period = _locked_period(period)
        if period.status == PayrollStatus.PROCESSED:
            raise RuleRefused(rules.PERIOD_ALREADY_PROCESSED)
        if period.status != PayrollStatus.VERIFIED:
            raise RuleRefused(rules.NOT_VERIFIED)

        lines = _computed_lines(period)
        # An advance was checked against the gross when it was set; correcting a
        # verified day or raising the daily rate can shrink that gross under it.
        # Refuse the process, never issue a negative net: the accountant lowers
        # the advance (the period is open again after any such correction).
        if any(line['cash_advance'] > line['gross_pay'] for line in lines):
            raise RuleRefused(rules.ADVANCE_OVER_GROSS)
        stored = [_stored(period, line) for line in lines]
        try:
            with transaction.atomic():
                PayrollLine.objects.bulk_create(stored)
        except IntegrityError as error:
            # A second simultaneous process slipped past the period lock.
            raise RuleRefused(rules.PERIOD_ALREADY_PROCESSED) from error

        period.status = PayrollStatus.PROCESSED
        period.save(update_fields=['status', 'updated_at'])
        user_services.record(
            user, 'payroll_processed', 'payroll_period', period.pk,
            _details(period, lines=len(stored)),
        )
    return period


def _stored(period, line):
    return PayrollLine(
        period=period,
        worker_id=line['worker_id'],
        days_worked=line['days_worked'],
        overtime_pay=line['overtime_pay'],
        gross_pay=line['gross_pay'],
        cash_advance=line['cash_advance'],
        statutory_deductions=line['statutory_deductions'],
        deductions_policy=line['deductions_policy'],
        net_pay=line['net_pay'],
    )


# --- Reads ------------------------------------------------------------------


def lines_for(period):
    """Stored lines once processed; otherwise computed from live attendance."""
    if period.status == PayrollStatus.PROCESSED:
        return [_wire(row) for row in period.lines.order_by('worker_id', 'id')]
    return _computed_lines(period)


def labor_cost(project):
    """Gross pay of the project's **processed** periods.

    Computed or verified-but-unprocessed pay is not a cost yet, and this is not
    posted to the expense log (payroll accounting policy is still open).
    """
    total = PayrollLine.objects.filter(
        period__project=project, period__status=PayrollStatus.PROCESSED,
    ).aggregate(total=Sum('gross_pay'))['total']
    return payroll_math.money(total or 0)


def _wire(row):
    return {
        'id': row.pk,
        'payroll_period_id': row.period_id,
        'worker_id': row.worker_id,
        'days_worked': row.days_worked,
        'overtime_pay': row.overtime_pay,
        'gross_pay': row.gross_pay,
        'cash_advance': row.cash_advance,
        'statutory_deductions': row.statutory_deductions,
        'deductions_policy': row.deductions_policy,
        'net_pay': row.net_pay,
    }


def _attendance_by_worker(period):
    rows = Attendance.objects.filter(
        project_id=period.project_id,
        work_date__gte=period.period_start,
        work_date__lte=period.period_end,
    ).select_related('worker').order_by('worker_id', 'work_date', 'id')
    grouped = {}
    for row in rows:
        grouped.setdefault(row.worker_id, []).append(row)
    return grouped


def _computed_lines(period):
    advances = dict(
        PayrollAdvance.objects.filter(period=period)
        .values_list('worker_id', 'amount')
    )
    lines = []
    for worker_id, rows in _attendance_by_worker(period).items():
        line = payroll_math.compute_line(
            rows[0].worker, rows, advances.get(worker_id, Decimal('0.00')),
        )
        line['payroll_period_id'] = period.pk
        lines.append(line)
    lines.sort(key=lambda line: line['worker_id'])
    return lines


def _line_for_worker(period, worker_id):
    rows = _attendance_by_worker(period).get(worker_id)
    if not rows:
        raise RuleRefused(rules.ADVANCE_NO_ATTENDANCE)
    advances = PayrollAdvance.objects.filter(
        period=period, worker_id=worker_id,
    ).values_list('amount', flat=True).first()
    line = payroll_math.compute_line(
        rows[0].worker, rows, advances or Decimal('0.00'),
    )
    line['payroll_period_id'] = period.pk
    return line


# --- The attendance save-day hooks ------------------------------------------


def locked_period(project, work_date):
    """The row-locked period covering `work_date`; a processed one refuses.

    Called by `services.save_day` **after** it locked the project row, so the
    status read here cannot change under it.
    """
    period = PayrollPeriod.objects.select_for_update().filter(
        project=project, period_start__lte=work_date, period_end__gte=work_date,
    ).first()
    if period is not None and period.status == PayrollStatus.PROCESSED:
        raise RuleRefused(rules.PERIOD_LOCKED)
    return period


def reopen_verified_period(user, period, work_date):
    """Owner-verified attendance changed: the owner must verify again."""
    period.status = PayrollStatus.OPEN
    period.save(update_fields=['status', 'updated_at'])
    user_services.record(
        user, 'payroll_reopened', 'payroll_period', period.pk,
        _details(
            period, reason='attendance_changed',
            work_date=work_date.isoformat(),
        ),
    )

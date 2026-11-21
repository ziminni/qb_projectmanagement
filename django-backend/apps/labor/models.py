"""Workers and project attendance (Phase 4 labor slice A) plus payroll
periods, lines and cash advances (slice C).

Shapes mirror `flutter/lib/data/models/{worker,attendance,payroll_period,
payroll_line}.dart` and the wire contracts
`planning/backend-integration/contracts/phase-4-labor.md` (slice A) and
`.../phase-4-payroll.md` (slice C):

    WORKERS    → apps_labor.Worker
    ATTENDANCE → apps_labor.Attendance
    PERIOD     → apps_labor.PayrollPeriod
    LINE       → apps_labor.PayrollLine      (snapshot, written at processing)
    ADVANCE    → apps_labor.PayrollAdvance   (pre-processing cash advance)

Two uniqueness rules live in the database, not only in the view:

1. one row per (project, worker, work_date);
2. one **non-absent** row per (worker, work_date) across all projects, so a
   worker cannot be marked present at two sites the same day (two half-days
   included). An absence at another project is allowed, hence the partial
   index condition.

Statutory deductions are **unresolved owner policy**. A line therefore stores
one `statutory_deductions` amount (default `0.00`) with an explicit
`deductions_policy` flag; nothing here computes SSS, PhilHealth, Pag-IBIG or
withholding tax.
"""

# Pyright here runs without django-stubs, so model fields are inferred as their
# `Field` class.
# pyright: reportAttributeAccessIssue=false

from decimal import Decimal

from django.conf import settings
from django.core.validators import MaxValueValidator, MinValueValidator
from django.db import models

from ..master_data.models import Trade


class AttendanceStatus(models.TextChoices):
    """Mirror of Flutter `AttendanceStatus` (`attendance.dart:3-7`)."""

    PRESENT = 'present', 'Present'
    HALF_DAY = 'half_day', 'Half day'
    ABSENT = 'absent', 'Absent'


# Values that count as "on site that day" for the cross-project rule.
PRESENT_STATUSES = (AttendanceStatus.PRESENT, AttendanceStatus.HALF_DAY)


class Worker(models.Model):
    """A daily-paid worker (`models/worker.dart`).

    `trade` is a protected FK: a trade still referenced by a worker cannot be
    deleted (the master-data view answers `400`, not a 500). Workers are never
    hard-deleted; deactivating keeps their attendance history readable.
    """

    full_name = models.CharField(max_length=200)
    address = models.CharField(max_length=255, null=True, blank=True)
    phone = models.CharField(max_length=32, null=True, blank=True)
    trade = models.ForeignKey(Trade, on_delete=models.PROTECT, related_name='workers')
    daily_rate = models.DecimalField(
        max_digits=12, decimal_places=2,
        validators=[MinValueValidator(Decimal('0.01'))],
    )
    cash_advance_balance = models.DecimalField(
        max_digits=12, decimal_places=2, default=Decimal('0.00'),
        validators=[MinValueValidator(Decimal('0.00'))],
    )
    sss_no = models.CharField(max_length=32, null=True, blank=True)
    philhealth_no = models.CharField(max_length=32, null=True, blank=True)
    pagibig_no = models.CharField(max_length=32, null=True, blank=True)
    is_active = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        verbose_name = 'Worker'
        verbose_name_plural = 'Workers'
        ordering = ('full_name', 'id')

    def __str__(self):
        return str(self.full_name)

    def save(self, *args, **kwargs):
        self.full_name = str(self.full_name).strip()
        super().save(*args, **kwargs)


class WorkerRequestStatus(models.TextChoices):
    PENDING = 'pending', 'Pending'
    APPROVED = 'approved', 'Approved'
    REJECTED = 'rejected', 'Rejected'


class ProjectWorkerRequest(models.Model):
    """A foreman's request to add a laborer to a project, approved by the PM."""

    project = models.ForeignKey(
        'apps_projects.Project',
        on_delete=models.PROTECT,
        related_name='worker_requests',
    )
    full_name = models.CharField(max_length=200)
    address = models.CharField(max_length=255)
    phone = models.CharField(max_length=32)
    status = models.CharField(
        max_length=16,
        choices=WorkerRequestStatus.choices,
        default=WorkerRequestStatus.PENDING,
        db_index=True,
    )
    requested_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.PROTECT,
        related_name='+',
    )
    reviewed_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.PROTECT,
        null=True,
        blank=True,
        related_name='+',
    )
    rejection_reason = models.CharField(max_length=255, null=True, blank=True)
    worker = models.ForeignKey(
        Worker,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='project_requests',
    )
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        verbose_name = 'Project Worker Request'
        verbose_name_plural = 'Project Worker Requests'
        ordering = ('-created_at', '-id')
        indexes = [models.Index(fields=['project', 'status'])]

    def __str__(self):
        return f'{self.full_name} ({self.project_id}) [{self.status}]'


class Attendance(models.Model):
    """One worker's attendance on one project on one day.

    `recorded_by` is server-owned: the view always writes the authenticated
    actor, never a value from the request body.
    """

    project = models.ForeignKey(
        'apps_projects.Project', on_delete=models.PROTECT, related_name='attendance',
    )
    worker = models.ForeignKey(Worker, on_delete=models.PROTECT, related_name='attendance')
    work_date = models.DateField()
    status = models.CharField(max_length=16, choices=AttendanceStatus.choices)
    overtime_hours = models.DecimalField(
        max_digits=4, decimal_places=2, default=Decimal('0.00'),
        validators=[MinValueValidator(0), MaxValueValidator(12)],
    )
    recorded_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.PROTECT, related_name='+',
    )
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        verbose_name = 'Attendance'
        verbose_name_plural = 'Attendance'
        ordering = ('work_date', 'id')
        constraints = [
            models.UniqueConstraint(
                fields=('project', 'worker', 'work_date'),
                name='apps_labor_attendance_unique_project_worker_day',
            ),
            # One presence per worker per day across projects; absences are
            # excluded so a second project may still record "absent".
            models.UniqueConstraint(
                fields=('worker', 'work_date'),
                condition=~models.Q(status=AttendanceStatus.ABSENT),
                name='apps_labor_attendance_unique_presence_per_worker_day',
            ),
        ]

    def __str__(self):
        return f'{self.worker} {self.work_date} {self.status}'


# ---------------------------------------------------------------------------
# Phase 4 slice C — payroll periods, lines and cash advances
# ---------------------------------------------------------------------------

class PayrollStatus(models.TextChoices):
    """Mirror of Flutter `PayrollStatus` (`payroll_period.dart:3-7`)."""

    OPEN = 'open', 'Open'
    VERIFIED = 'verified', 'Verified by owner'
    PROCESSED = 'processed', 'Processed'


class PayrollPeriod(models.Model):
    """One weekly/15-day cut-off of one project (`payroll_period.dart`).

    The status only moves open → verified → processed, plus one step back
    (verified → open) when verified attendance is corrected before processing.
    A processed period is final: its lines are the pay that was issued.
    """

    project = models.ForeignKey(
        'apps_projects.Project', on_delete=models.PROTECT,
        related_name='payroll_periods',
    )
    period_start = models.DateField()
    period_end = models.DateField()
    status = models.CharField(
        max_length=16, choices=PayrollStatus.choices,
        default=PayrollStatus.OPEN, db_index=True,
    )
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        verbose_name = 'Payroll Period'
        verbose_name_plural = 'Payroll Periods'
        ordering = ('-period_start', '-id')
        indexes = [models.Index(fields=['project', 'status'])]
        constraints = [
            # Overlaps are refused by the service under the project row lock;
            # this is the backstop for two simultaneous creates.
            models.UniqueConstraint(
                fields=('project', 'period_start'),
                name='apps_labor_payroll_period_unique_project_start',
            ),
            models.CheckConstraint(
                condition=models.Q(period_end__gte=models.F('period_start')),
                name='apps_labor_payroll_period_end_after_start',
            ),
        ]

    def __str__(self):
        return f'{self.project.code} {self.period_start}–{self.period_end}'


class PayrollLine(models.Model):
    """One worker's pay for one period (`payroll_line.dart`).

    Written once, at processing: a later wage change never rewrites issued pay.
    The wire shape extends the demo model with one `statutory_deductions`
    amount and a `deductions_policy` flag, because the SSS/PhilHealth/Pag-IBIG/
    withholding-tax policy is an open owner decision.
    """

    DEDUCTIONS_UNCONFIGURED = 'unconfigured'
    DEDUCTIONS_CONFIGURED = 'configured'
    DEDUCTIONS_POLICY_CHOICES = (
        (DEDUCTIONS_UNCONFIGURED, 'Not configured'),
        (DEDUCTIONS_CONFIGURED, 'Configured'),
    )

    period = models.ForeignKey(
        PayrollPeriod, on_delete=models.PROTECT, related_name='lines',
    )
    worker = models.ForeignKey(Worker, on_delete=models.PROTECT,
                               related_name='payroll_lines')
    days_worked = models.DecimalField(
        max_digits=5, decimal_places=2,
        validators=[MinValueValidator(0), MaxValueValidator(16)],
    )
    overtime_pay = models.DecimalField(
        max_digits=12, decimal_places=2,
        validators=[MinValueValidator(0)],
    )
    gross_pay = models.DecimalField(
        max_digits=12, decimal_places=2,
        validators=[MinValueValidator(0)],
    )
    sss = models.DecimalField(
        max_digits=12, decimal_places=2, default=Decimal('0.00'),
        validators=[MinValueValidator(0)],
    )
    philhealth = models.DecimalField(
        max_digits=12, decimal_places=2, default=Decimal('0.00'),
        validators=[MinValueValidator(0)],
    )
    pagibig = models.DecimalField(
        max_digits=12, decimal_places=2, default=Decimal('0.00'),
        validators=[MinValueValidator(0)],
    )
    cash_advance = models.DecimalField(
        max_digits=12, decimal_places=2, default=Decimal('0.00'),
        validators=[MinValueValidator(0)],
    )
    statutory_deductions = models.DecimalField(
        max_digits=12, decimal_places=2, default=Decimal('0.00'),
        validators=[MinValueValidator(0)],
    )
    deductions_policy = models.CharField(
        max_length=16, choices=DEDUCTIONS_POLICY_CHOICES,
        default=DEDUCTIONS_CONFIGURED,
    )
    net_pay = models.DecimalField(max_digits=12, decimal_places=2)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        verbose_name = 'Payroll Line'
        verbose_name_plural = 'Payroll Lines'
        ordering = ('worker_id', 'id')
        constraints = [
            models.UniqueConstraint(
                fields=('period', 'worker'),
                name='apps_labor_payroll_line_unique_period_worker',
            ),
            models.CheckConstraint(
                condition=models.Q(cash_advance__gte=0)
                & models.Q(statutory_deductions__gte=0)
                & models.Q(gross_pay__gte=0),
                name='apps_labor_payroll_line_amounts_not_negative',
            ),
        ]

    def __str__(self):
        return f'{self.period_id}/{self.worker_id} {self.net_pay}'


class PayrollAdvance(models.Model):
    """A worker's cash advance held against one period, before processing.

    Keyed by (period, worker) — "per line" once the period is processed. An
    advance is set back to `0.00`, never deleted, so its history is kept.
    """

    period = models.ForeignKey(
        PayrollPeriod, on_delete=models.PROTECT, related_name='advances',
    )
    worker = models.ForeignKey(Worker, on_delete=models.PROTECT,
                               related_name='payroll_advances')
    amount = models.DecimalField(
        max_digits=12, decimal_places=2,
        validators=[MinValueValidator(0)],
    )
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        verbose_name = 'Payroll Advance'
        verbose_name_plural = 'Payroll Advances'
        ordering = ('worker_id', 'id')
        constraints = [
            models.UniqueConstraint(
                fields=('period', 'worker'),
                name='apps_labor_payroll_advance_unique_period_worker',
            ),
            models.CheckConstraint(
                condition=models.Q(amount__gte=0),
                name='apps_labor_payroll_advance_amount_not_negative',
            ),
        ]

    def __str__(self):
        return f'{self.period_id}/{self.worker_id} {self.amount}'

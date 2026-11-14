"""Workers and project attendance (Phase 4 labor slice A).

Shapes mirror `flutter/lib/data/models/{worker,attendance}.dart` and the wire
contract `planning/backend-integration/contracts/phase-4-labor.md`:

    WORKERS    → apps_labor.Worker
    ATTENDANCE → apps_labor.Attendance

No payroll table exists in this slice on purpose: periods, processing and
labor cost posting are a later slice and must add processed-period attendance
locks in the same rollout.

Two uniqueness rules live in the database, not only in the view:

1. one row per (project, worker, work_date);
2. one **non-absent** row per (worker, work_date) across all projects, so a
   worker cannot be marked present at two sites the same day (two half-days
   included). An absence at another project is allowed, hence the partial
   index condition.
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
    trade = models.ForeignKey(Trade, on_delete=models.PROTECT, related_name='workers')
    daily_rate = models.DecimalField(
        max_digits=12, decimal_places=2,
        validators=[MinValueValidator(Decimal('0.01'))],
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

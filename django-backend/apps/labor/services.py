"""Labor writes: worker maintenance and the atomic attendance save-day.

Every write lives in one `transaction.atomic()` with its audit row, so an
invalid entry leaves no row, no audit and no half-saved sheet behind.

The save-day lock order is fixed to avoid deadlocks, and shared with payroll:

1. the **project** row (`select_for_update`) — the same first lock a payroll
   processing run takes, so "process vs. save attendance" cannot interleave;
2. the payroll period covering the day (a processed one refuses the save);
3. worker rows, `select_for_update()` ordered by id (this also serialises two
   competing cross-project saves for the same worker);
4. the existing attendance rows of the project/day;
5. then the cross-project presence check, the upsert, the audits and — when a
   verified period's attendance actually changed — the reopen to `open`.

The database's partial unique index (one non-absent row per worker per day) is
the backstop; a race that still reaches it is mapped to a clean `400`, never a
`500`.
"""

# Pyright here runs without django-stubs, so model managers are untyped.
# pyright: reportAttributeAccessIssue=false, reportArgumentType=false

from decimal import Decimal

from django.db import IntegrityError, transaction
from django.utils import timezone

from ..projects.models import Project
from ..projects.rules import RuleRefused
from ..users import services as user_services
from . import payroll_services, rules
from .models import (
    PRESENT_STATUSES,
    Attendance,
    AttendanceStatus,
    PayrollStatus,
    Worker,
)


def create_worker(user, serializer):
    with transaction.atomic():
        worker = serializer.save()
        user_services.record(user, 'worker_created', 'worker', worker.pk,
                             {'name': worker.full_name})
    return worker


def update_worker(user, serializer):
    with transaction.atomic():
        worker = serializer.save()
        user_services.record(user, 'worker_updated', 'worker', worker.pk,
                             {'name': worker.full_name})
    return worker


def save_day(user, project, work_date, entries):
    """Replace the listed workers' rows for one project/day; return them.

    `entries` are already validated (status, finite overtime in 0–12, unique
    worker ids). Omitted workers are untouched and an empty sheet is a no-op.
    """
    if work_date > timezone.localdate():
        raise RuleRefused(rules.FUTURE_DATE)
    if not entries:
        return []

    worker_ids = [entry['worker_id'] for entry in entries]
    try:
        saved = _write_sheet(user, project, work_date, entries, worker_ids)
    except IntegrityError as error:
        # The partial unique index refused a presence that slipped past the
        # lock (a different code path inserting directly). Never a 500.
        raise RuleRefused(rules.PRESENCE_CONFLICT_GENERIC) from error
    return sorted(saved, key=lambda row: row.worker_id)


def _write_sheet(user, project, work_date, entries, worker_ids):
    saved = []
    with transaction.atomic():
        # The project lock is shared with payroll processing: it decides whether
        # this save sees the period's status or the process run sees the save.
        project = Project.objects.select_for_update().get(pk=project.pk)
        period = payroll_services.locked_period(project, work_date)
        # Stable worker lock order serialises competing saves for this worker.
        workers = {
            worker.pk: worker
            for worker in _locked_workers(worker_ids)
        }
        rows = {
            row.worker_id: row
            for row in Attendance.objects.select_for_update().filter(
                project=project, work_date=work_date, worker_id__in=worker_ids,
            )
        }
        conflicts = {
            row.worker_id
            for row in Attendance.objects.filter(
                worker_id__in=worker_ids,
                work_date=work_date,
                status__in=PRESENT_STATUSES,
            ).exclude(project=project)
        }

        for entry in entries:
            worker = workers.get(entry['worker_id'])
            if worker is None:
                raise RuleRefused(rules.UNKNOWN_WORKER)
            # A correction of an existing row is allowed even when the worker
            # has since been deactivated; a brand-new row is not.
            if not worker.is_active and worker.pk not in rows:
                raise RuleRefused(rules.INACTIVE_WORKER)
            # Only a new presence conflicts; "absent" at another project is
            # allowed even when this worker is present here.
            if (entry['status'] in PRESENT_STATUSES
                    and worker.pk in conflicts):
                raise RuleRefused(
                    rules.PRESENCE_CONFLICT.format(name=worker.full_name)
                )

        changed = False
        for entry in entries:
            worker = workers[entry['worker_id']]
            status = entry['status']
            row = rows.get(worker.pk)
            if row is None:
                row = Attendance(project=project, worker=worker,
                                 work_date=work_date)
            overtime_hours = (
                Decimal(0) if status == AttendanceStatus.ABSENT
                else entry['overtime_hours']
            )
            if (row.pk is None or row.status != status
                    or row.overtime_hours != overtime_hours):
                changed = True
            row.status = status
            row.overtime_hours = overtime_hours
            row.recorded_by = user
            row.save()
            # No wage, government id or raw request body reaches the audit row.
            user_services.record(user, 'attendance_saved', 'attendance', row.pk, {
                'project': project.code,
                'work_date': work_date.isoformat(),
                'worker_id': worker.pk,
                'status': status,
            })
            saved.append(row)
        # The owner verified this attendance; a real correction needs a new
        # verification before the accountant may process the period.
        if (changed and period is not None
                and period.status == PayrollStatus.VERIFIED):
            payroll_services.reopen_verified_period(user, period, work_date)
    return saved


def _locked_workers(worker_ids):
    return (
        Worker.objects.select_for_update()
        .filter(pk__in=worker_ids)
        .order_by('pk')
    )

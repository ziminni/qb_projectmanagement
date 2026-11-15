"""Phase 4 slice C wire-contract tests: payroll periods, advances, processing.

Every rule in `planning/backend-integration/contracts/phase-4-payroll.md` has a
test here: the finance/owner fences (active role only, never a union), project
scoping / IDOR, period validation, verification at cut-off, cash advances per
line, the gross-pay computation, processed-period attendance locking, owner
verification invalidation when verified attendance changes, the labor-cost
rollup, audit rows without wages, and one real process-vs-save race.

Statutory deductions stay **unconfigured**: every line reports
`statutory_deductions = 0.00` and `deductions_policy = 'unconfigured'`, and
`net = gross - advances - deductions`. Nothing here asserts demo SSS/PhilHealth/
Pag-IBIG percentages as payroll policy.
"""

# Pyright here runs without django-stubs, so model managers are untyped.
# pyright: reportAttributeAccessIssue=false, reportArgumentType=false

import json
import threading
from datetime import date, timedelta
from decimal import Decimal

from django.db import connections
from django.test import TransactionTestCase
from django.utils import timezone
from rest_framework.test import APIClient

from ..users.models import AuditLog, Role
from ..users.tests import make_user
from .models import (
    Attendance,
    AttendanceStatus,
    PayrollLine,
    PayrollPeriod,
    PayrollStatus,
)
from .tests_api import SAVE_DAY_URL, LaborCase, LaborFixtures

PERIODS_URL = '/api/v1/payroll-periods/'
LABOR_COST_URL = '/api/v1/labor-cost/'

# `self.worker`: 750/day, 1 day present + 1 half day, 2 overtime hours.
GROSS = '1359.38'
OVERTIME_PAY = '234.38'


class PayrollFixtures(LaborFixtures):
    """Slice-A fixtures plus one open period with attendance inside it."""

    def setUp(self):
        super().setUp()
        # A project nobody is assigned to: the IDOR/404 pin.
        self.blank_project = self.make_project('PRJ-D', 'Tower D')
        self.period = self.make_period(date(2026, 11, 1), date(2026, 11, 15))
        self.day = date(2026, 11, 3)
        self.other_day = date(2026, 11, 4)
        self.mark(self.project, self.worker, self.day, user=self.engineer)
        self.mark(self.project, self.worker, self.other_day,
                  AttendanceStatus.HALF_DAY, '2.00', user=self.engineer)
        self.mark(self.project, self.second, self.day, user=self.engineer)

    def make_period(self, start, end, status=PayrollStatus.OPEN,
                    project=None):
        return PayrollPeriod.objects.create(
            project=project or self.project,
            period_start=start, period_end=end, status=status,
        )

    def period_url(self, period, action=''):
        return f'{PERIODS_URL}{period.pk}/{action}'

    def get_lines(self, period=None, user=None, role=Role.ACCOUNTANT):
        self.act_as(user or self.accountant, role)
        return self.client.get(self.period_url(period or self.period, 'lines/'))

    def post_advance(self, worker_id, amount, period=None, user=None,
                     role=Role.ACCOUNTANT):
        self.act_as(user or self.accountant, role)
        return self.client.post(self.period_url(period or self.period,
                                                'cash-advance/'), {
            'worker_id': worker_id, 'amount': amount,
        }, format='json')


class PayrollWriteCase(PayrollFixtures, LaborCase):
    """Fixtures plus an API client (one rolled-back test)."""


# --------------------------------------------------------------------------
# Periods: create, read, scope
# --------------------------------------------------------------------------

class PayrollPeriodCreateTests(PayrollWriteCase):
    def test_accountant_creates_an_open_period(self):
        self.act_as(self.accountant, Role.ACCOUNTANT)
        response = self.client.post(PERIODS_URL, {
            'project_id': self.project.pk,
            'period_start': '2026-12-01',
            'period_end': '2026-12-15',
        }, format='json')

        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(response.data['status'], 'open')
        self.assertEqual(response.data['period_start'], '2026-12-01')
        self.assertEqual(response.data['period_end'], '2026-12-15')
        self.assertEqual(response.data['project_id'], self.project.pk)
        for key in ('id', 'created_at', 'updated_at'):
            self.assertIn(key, response.data)
        self.assertTrue(AuditLog.objects.filter(
            action='payroll_period_created', entity='payroll_period',
            entity_id=response.data['id'],
        ).exists())

    def test_only_the_accountant_role_creates_periods(self):
        body = {
            'project_id': self.project.pk,
            'period_start': '2026-12-01',
            'period_end': '2026-12-15',
        }
        for user, role in (
            (self.owner, Role.OWNER),
            (self.engineer, Role.SITE_ENGINEER),
            (self.admin, Role.ADMIN),
            (self.client_user, Role.CLIENT),
        ):
            with self.subTest(role=role):
                self.act_as(user, role)
                response = self.client.post(PERIODS_URL, body, format='json')
                self.assertEqual(response.status_code, 403, response.data)
        self.assertFalse(PayrollPeriod.objects.filter(
            period_start=date(2026, 12, 1),
        ).exists())

    def test_period_dates_are_validated(self):
        self.act_as(self.accountant, Role.ACCOUNTANT)
        cases = (
            ({'period_start': '2026-12-15', 'period_end': '2026-12-01'},
             'The period must end on or after it starts.'),
            ({'period_start': '2026-12-01', 'period_end': '2026-12-17'},
             'A payroll period covers a week or 15 days, not more than 16.'),
            ({'period_start': '2026-12-01', 'period_end': ''},
             'Choose the period dates.'),
            ({'period_start': '12/01/2026', 'period_end': '2026-12-15'},
             'Choose the period dates.'),
        )
        for body, text in cases:
            with self.subTest(body=body):
                response = self.client.post(
                    PERIODS_URL,
                    dict(body, project_id=self.project.pk), format='json',
                )
                self.assertEqual(response.status_code, 400, response.data)
                self.assertEqual(response.data['detail'], text)

    def test_overlapping_period_is_refused_and_a_free_one_is_allowed(self):
        self.act_as(self.accountant, Role.ACCOUNTANT)
        overlap = self.client.post(PERIODS_URL, {
            'project_id': self.project.pk,
            'period_start': '2026-11-10',
            'period_end': '2026-11-20',
        }, format='json')
        self.assertEqual(overlap.status_code, 400, overlap.data)
        self.assertEqual(
            overlap.data['detail'],
            'This overlaps an existing payroll period for the project.',
        )

        free = self.client.post(PERIODS_URL, {
            'project_id': self.project.pk,
            'period_start': '2026-11-16',
            'period_end': '2026-11-22',
        }, format='json')
        self.assertEqual(free.status_code, 201, free.data)

        # Another project's overlapping period is not a conflict.
        other = self.client.post(PERIODS_URL, {
            'project_id': self.other_project.pk,
            'period_start': '2026-11-10',
            'period_end': '2026-11-20',
        }, format='json')
        self.assertEqual(other.status_code, 201, other.data)

    def test_unknown_project_is_404(self):
        self.act_as(self.accountant, Role.ACCOUNTANT)
        response = self.client.post(PERIODS_URL, {
            'project_id': 999999,
            'period_start': '2026-12-01',
            'period_end': '2026-12-15',
        }, format='json')
        self.assertEqual(response.status_code, 404, response.data)


class PayrollPeriodReadTests(PayrollWriteCase):
    def test_list_is_scoped_newest_first_and_filterable(self):
        self.make_period(date(2026, 10, 1), date(2026, 10, 15))
        self.make_period(date(2026, 11, 1), date(2026, 11, 15),
                         project=self.other_project)

        self.act_as(self.engineer, Role.SITE_ENGINEER)
        listed = self.client.get(PERIODS_URL)
        self.assertEqual(listed.status_code, 200, listed.data)
        self.assertEqual(listed.data['count'], 3)
        starts = [row['period_start'] for row in listed.data['results']]
        self.assertEqual(starts, sorted(starts, reverse=True))

        one = self.client.get(f'{PERIODS_URL}?project={self.project.pk}')
        self.assertEqual(one.status_code, 200, one.data)
        self.assertEqual(one.data['count'], 2)
        self.assertEqual(
            {row['project_id'] for row in one.data['results']}, {self.project.pk},
        )

        junk = self.client.get(f'{PERIODS_URL}?project=abc')
        self.assertEqual(junk.status_code, 400, junk.data)

    def test_client_and_out_of_scope_reads_are_refused(self):
        self.make_period(date(2026, 11, 1), date(2026, 11, 15),
                         project=self.blank_project)

        self.act_as(self.engineer, Role.SITE_ENGINEER)
        self.assertEqual(self.client.get(PERIODS_URL).data['count'], 1)
        hidden = self.client.get(self.period_url(
            PayrollPeriod.objects.get(project=self.blank_project),
        ))
        self.assertEqual(hidden.status_code, 404, hidden.data)

        self.act_as(self.client_user, Role.CLIENT)
        self.assertEqual(self.client.get(PERIODS_URL).status_code, 403)
        self.assertEqual(
            self.client.get(self.period_url(self.period)).status_code, 403,
        )

    def test_detail_returns_the_house_period_row(self):
        self.act_as(self.engineer, Role.SITE_ENGINEER)
        response = self.client.get(self.period_url(self.period))
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(set(response.data), {
            'id', 'project_id', 'period_start', 'period_end', 'status',
            'created_at', 'updated_at',
        })


# --------------------------------------------------------------------------
# Verification
# --------------------------------------------------------------------------

class PayrollVerificationTests(PayrollWriteCase):
    def test_only_the_assigned_owner_verifies(self):
        # A different owner who is not on this project cannot even see it
        # (scope is checked before the active role, so that is a 404).
        other_owner = make_user('other-owner@example.com', [Role.OWNER])

        for user, role, expected in (
            (self.accountant, Role.ACCOUNTANT, 403),
            (self.engineer, Role.SITE_ENGINEER, 403),
            (other_owner, Role.OWNER, 404),
        ):
            with self.subTest(role=role, expected=expected):
                self.act_as(user, role)
                response = self.client.post(
                    self.period_url(self.period, 'verify/'),
                )
                self.assertEqual(response.status_code, expected, response.data)

        self.act_as(self.owner, Role.OWNER)
        accepted = self.client.post(self.period_url(self.period, 'verify/'))
        self.assertEqual(accepted.status_code, 200, accepted.data)
        self.assertEqual(accepted.data['status'], 'verified')
        self.assertTrue(AuditLog.objects.filter(
            action='attendance_verified', entity='payroll_period',
            entity_id=self.period.pk,
        ).exists())

    def test_verify_waits_for_the_cut_off(self):
        future = self.make_period(
            timezone.localdate(), timezone.localdate() + timedelta(days=3),
        )
        self.act_as(self.owner, Role.OWNER)
        response = self.client.post(self.period_url(future, 'verify/'))
        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(
            response.data['detail'],
            'Attendance can be verified once the cut-off date has passed.',
        )

    def test_a_period_that_is_not_open_cannot_be_verified(self):
        self.period.status = PayrollStatus.VERIFIED
        self.period.save(update_fields=['status'])
        self.act_as(self.owner, Role.OWNER)
        response = self.client.post(self.period_url(self.period, 'verify/'))
        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(response.data['detail'], 'This period is not open.')


# --------------------------------------------------------------------------
# Processed-period locking and verification invalidation
# --------------------------------------------------------------------------

class AttendanceLockTests(PayrollWriteCase):
    def verified(self, period=None):
        period = period or self.period
        period.status = PayrollStatus.VERIFIED
        period.save(update_fields=['status'])
        return period

    def test_changed_verified_attendance_reopens_the_period(self):
        self.verified()
        response = self.save_day([{
            'worker_id': self.worker.pk, 'status': 'present',
            'overtime_hours': '4',
        }], work_date=self.day)

        self.assertEqual(response.status_code, 200, response.data)
        self.period.refresh_from_db()
        self.assertEqual(self.period.status, PayrollStatus.OPEN)
        self.assertTrue(AuditLog.objects.filter(
            action='payroll_reopened', entity='payroll_period',
            entity_id=self.period.pk,
        ).exists())

    def test_unchanged_verified_attendance_keeps_the_period_verified(self):
        self.verified()
        response = self.save_day([{
            'worker_id': self.worker.pk, 'status': 'present',
            'overtime_hours': '0',
        }], work_date=self.day)

        self.assertEqual(response.status_code, 200, response.data)
        self.period.refresh_from_db()
        self.assertEqual(self.period.status, PayrollStatus.VERIFIED)

    def test_processed_period_locks_its_attendance(self):
        self.verified()
        self.act_as(self.accountant, Role.ACCOUNTANT)
        processed = self.client.post(self.period_url(self.period, 'process/'))
        self.assertEqual(processed.status_code, 200, processed.data)

        refused = self.save_day([{
            'worker_id': self.worker.pk, 'status': 'half_day',
            'overtime_hours': '0',
        }], work_date=self.day)
        self.assertEqual(refused.status_code, 400, refused.data)
        self.assertEqual(
            refused.data['detail'],
            'Attendance in a processed payroll period is locked.',
        )
        row = Attendance.objects.get(
            project=self.project, worker=self.worker, work_date=self.day,
        )
        self.assertEqual(row.status, AttendanceStatus.PRESENT)

    def test_a_day_outside_every_period_is_still_editable(self):
        self.verified()
        response = self.save_day([{
            'worker_id': self.worker.pk, 'status': 'absent',
            'overtime_hours': '0',
        }], work_date=date(2026, 10, 20))

        self.assertEqual(response.status_code, 200, response.data)
        self.period.refresh_from_db()
        self.assertEqual(self.period.status, PayrollStatus.VERIFIED)


# --------------------------------------------------------------------------
# Lines, advances and the deduction placeholder
# --------------------------------------------------------------------------

class PayrollLineTests(PayrollWriteCase):
    def test_lines_before_processing_are_computed_and_deductions_unconfigured(self):
        response = self.get_lines()
        self.assertEqual(response.status_code, 200, response.data)

        rows = {row['worker_id']: row for row in response.data}
        self.assertEqual(set(rows), {self.worker.pk, self.second.pk})
        mine = rows[self.worker.pk]
        self.assertEqual(mine['payroll_period_id'], self.period.pk)
        self.assertEqual(mine['days_worked'], '1.50')
        self.assertEqual(mine['overtime_pay'], OVERTIME_PAY)
        self.assertEqual(mine['gross_pay'], GROSS)
        self.assertEqual(mine['cash_advance'], '0.00')
        self.assertEqual(mine['statutory_deductions'], '0.00')
        self.assertEqual(mine['deductions_policy'], 'unconfigured')
        self.assertEqual(mine['net_pay'], GROSS)
        self.assertEqual(rows[self.second.pk]['net_pay'], '750.00')

    def test_site_engineer_and_admin_never_see_wages(self):
        for user, role in (
            (self.engineer, Role.SITE_ENGINEER),
            (self.admin, Role.ADMIN),
        ):
            with self.subTest(role=role):
                self.act_as(user, role)
                lines = self.client.get(self.period_url(self.period, 'lines/'))
                cost = self.client.get(
                    f'{LABOR_COST_URL}?project={self.project.pk}',
                )
                self.assertEqual(lines.status_code, 403, lines.data)
                self.assertEqual(cost.status_code, 403, cost.data)

    def test_cash_advance_reduces_net_pay(self):
        response = self.post_advance(self.worker.pk, '100.00')
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data['cash_advance'], '100.00')
        self.assertEqual(response.data['net_pay'], '1259.38')

        lines = self.get_lines()
        rows = {row['worker_id']: row for row in lines.data}
        self.assertEqual(rows[self.worker.pk]['cash_advance'], '100.00')
        self.assertEqual(rows[self.worker.pk]['net_pay'], '1259.38')

        # Setting it again replaces the amount; the row is never duplicated.
        again = self.post_advance(self.worker.pk, '0.00')
        self.assertEqual(again.status_code, 200, again.data)
        self.assertEqual(again.data['net_pay'], GROSS)

    def test_cash_advance_bounds_and_unknown_worker(self):
        cases = (
            ('-1.00', 'Enter 0 or more.'),
            ('2000.00', 'Cash advance cannot exceed gross pay.'),
        )
        for amount, text in cases:
            with self.subTest(amount=amount):
                response = self.post_advance(self.worker.pk, amount)
                self.assertEqual(response.status_code, 400, response.data)
                self.assertEqual(response.data['detail'], text)

        absent = self.post_advance(self.retired.pk, '10.00')
        self.assertEqual(absent.status_code, 400, absent.data)
        self.assertEqual(
            absent.data['detail'],
            'This worker has no attendance in the period.',
        )

        for amount in ('NaN', 'Infinity'):
            with self.subTest(amount=amount):
                response = self.post_advance(self.worker.pk, amount)
                self.assertEqual(response.status_code, 400, response.data)

    def test_only_the_accountant_moves_a_cash_advance(self):
        for user, role in (
            (self.owner, Role.OWNER),
            (self.engineer, Role.SITE_ENGINEER),
        ):
            with self.subTest(role=role):
                response = self.post_advance(
                    self.worker.pk, '10.00', user=user, role=role,
                )
                self.assertEqual(response.status_code, 403, response.data)


# --------------------------------------------------------------------------
# Processing and labor cost
# --------------------------------------------------------------------------

class ProcessAndCostTests(PayrollWriteCase):
    def verified(self, period=None):
        period = period or self.period
        period.status = PayrollStatus.VERIFIED
        period.save(update_fields=['status'])
        return period

    def test_process_requires_verification(self):
        self.act_as(self.accountant, Role.ACCOUNTANT)
        response = self.client.post(self.period_url(self.period, 'process/'))
        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(
            response.data['detail'],
            'The owner must verify attendance before payroll is processed.',
        )
        self.assertEqual(PayrollLine.objects.count(), 0)

    def test_only_the_accountant_processes(self):
        self.verified()
        for user, role in (
            (self.owner, Role.OWNER),
            (self.engineer, Role.SITE_ENGINEER),
        ):
            with self.subTest(role=role):
                self.act_as(user, role)
                response = self.client.post(
                    self.period_url(self.period, 'process/'),
                )
                self.assertEqual(response.status_code, 403, response.data)

    def test_process_refuses_an_advance_above_the_recomputed_gross(self):
        """A corrected verified day shrinks gross under a stored advance.

        The advance was legal when it was set (gross 1359.38); a half day
        corrected to absent leaves gross 750.00, so processing must refuse
        instead of storing a negative net, and the accountant lowers it.
        """
        today = timezone.localdate()
        first, changed = today - timedelta(days=2), today - timedelta(days=1)
        period = self.make_period(first, changed)
        self.mark(self.project, self.worker, first)
        self.mark(self.project, self.worker, changed,
                  AttendanceStatus.HALF_DAY, '2.00')
        self.post_advance(self.worker.pk, GROSS, period=period)

        self.act_as(self.owner, Role.OWNER)
        verified = self.client.post(self.period_url(period, 'verify/'))
        self.assertEqual(verified.status_code, 200, verified.data)

        corrected = self.save_day([{
            'worker_id': self.worker.pk, 'status': 'absent',
            'overtime_hours': '0',
        }], work_date=changed)
        self.assertEqual(corrected.status_code, 200, corrected.data)
        period.refresh_from_db()
        self.assertEqual(period.status, PayrollStatus.OPEN)

        # The stored advance is now larger than the recomputed gross (750.00).
        rows = {row['worker_id']: row for row in self.get_lines(period).data}
        self.assertEqual(rows[self.worker.pk]['gross_pay'], '750.00')
        self.assertEqual(rows[self.worker.pk]['net_pay'], '-609.38')

        self.act_as(self.owner, Role.OWNER)
        reverified = self.client.post(self.period_url(period, 'verify/'))
        self.assertEqual(reverified.status_code, 200, reverified.data)

        self.act_as(self.accountant, Role.ACCOUNTANT)
        refused = self.client.post(self.period_url(period, 'process/'))
        self.assertEqual(refused.status_code, 400, refused.data)
        self.assertEqual(
            refused.data['detail'], 'Cash advance cannot exceed gross pay.',
        )
        self.assertEqual(PayrollLine.objects.filter(period=period).count(), 0)
        period.refresh_from_db()
        self.assertEqual(period.status, PayrollStatus.VERIFIED)

        # Lowering the advance to the recomputed gross is the way forward.
        lowered = self.post_advance(self.worker.pk, '750.00', period=period)
        self.assertEqual(lowered.status_code, 200, lowered.data)
        self.assertEqual(lowered.data['net_pay'], '0.00')

        processed = self.client.post(self.period_url(period, 'process/'))
        self.assertEqual(processed.status_code, 200, processed.data)
        line = PayrollLine.objects.get(period=period, worker=self.worker)
        self.assertEqual(line.net_pay, Decimal('0.00'))

    def test_process_snapshots_lines_and_locks_the_period(self):
        self.verified()
        self.post_advance(self.worker.pk, '59.38')

        self.act_as(self.accountant, Role.ACCOUNTANT)
        response = self.client.post(self.period_url(self.period, 'process/'))
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data['status'], 'processed')

        lines = PayrollLine.objects.filter(period=self.period)
        self.assertEqual(lines.count(), 2)
        mine = lines.get(worker=self.worker)
        self.assertEqual(mine.days_worked, Decimal('1.50'))
        self.assertEqual(mine.overtime_pay, Decimal(OVERTIME_PAY))
        self.assertEqual(mine.gross_pay, Decimal(GROSS))
        self.assertEqual(mine.cash_advance, Decimal('59.38'))
        self.assertEqual(mine.statutory_deductions, Decimal('0.00'))
        self.assertEqual(mine.deductions_policy, 'unconfigured')
        self.assertEqual(mine.net_pay, Decimal('1300.00'))
        self.assertTrue(AuditLog.objects.filter(
            action='payroll_processed', entity='payroll_period',
            entity_id=self.period.pk,
        ).exists())

        again = self.client.post(self.period_url(self.period, 'process/'))
        self.assertEqual(again.status_code, 400, again.data)

        advance = self.post_advance(self.worker.pk, '10.00')
        self.assertEqual(advance.status_code, 400, advance.data)
        self.assertEqual(
            advance.data['detail'], 'This period is already processed.',
        )

    def test_processed_lines_are_stable_snapshots(self):
        self.verified()
        self.act_as(self.accountant, Role.ACCOUNTANT)
        self.client.post(self.period_url(self.period, 'process/'))

        # A wage change after processing never rewrites issued pay.
        self.worker.daily_rate = Decimal('900.00')
        self.worker.save(update_fields=['daily_rate'])

        lines = self.get_lines()
        rows = {row['worker_id']: row for row in lines.data}
        self.assertEqual(rows[self.worker.pk]['gross_pay'], GROSS)
        self.assertEqual(rows[self.worker.pk]['id'], PayrollLine.objects.get(
            period=self.period, worker=self.worker,
        ).pk)

    def test_labor_cost_counts_processed_gross_only(self):
        self.act_as(self.accountant, Role.ACCOUNTANT)
        before = self.client.get(f'{LABOR_COST_URL}?project={self.project.pk}')
        self.assertEqual(before.status_code, 200, before.data)
        self.assertEqual(before.data['labor_cost'], '0.00')

        self.verified()
        self.client.post(self.period_url(self.period, 'process/'))

        after = self.client.get(f'{LABOR_COST_URL}?project={self.project.pk}')
        self.assertEqual(after.status_code, 200, after.data)
        self.assertEqual(after.data['labor_cost'], '2109.38')

        # The other project's open period is not part of its labor cost.
        other = self.make_period(date(2026, 11, 1), date(2026, 11, 15),
                                 project=self.other_project)
        self.assertEqual(
            self.client.get(
                f'{LABOR_COST_URL}?project={self.other_project.pk}',
            ).data['labor_cost'],
            '0.00',
        )
        self.assertEqual(other.status, PayrollStatus.OPEN)

    def test_labor_cost_is_scoped_and_validated(self):
        other = self.make_period(date(2026, 11, 1), date(2026, 11, 15),
                                 project=self.blank_project)
        self.act_as(self.engineer, Role.SITE_ENGINEER)
        # The engineer cannot see this project's money at all (403, not 404).
        hidden = self.client.get(f'{LABOR_COST_URL}?project={other.project_id}')
        self.assertEqual(hidden.status_code, 403, hidden.data)

        self.act_as(self.accountant, Role.ACCOUNTANT)
        self.assertEqual(
            self.client.get(f'{LABOR_COST_URL}?project=999999').status_code, 404,
        )
        self.assertEqual(
            self.client.get(LABOR_COST_URL).status_code, 400,
        )

    def test_payroll_audits_carry_no_wages(self):
        self.verified()
        self.post_advance(self.worker.pk, '100.00')
        self.act_as(self.accountant, Role.ACCOUNTANT)
        self.client.post(self.period_url(self.period, 'process/'))

        allowed = {
            'project', 'period_start', 'period_end', 'worker_id', 'lines',
            'reason',
        }
        for row in AuditLog.objects.filter(
            entity__in=('payroll_period', 'payroll_advance', 'payroll_line'),
        ):
            with self.subTest(action=row.action):
                self.assertLessEqual(set(row.details), allowed, row.details)
                blob = json.dumps(row.details)
                for money in ('1359.38', '234.38', '750.00', '100.00'):
                    self.assertNotIn(money, blob)


# --------------------------------------------------------------------------
# One true race: processing vs saving attendance in the same period
# --------------------------------------------------------------------------

class PayrollConcurrencyTests(PayrollFixtures, TransactionTestCase):
    """Process and attendance-save serialize on the project row.

    `TransactionTestCase` on purpose: the threads need committed rows and their
    own connections. Two outcomes are allowed and both are asserted exactly:
    process first -> the save is refused (locked) and the line is the old
    attendance; save first -> the period is reopened and process is refused.
    A `500`, a half-saved sheet, or a processed period with unseen attendance
    fails the test.
    """

    client_class = APIClient
    serialized_rollback = True

    def test_process_versus_attendance_save(self):
        day = timezone.localdate() - timedelta(days=1)
        self.mark(self.project, self.worker, day, user=self.engineer)
        period = self.make_period(day, day, status=PayrollStatus.VERIFIED)

        results = {}
        barrier = threading.Barrier(2)

        def call(name, user, role, path, body):
            client = APIClient()
            try:
                client.force_authenticate(user=user)
                client.credentials(HTTP_X_ACTIVE_ROLE=role)
                barrier.wait(timeout=10)
                results[name] = client.post(path, body, format='json').status_code
            except Exception as error:  # pragma: no cover - reported below
                results[name] = repr(error)
            finally:
                connections.close_all()

        threads = [
            threading.Thread(target=call, args=(
                'process', self.accountant, Role.ACCOUNTANT,
                self.period_url(period, 'process/'), {},
            )),
            threading.Thread(target=call, args=(
                'save', self.engineer, Role.SITE_ENGINEER,
                SAVE_DAY_URL, {
                    'project_id': self.project.pk,
                    'work_date': day.isoformat(),
                    'entries': [{
                        'worker_id': self.worker.pk, 'status': 'half_day',
                        'overtime_hours': '0',
                    }],
                },
            )),
        ]
        for thread in threads:
            thread.start()
        for thread in threads:
            thread.join(timeout=30)

        period.refresh_from_db()
        attendance = Attendance.objects.get(
            project=self.project, worker=self.worker, work_date=day,
        )

        if results['process'] == 200:
            self.assertEqual(results['save'], 400, results)
            self.assertEqual(period.status, PayrollStatus.PROCESSED)
            self.assertEqual(attendance.status, AttendanceStatus.PRESENT)
            line = PayrollLine.objects.get(period=period)
            self.assertEqual(line.days_worked, Decimal('1.00'))
            self.assertEqual(line.gross_pay, Decimal('750.00'))
        else:
            self.assertEqual(results['process'], 400, results)
            self.assertEqual(results['save'], 200, results)
            self.assertEqual(period.status, PayrollStatus.OPEN)
            self.assertEqual(attendance.status, AttendanceStatus.HALF_DAY)
            self.assertEqual(PayrollLine.objects.filter(period=period).count(), 0)

        self.assertEqual(
            AuditLog.objects.filter(action='payroll_processed').count(),
            1 if results['process'] == 200 else 0,
        )

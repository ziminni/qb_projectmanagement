"""Phase 4 slice A wire-contract tests: workers and project attendance.

Every rule in `planning/backend-integration/contracts/phase-4-labor.md` for this
slice has a test here: the active-role fence (held roles are never unioned),
finance redaction that **omits** wages and government identifiers, accepted
assignment scoping / IDOR, client denial, Trade protection, strict validation,
atomic partial-sheet saves, cross-project presence uniqueness (including a real
concurrent race) and audit rows that carry no confidential data.

Payroll periods, processing, costs and the Flutter HTTP adapter are later
slices and are deliberately absent.
"""

# Pyright here runs without django-stubs, so model managers are untyped.
# pyright: reportAttributeAccessIssue=false, reportArgumentType=false

import json
import threading
from datetime import date, timedelta
from decimal import Decimal
from unittest import mock

from django.db import IntegrityError, connections, transaction
from django.test import TransactionTestCase
from django.utils import timezone
from rest_framework.test import APIClient, APITestCase

from ..company.models import Company
from ..master_data.models import Trade
from ..projects.models import (
    Client,
    Project,
    ProjectAssignment,
    ProjectStatus,
    RequestResponse,
    RoleOnProject,
)
from ..users.models import AuditLog, Role
from ..users.tests import make_user
from . import rules
from .models import Attendance, AttendanceStatus, Worker

WORKERS_URL = '/api/v1/workers/'
ATTENDANCE_URL = '/api/v1/attendance/'
SAVE_DAY_URL = '/api/v1/attendance/save-day/'

# Keys a non-finance role must never receive.
CONFIDENTIAL_WORKER_KEYS = ('daily_rate', 'sss_no', 'philhealth_no', 'pagibig_no')


class LaborFixtures:
    """Two in-scope projects, one pending request, all five roles and workers."""

    def setUp(self):
        # A TransactionTestCase flushes the database, so the seeded company may
        # be gone: create one rather than depending on another suite's state.
        if not Company.objects.exists():
            Company.objects.create(name='BuildPro Test')
        self.owner = make_user('maria@example.com', [Role.OWNER])
        self.accountant = make_user('liza@example.com', [Role.ACCOUNTANT])
        self.admin = make_user('admin@example.com', [Role.ADMIN])
        self.engineer = make_user('ramon@example.com', [Role.SITE_ENGINEER])
        self.other_engineer = make_user('eng2@example.com', [Role.SITE_ENGINEER])
        self.client_user = make_user('elena@example.com', [Role.CLIENT])
        # Holds two roles on purpose: the active role decides, never the union.
        self.dual = make_user('dual@example.com', [Role.ADMIN, Role.OWNER])
        self.client_record = Client.objects.create(
            name='Acme Holdings', user=self.client_user,
        )

        self.project = self.make_project('PRJ-A', 'Tower A')
        self.other_project = self.make_project('PRJ-B', 'Tower B')
        self.pending_project = self.make_project('PRJ-C', 'Tower C')
        self.join(self.project, self.owner, RoleOnProject.OWNER)
        self.join(self.project, self.engineer, RoleOnProject.SITE_ENGINEER)
        self.join(self.other_project, self.owner, RoleOnProject.OWNER)
        self.join(self.other_project, self.engineer, RoleOnProject.SITE_ENGINEER)
        # The engineer asked for this one; the owner has not answered yet.
        ProjectAssignment.objects.create(
            project=self.pending_project, user=self.engineer,
            role_on_project=RoleOnProject.SITE_ENGINEER,
            response=RequestResponse.PENDING,
        )

        self.mason = Trade.objects.create(name='Mason')
        self.carpenter = Trade.objects.create(name='Carpenter')
        self.laborer = Trade.objects.create(name='Laborer')
        self.worker = self.make_worker(
            'Rodel Macaraig', self.mason, '750.00',
            sss_no='34-1234561-1', philhealth_no='12-345678901-1',
            pagibig_no='1211-0000-0001',
        )
        self.second = self.make_worker('Arnel Dimaano', self.mason, '750.00')
        self.retired = self.make_worker(
            'Pablo Garcia', self.laborer, '610.00', is_active=False,
        )

    # --- fixtures -------------------------------------------------------
    def make_project(self, code, name, status=ProjectStatus.ONGOING):
        return Project.objects.create(
            code=code, name=name, client=self.client_record,
            contract_amount=Decimal('1000000.00'),
            start_date=date(2026, 1, 1), target_end_date=date(2026, 6, 30),
            status=status,
        )

    def join(self, project, user, role_on_project,
             response=RequestResponse.ACCEPTED):
        return ProjectAssignment.objects.create(
            project=project, user=user, role_on_project=role_on_project,
            response=response,
        )

    def make_worker(self, full_name, trade, rate, is_active=True, **extra):
        return Worker.objects.create(
            full_name=full_name, trade=trade, daily_rate=Decimal(rate),
            is_active=is_active, **extra,
        )

    def act_as(self, user, role):
        self.client.force_authenticate(user=user)
        self.client.credentials(HTTP_X_ACTIVE_ROLE=role)

    def mark(self, project, worker, work_date, status=AttendanceStatus.PRESENT,
             overtime='0.00', user=None):
        return Attendance.objects.create(
            project=project, worker=worker, work_date=work_date,
            status=status, overtime_hours=Decimal(overtime),
            recorded_by=user or self.engineer,
        )

    def save_day(self, entries, project=None, work_date=None, user=None,
                 role=Role.SITE_ENGINEER):
        if user is not None:
            self.act_as(user, role)
        else:
            self.act_as(self.engineer, Role.SITE_ENGINEER)
        return self.client.post(SAVE_DAY_URL, {
            'project_id': (project or self.project).pk,
            'work_date': (work_date or timezone.localdate()).isoformat(),
            'entries': entries,
        }, format='json')


class LaborCase(LaborFixtures, APITestCase):
    """The normal case: fixtures plus an API client (one rolled-back test)."""


# --------------------------------------------------------------------------
# Workers: reads, redaction, picker
# --------------------------------------------------------------------------

class WorkerReadTests(LaborCase):
    def test_staff_picker_is_paginated_and_ordered_by_name(self):
        self.act_as(self.engineer, Role.SITE_ENGINEER)
        response = self.client.get(WORKERS_URL)

        self.assertEqual(response.status_code, 200, response.data)
        names = [row['full_name'] for row in response.data['results']]
        self.assertEqual(names, sorted(names))
        self.assertEqual(
            names, ['Arnel Dimaano', 'Pablo Garcia', 'Rodel Macaraig'],
        )

    def test_active_only_filters_and_is_strictly_parsed(self):
        self.act_as(self.engineer, Role.SITE_ENGINEER)
        active = self.client.get(f'{WORKERS_URL}?active_only=true')

        self.assertEqual(active.status_code, 200, active.data)
        self.assertEqual(
            [row['full_name'] for row in active.data['results']],
            ['Arnel Dimaano', 'Rodel Macaraig'],
        )

        junk = self.client.get(f'{WORKERS_URL}?active_only=maybe')
        self.assertEqual(junk.status_code, 400, junk.data)

    def test_non_finance_roles_omit_wages_and_identifiers(self):
        for user, role in (
            (self.engineer, Role.SITE_ENGINEER),
            (self.admin, Role.ADMIN),
        ):
            with self.subTest(role=role):
                self.act_as(user, role)
                listing = self.client.get(WORKERS_URL)
                detail = self.client.get(f'{WORKERS_URL}{self.worker.pk}/')

                self.assertEqual(listing.status_code, 200, listing.data)
                self.assertEqual(detail.status_code, 200, detail.data)
                for row in listing.data['results'] + [detail.data]:
                    for key in CONFIDENTIAL_WORKER_KEYS:
                        self.assertNotIn(key, row)
                    self.assertEqual(row['full_name'], 'Rodel Macaraig'
                                     if row['id'] == self.worker.pk
                                     else row['full_name'])
                    self.assertIn('trade', row)
                    self.assertIn('is_active', row)

    def test_finance_roles_receive_the_full_worker_row(self):
        for user, role in (
            (self.owner, Role.OWNER),
            (self.accountant, Role.ACCOUNTANT),
        ):
            with self.subTest(role=role):
                self.act_as(user, role)
                response = self.client.get(f'{WORKERS_URL}{self.worker.pk}/')

                self.assertEqual(response.status_code, 200, response.data)
                self.assertEqual(response.data['trade'], 'Mason')
                self.assertEqual(Decimal(response.data['daily_rate']), Decimal('750.00'))
                self.assertEqual(response.data['sss_no'], '34-1234561-1')
                self.assertEqual(response.data['philhealth_no'], '12-345678901-1')
                self.assertEqual(response.data['pagibig_no'], '1211-0000-0001')

    def test_active_admin_role_is_not_a_finance_role(self):
        """A user holding admin+owner gets the admin answer while acting as admin."""
        self.act_as(self.dual, Role.ADMIN)
        as_admin = self.client.get(f'{WORKERS_URL}{self.worker.pk}/')
        self.act_as(self.dual, Role.OWNER)
        as_owner = self.client.get(f'{WORKERS_URL}{self.worker.pk}/')

        self.assertNotIn('daily_rate', as_admin.data)
        self.assertIn('daily_rate', as_owner.data)

    def test_client_is_denied_every_worker_route(self):
        self.act_as(self.client_user, Role.CLIENT)

        self.assertEqual(self.client.get(WORKERS_URL).status_code, 403)
        self.assertEqual(self.client.get(f'{WORKERS_URL}{self.worker.pk}/').status_code, 403)
        self.assertEqual(self.client.post(WORKERS_URL, {}, format='json').status_code, 403)


# --------------------------------------------------------------------------
# Workers: maintenance
# --------------------------------------------------------------------------

class WorkerWriteTests(LaborCase):
    def payload(self, **overrides):
        payload = {
            'full_name': '  Bong Perez  ',
            'trade': 'Mason',
            'daily_rate': '750.00',
            'sss_no': '34-1234564-4',
            'philhealth_no': None,
            'pagibig_no': '',
            'is_active': True,
        }
        payload.update(overrides)
        return payload

    def test_owner_creates_a_worker_with_a_resolved_trade_and_an_audit(self):
        self.act_as(self.owner, Role.OWNER)
        response = self.client.post(WORKERS_URL, self.payload(trade=' mason '),
                                    format='json')

        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(response.data['full_name'], 'Bong Perez')
        self.assertEqual(response.data['trade'], 'Mason')
        self.assertEqual(response.data['is_active'], True)
        worker = Worker.objects.get(pk=response.data['id'])
        self.assertEqual(worker.trade, self.mason)
        self.assertEqual(worker.daily_rate, Decimal('750.00'))

        audit = AuditLog.objects.get(action='worker_created', entity='worker',
                                     entity_id=worker.pk)
        self.assertEqual(audit.details['name'], 'Bong Perez')
        # No wage and no government identifier reaches a broadly visible row.
        flat = json.dumps(audit.details)
        for secret in ('750', '34-1234564-4', 'daily_rate', 'sss_no'):
            self.assertNotIn(secret, flat)

    def test_accountant_creates_and_patches_a_worker(self):
        self.act_as(self.accountant, Role.ACCOUNTANT)
        created = self.client.post(WORKERS_URL, self.payload(), format='json')
        self.assertEqual(created.status_code, 201, created.data)

        response = self.client.patch(
            f'{WORKERS_URL}{created.data["id"]}/',
            {'full_name': ' Bong P. ', 'daily_rate': '800.00'}, format='json',
        )
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data['full_name'], 'Bong P.')
        self.assertEqual(Decimal(response.data['daily_rate']), Decimal('800.00'))
        self.assertEqual(response.data['sss_no'], '34-1234564-4')

    def test_patch_without_a_rate_keeps_the_stored_one(self):
        self.act_as(self.owner, Role.OWNER)
        response = self.client.patch(
            f'{WORKERS_URL}{self.worker.pk}/', {'is_active': False}, format='json',
        )

        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(Decimal(response.data['daily_rate']), Decimal('750.00'))
        self.assertFalse(response.data['is_active'])
        self.assertTrue(
            AuditLog.objects.filter(action='worker_updated', entity='worker',
                                    entity_id=self.worker.pk).exists()
        )

    def test_role_fence_for_maintenance_uses_the_active_role_only(self):
        for user, role in (
            (self.admin, Role.ADMIN),
            (self.engineer, Role.SITE_ENGINEER),
            (self.client_user, Role.CLIENT),
        ):
            with self.subTest(role=role):
                self.act_as(user, role)
                response = self.client.post(WORKERS_URL, self.payload(), format='json')
                self.assertEqual(response.status_code, 403, response.data)

        self.act_as(self.dual, Role.ADMIN)  # holds owner too; union must not count.
        self.assertEqual(
            self.client.post(WORKERS_URL, self.payload(), format='json').status_code,
            403,
        )
        self.act_as(self.dual, Role.OWNER)
        self.assertEqual(
            self.client.post(WORKERS_URL, self.payload(), format='json').status_code,
            201,
        )

    def test_worker_has_no_delete_and_no_put(self):
        self.act_as(self.owner, Role.OWNER)

        self.assertEqual(self.client.delete(f'{WORKERS_URL}{self.worker.pk}/').status_code, 405)
        self.assertEqual(self.client.put(f'{WORKERS_URL}{self.worker.pk}/', {}).status_code, 405)
        self.assertTrue(Worker.objects.filter(pk=self.worker.pk).exists())

    def test_name_trade_and_rate_validation_refuses_and_writes_nothing(self):
        self.act_as(self.owner, Role.OWNER)
        cases = (
            ({'full_name': '   '}, rules.WORKER_NAME),
            ({'trade': 'Plumber'}, rules.WORKER_TRADE),
            ({'trade': '  '}, rules.WORKER_TRADE),
            ({'daily_rate': '0'}, rules.RATE_POSITIVE),
            ({'daily_rate': '-750'}, rules.RATE_POSITIVE),
            ({'daily_rate': '750.123'}, rules.RATE_PRECISION),
            ({'daily_rate': 'abc'}, rules.RATE_INVALID),
            ({'daily_rate': 'NaN'}, rules.RATE_INVALID),
            ({'daily_rate': 'Infinity'}, rules.RATE_INVALID),
            ({'daily_rate': '-Infinity'}, rules.RATE_INVALID),
            ({'daily_rate': 750.0}, None),  # a JSON number is fine
        )
        before = Worker.objects.count()
        for overrides, message in cases:
            with self.subTest(overrides=overrides):
                response = self.client.post(WORKERS_URL, self.payload(**overrides),
                                            format='json')
                if message is None:
                    self.assertEqual(response.status_code, 201, response.data)
                else:
                    self.assertEqual(response.status_code, 400, response.data)
                    self.assertEqual(response.data['detail'], message)
        self.assertEqual(Worker.objects.count(), before + 1)

    def test_missing_rate_on_create_is_refused(self):
        self.act_as(self.owner, Role.OWNER)
        payload = self.payload()
        payload.pop('daily_rate')
        response = self.client.post(WORKERS_URL, payload, format='json')

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(response.data['detail'], rules.RATE_POSITIVE)

    def test_is_active_is_parsed_strictly(self):
        self.act_as(self.owner, Role.OWNER)
        for value in ('false', 'true', 0, 1, 'no'):
            with self.subTest(value=value):
                response = self.client.post(
                    WORKERS_URL, self.payload(is_active=value), format='json',
                )
                self.assertEqual(response.status_code, 400, response.data)

    def test_unknown_fields_cannot_set_server_owned_values(self):
        self.act_as(self.owner, Role.OWNER)
        response = self.client.post(WORKERS_URL, self.payload(
            id=999, created_at='2020-01-01T00:00:00Z',
        ), format='json')

        self.assertEqual(response.status_code, 201, response.data)
        self.assertNotEqual(response.data['id'], 999)

    def test_worker_retrieve_is_staff_only_and_company_wide(self):
        # Workers are company-wide: no project scope applies to the picker.
        self.act_as(self.engineer, Role.SITE_ENGINEER)
        response = self.client.get(f'{WORKERS_URL}{self.retired.pk}/')
        self.assertEqual(response.status_code, 200, response.data)
        self.assertFalse(response.data['is_active'])


# --------------------------------------------------------------------------
# Trade protection
# --------------------------------------------------------------------------

class TradeProtectionTests(LaborCase):
    def test_a_trade_used_by_a_worker_cannot_be_deleted(self):
        self.act_as(self.owner, Role.OWNER)
        response = self.client.delete(f'/api/v1/master-data/trades/{self.mason.pk}/')

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(response.data['detail'], rules.TRADE_IN_USE)
        self.assertTrue(Trade.objects.filter(pk=self.mason.pk).exists())
        self.assertFalse(
            AuditLog.objects.filter(action='trade_deleted',
                                    entity_id=self.mason.pk).exists()
        )

    def test_an_unused_trade_still_deletes_with_its_audit(self):
        self.act_as(self.owner, Role.OWNER)
        response = self.client.delete(f'/api/v1/master-data/trades/{self.carpenter.pk}/')

        self.assertEqual(response.status_code, 204)
        self.assertFalse(Trade.objects.filter(pk=self.carpenter.pk).exists())
        self.assertTrue(
            AuditLog.objects.filter(action='trade_deleted',
                                    entity_id=self.carpenter.pk).exists()
        )


# --------------------------------------------------------------------------
# Attendance reads
# --------------------------------------------------------------------------

class AttendanceReadTests(LaborCase):
    def setUp(self):
        super().setUp()
        self.day = date(2026, 3, 2)
        self.mark(self.project, self.worker, self.day)
        self.mark(self.project, self.second, self.day, AttendanceStatus.HALF_DAY,
                  overtime='2.00')
        self.mark(self.project, self.worker, self.day + timedelta(days=1),
                  AttendanceStatus.ABSENT)
        self.mark(self.other_project, self.retired, self.day)

    def test_project_is_required_and_must_be_a_number(self):
        self.act_as(self.engineer, Role.SITE_ENGINEER)

        missing = self.client.get(ATTENDANCE_URL)
        junk = self.client.get(f'{ATTENDANCE_URL}?project=abc')

        self.assertEqual(missing.status_code, 400, missing.data)
        self.assertEqual(missing.data['detail'], rules.PROJECT_REQUIRED)
        self.assertEqual(junk.status_code, 400, junk.data)

    def test_assigned_engineer_reads_only_that_project(self):
        self.act_as(self.engineer, Role.SITE_ENGINEER)
        response = self.client.get(f'{ATTENDANCE_URL}?project={self.project.pk}')

        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(len(response.data), 3)
        self.assertEqual({row['project_id'] for row in response.data},
                         {self.project.pk})
        self.assertEqual(
            set(response.data[0]),
            {'id', 'project_id', 'worker_id', 'work_date', 'status',
             'overtime_hours', 'recorded_by', 'created_at', 'updated_at'},
        )
        for row in response.data:
            for key in ('full_name', 'daily_rate', 'sss_no', 'trade'):
                self.assertNotIn(key, row)

    def test_dates_are_inclusive_and_ordered(self):
        self.act_as(self.engineer, Role.SITE_ENGINEER)
        response = self.client.get(
            f'{ATTENDANCE_URL}?project={self.project.pk}'
            f'&from={self.day.isoformat()}&to={self.day.isoformat()}',
        )

        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(
            [(row['work_date'], row['status']) for row in response.data],
            [(self.day.isoformat(), 'present'),
             (self.day.isoformat(), 'half_day')],
        )

    def test_malformed_or_reversed_bounds_are_refused(self):
        self.act_as(self.engineer, Role.SITE_ENGINEER)
        base = f'{ATTENDANCE_URL}?project={self.project.pk}'
        malformed = self.client.get(f'{base}&from=2026-3-2')
        reversed_bounds = self.client.get(
            f'{base}&from={self.day.isoformat()}&to=2026-03-01',
        )

        self.assertEqual(malformed.status_code, 400, malformed.data)
        self.assertEqual(reversed_bounds.status_code, 400, reversed_bounds.data)

    def test_out_of_scope_pending_and_client_reads_are_refused(self):
        self.act_as(self.engineer, Role.SITE_ENGINEER)
        pending = self.client.get(f'{ATTENDANCE_URL}?project={self.pending_project.pk}')
        self.assertEqual(pending.status_code, 404)

        self.act_as(self.other_engineer, Role.SITE_ENGINEER)
        foreign = self.client.get(f'{ATTENDANCE_URL}?project={self.project.pk}')
        self.assertEqual(foreign.status_code, 404)

        self.act_as(self.client_user, Role.CLIENT)
        client = self.client.get(f'{ATTENDANCE_URL}?project={self.project.pk}')
        self.assertEqual(client.status_code, 403)

    def test_owner_and_company_wide_roles_read_the_assigned_project(self):
        for user, role in (
            (self.owner, Role.OWNER),
            (self.accountant, Role.ACCOUNTANT),
            (self.admin, Role.ADMIN),
        ):
            with self.subTest(role=role):
                self.act_as(user, role)
                response = self.client.get(
                    f'{ATTENDANCE_URL}?project={self.project.pk}',
                )
                self.assertEqual(response.status_code, 200, response.data)
                self.assertEqual(len(response.data), 3)

    def test_there_is_no_generic_attendance_write_or_detail_route(self):
        self.act_as(self.engineer, Role.SITE_ENGINEER)

        # Only `save-day/` writes, and no detail route exists at all.
        self.assertEqual(self.client.post(ATTENDANCE_URL, {}, format='json').status_code, 405)
        self.assertEqual(
            self.client.patch(f'{ATTENDANCE_URL}{self.project.pk}/', {}).status_code, 404)
        self.assertEqual(
            self.client.get(f'{ATTENDANCE_URL}{self.project.pk}/').status_code, 404)


# --------------------------------------------------------------------------
# Attendance save-day
# --------------------------------------------------------------------------

class AttendanceSaveTests(LaborCase):
    def setUp(self):
        super().setUp()
        # Today is allowed (only future dates are refused); the helper defaults
        # to it, so seeding and corrections land on the same day.
        self.day = timezone.localdate()

    def entry(self, worker=None, status=AttendanceStatus.PRESENT, overtime='0'):
        return {
            'worker_id': (worker or self.worker).pk,
            'status': status,
            'overtime_hours': overtime,
        }

    def test_engineer_saves_a_day_and_the_server_owns_the_actor(self):
        response = self.save_day([
            self.entry(overtime='1.50'),
            self.entry(self.second, AttendanceStatus.ABSENT, overtime='5'),
        ])

        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(len(response.data), 2)
        rows = {row['worker_id']: row for row in response.data}
        self.assertEqual(rows[self.worker.pk]['status'], 'present')
        self.assertEqual(Decimal(rows[self.worker.pk]['overtime_hours']), Decimal('1.50'))
        # Absent normalises overtime to zero after validating the range.
        self.assertEqual(Decimal(rows[self.second.pk]['overtime_hours']), Decimal(0))
        for row in response.data:
            self.assertEqual(row['recorded_by'], self.engineer.pk)
            self.assertEqual(row['work_date'], self.day.isoformat())
        self.assertEqual(
            AuditLog.objects.filter(action='attendance_saved', entity='attendance').count(),
            2,
        )

    def test_partial_sheet_replaces_only_the_listed_workers(self):
        self.save_day([self.entry(), self.entry(self.second)])
        original = {
            row.worker_id: row
            for row in Attendance.objects.filter(project=self.project)
        }

        response = self.save_day([self.entry(status=AttendanceStatus.HALF_DAY,
                                             overtime='4')])
        self.assertEqual(response.status_code, 200, response.data)

        rows = {
            row.worker_id: row
            for row in Attendance.objects.filter(project=self.project)
        }
        self.assertEqual(len(rows), 2)
        self.assertEqual(rows[self.worker.pk].status, 'half_day')
        self.assertEqual(rows[self.worker.pk].overtime_hours, Decimal('4.00'))
        self.assertEqual(rows[self.worker.pk].pk, original[self.worker.pk].pk)
        self.assertEqual(rows[self.second.pk].status, 'present')
        self.assertEqual(rows[self.second.pk].overtime_hours, Decimal('0.00'))
        self.assertEqual(rows[self.second.pk].pk, original[self.second.pk].pk)

    def test_empty_entries_is_a_no_op(self):
        response = self.save_day([])

        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data, [])
        self.assertEqual(Attendance.objects.count(), 0)
        self.assertFalse(
            AuditLog.objects.filter(action='attendance_saved').exists()
        )

    def test_bad_entries_refuse_the_whole_save_without_audits(self):
        cases = (
            ([self.entry(), {'worker_id': 999999, 'status': 'present'}],
             rules.UNKNOWN_WORKER),
            ([self.entry(), self.entry()], rules.DUPLICATE_WORKER),
            ([{'worker_id': self.worker.pk, 'status': 'sick'}], rules.ENTRY_STATUS),
            ([{'status': 'present'}], rules.UNKNOWN_WORKER),
            ([self.entry(overtime='-1')], rules.OVERTIME_NEGATIVE),
            ([self.entry(overtime='12.5')], rules.OVERTIME_RANGE),
            ([self.entry(overtime='NaN')], rules.OVERTIME_INVALID),
            ([self.entry(overtime='Infinity')], rules.OVERTIME_INVALID),
            ([self.entry(overtime=True)], rules.OVERTIME_INVALID),
        )
        for entries, message in cases:
            with self.subTest(entries=entries):
                response = self.save_day(entries)
                self.assertEqual(response.status_code, 400, response.data)
                self.assertEqual(response.data['detail'], message)
                self.assertEqual(Attendance.objects.count(), 0)
                self.assertFalse(
                    AuditLog.objects.filter(action='attendance_saved').exists()
                )

    def test_future_date_is_refused_using_the_manila_date(self):
        tomorrow = timezone.localdate() + timedelta(days=1)
        response = self.save_day([self.entry()], work_date=tomorrow)

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(response.data['detail'], rules.FUTURE_DATE)

    def test_work_date_must_be_strict_iso(self):
        for value in ('2026-3-2', 'yesterday', '2026-02-30'):
            with self.subTest(value=value):
                self.act_as(self.engineer, Role.SITE_ENGINEER)
                response = self.client.post(SAVE_DAY_URL, {
                    'project_id': self.project.pk,
                    'work_date': value,
                    'entries': [self.entry()],
                }, format='json')
                self.assertEqual(response.status_code, 400, response.data)

    def test_project_id_must_be_sent(self):
        self.act_as(self.engineer, Role.SITE_ENGINEER)
        for payload in (
            {'work_date': self.day.isoformat(), 'entries': []},
            {'project_id': 'abc', 'work_date': self.day.isoformat(), 'entries': []},
        ):
            with self.subTest(payload=payload):
                response = self.client.post(SAVE_DAY_URL, payload, format='json')
                self.assertEqual(response.status_code, 400, response.data)

    def test_inactive_worker_cannot_get_a_new_row_but_may_be_corrected(self):
        self.mark(self.project, self.retired, self.day,
                  AttendanceStatus.PRESENT, user=self.engineer)

        corrected = self.save_day([
            self.entry(self.retired, AttendanceStatus.HALF_DAY, overtime='1'),
        ])
        self.assertEqual(corrected.status_code, 200, corrected.data)
        self.assertEqual(corrected.data[0]['status'], 'half_day')

        new_day = self.day - timedelta(days=1)
        refused = self.save_day([self.entry(self.retired)], work_date=new_day)
        self.assertEqual(refused.status_code, 400, refused.data)
        self.assertEqual(refused.data['detail'], rules.INACTIVE_WORKER)
        self.assertFalse(Attendance.objects.filter(work_date=new_day).exists())

    def test_cross_project_presence_conflicts_but_absence_is_allowed(self):
        self.save_day([self.entry()])
        conflict = self.save_day([self.entry()], project=self.other_project)

        self.assertEqual(conflict.status_code, 400, conflict.data)
        self.assertIn('Rodel Macaraig', conflict.data['detail'])
        self.assertFalse(Attendance.objects.filter(project=self.other_project).exists())

        # Same day, other worker: present at A, then absent at B is allowed.
        self.save_day([self.entry(self.second, AttendanceStatus.PRESENT)])
        absent_elsewhere = self.save_day(
            [self.entry(self.second, AttendanceStatus.ABSENT)],
            project=self.other_project,
        )
        self.assertEqual(absent_elsewhere.status_code, 200, absent_elsewhere.data)
        # And the reverse: absent at A, present at B is allowed.
        third = self.make_worker('Nilo Aguilar', self.laborer, '610.00')
        self.save_day([self.entry(third, AttendanceStatus.ABSENT, overtime='0')])
        present_elsewhere = self.save_day(
            [self.entry(third, AttendanceStatus.PRESENT)],
            project=self.other_project,
        )
        self.assertEqual(present_elsewhere.status_code, 200, present_elsewhere.data)

    def test_attendance_write_requires_the_active_site_engineer_role(self):
        for user, role in (
            (self.owner, Role.OWNER),
            (self.accountant, Role.ACCOUNTANT),
            (self.admin, Role.ADMIN),
            (self.client_user, Role.CLIENT),
            (self.dual, Role.ADMIN),
        ):
            with self.subTest(role=role):
                response = self.save_day([self.entry()], user=user, role=role)
                self.assertEqual(response.status_code, 403, response.data)
                self.assertEqual(Attendance.objects.count(), 0)

    def test_accepted_assignment_is_required_even_with_the_engineer_role(self):
        pending = self.save_day([self.entry()], project=self.pending_project)
        self.assertEqual(pending.status_code, 404, pending.data)

        self.act_as(self.other_engineer, Role.SITE_ENGINEER)
        foreign = self.client.post(SAVE_DAY_URL, {
            'project_id': self.project.pk,
            'work_date': self.day.isoformat(),
            'entries': [self.entry()],
        }, format='json')
        self.assertEqual(foreign.status_code, 404, foreign.data)
        self.assertEqual(Attendance.objects.count(), 0)

    def test_a_race_that_reaches_the_database_is_a_clean_400(self):
        """The partial unique index backup maps to a `400`, never a `500`.

        The worker-row lock normally serialises competing saves; this pins the
        backstop path by making the insert itself collide.
        """
        self.act_as(self.engineer, Role.SITE_ENGINEER)
        with mock.patch.object(
            Attendance, 'save', side_effect=IntegrityError('duplicate key'),
        ):
            response = self.client.post(SAVE_DAY_URL, {
                'project_id': self.project.pk,
                'work_date': self.day.isoformat(),
                'entries': [self.entry()],
            }, format='json')

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(response.data['detail'], rules.PRESENCE_CONFLICT_GENERIC)
        self.assertEqual(Attendance.objects.count(), 0)
        self.assertFalse(AuditLog.objects.filter(action='attendance_saved').exists())

    def test_body_cannot_override_recorded_by_or_ids(self):
        response = self.save_day([self.entry()])
        self.assertEqual(response.status_code, 200, response.data)

        self.act_as(self.engineer, Role.SITE_ENGINEER)
        patched = self.client.post(SAVE_DAY_URL, {
            'project_id': self.project.pk,
            'work_date': self.day.isoformat(),
            'entries': [{
                'id': 999, 'worker_id': self.worker.pk, 'status': 'present',
                'overtime_hours': 2, 'recorded_by': self.owner.pk,
            }],
        }, format='json')
        self.assertEqual(patched.status_code, 200, patched.data)
        self.assertEqual(patched.data[0]['recorded_by'], self.engineer.pk)
        self.assertNotEqual(patched.data[0]['id'], 999)


class AttendanceConstraintTests(LaborCase):
    """The two database uniqueness rules are real indexes, not view-only checks."""

    def test_presence_at_two_projects_on_one_day_is_a_database_error(self):
        day = date(2026, 3, 2)
        self.mark(self.project, self.worker, day)

        with self.assertRaises(IntegrityError), transaction.atomic():
            self.mark(self.other_project, self.worker, day)

    def test_absence_at_two_projects_on_one_day_is_allowed(self):
        day = date(2026, 3, 2)
        self.mark(self.project, self.worker, day, AttendanceStatus.ABSENT)
        self.mark(self.other_project, self.worker, day, AttendanceStatus.ABSENT)

        self.assertEqual(
            Attendance.objects.filter(worker=self.worker, work_date=day).count(), 2,
        )

    def test_one_row_per_project_worker_day(self):
        day = date(2026, 3, 2)
        self.mark(self.project, self.worker, day)

        with self.assertRaises(IntegrityError), transaction.atomic():
            self.mark(self.project, self.worker, day, AttendanceStatus.HALF_DAY)


class AttendanceConcurrencyTests(LaborFixtures, TransactionTestCase):
    """Two simultaneous saves cannot both mark one worker present on one day.

    `TransactionTestCase` on purpose: worker threads get their own database
    connection, which cannot see rows an `APITestCase` transaction has not
    committed. The save locks worker rows in id order, so the second save waits
    and then sees the first project's row.
    """

    client_class = APIClient

    # This class flushes the database; restore the serialized state afterwards.
    serialized_rollback = True

    def test_simultaneous_cross_project_saves_leave_one_presence(self):
        day = timezone.localdate() - timedelta(days=1)
        payload = {
            'work_date': day.isoformat(),
            'entries': [{
                'worker_id': self.worker.pk, 'status': 'present',
                'overtime_hours': '0',
            }],
        }
        results = []
        barrier = threading.Barrier(2)

        def worker(project):
            client = APIClient()
            try:
                client.force_authenticate(user=self.engineer)
                client.credentials(HTTP_X_ACTIVE_ROLE=Role.SITE_ENGINEER)
                barrier.wait(timeout=10)
                response = client.post(
                    SAVE_DAY_URL, dict(payload, project_id=project.pk),
                    format='json',
                )
                results.append(response.status_code)
            finally:
                connections.close_all()

        threads = [
            threading.Thread(target=worker, args=(self.project,)),
            threading.Thread(target=worker, args=(self.other_project,)),
        ]
        for thread in threads:
            thread.start()
        for thread in threads:
            thread.join(timeout=30)

        self.assertEqual(sorted(results), [200, 400], results)
        present = Attendance.objects.filter(
            worker=self.worker, work_date=day,
        ).exclude(status=AttendanceStatus.ABSENT)
        self.assertEqual(present.count(), 1)
        self.assertEqual(
            AuditLog.objects.filter(action='attendance_saved').count(), 1,
        )

"""Phase 2.2 wire-contract tests: daily reports, approved lists and photos.

Every check in `planning/backend-integration/contracts/phase-2-projects-and-site.md`
under "Daily reports", "State machines" (daily report) and security checks 1, 2,
3, 4 and 7 that belongs to 2.2 has a test here; documents and uploads live in
`tests_uploads.py`, the `Todo.daily_report_id` FK in `tests_migration.py`.

The clock is pinned: `TODAY` is the **Asia/Manila** date for `NOW_UTC`, which is
the next day in UTC. A test therefore proves the server uses the project
timezone and not `date.today()`.
"""

# Pyright here runs without django-stubs, so model managers are untyped.
# pyright: reportAttributeAccessIssue=false, reportArgumentType=false

from datetime import UTC, date, datetime, timedelta
from unittest import mock

from django.core.files.base import ContentFile
from django.utils import timezone
from rest_framework.test import APITestCase

from ..master_data.models import EquipmentItem, MaterialItem
from ..projects.models import (
    Category,
    Client,
    Project,
    ProjectAssignment,
    ProjectStatus,
    RequestResponse,
    RoleOnProject,
    Todo,
)
from ..users.models import AuditLog, Notification, Role
from ..users.tests import make_user
from .models import (
    DailyReport,
    EquipmentLog,
    Issue,
    ReportManpower,
    ReportMaterialUsage,
    ReportPhoto,
)

NOW_UTC = datetime(2026, 11, 14, 20, 0, tzinfo=UTC)  # 04:00 the next day in Manila
TODAY = date(2026, 11, 15)

REPORT_KEYS = {
    'id', 'project_id', 'report_date', 'weather', 'status', 'submitted_by',
    'reviewed_by', 'remarks', 'toolbox_meeting_held', 'created_at', 'updated_at',
}
DETAIL_KEYS = {
    'report', 'manpower', 'materials', 'equipment', 'issues', 'photos', 'todos',
}
MANPOWER_KEYS = {
    'id', 'daily_report_id', 'trade', 'headcount', 'created_at', 'updated_at',
}
MATERIAL_KEYS = {
    'id', 'daily_report_id', 'material_id', 'quantity', 'created_at', 'updated_at',
}
EQUIPMENT_KEYS = {
    'id', 'equipment_id', 'project_id', 'log_date', 'hours_used',
    'daily_report_id', 'created_at', 'updated_at',
}
ISSUE_KEYS = {
    'id', 'project_id', 'daily_report_id', 'type', 'reason', 'description',
    'days_lost', 'created_at', 'updated_at',
}
PHOTO_KEYS = {
    'id', 'daily_report_id', 'file_url', 'caption', 'latitude', 'longitude',
    'taken_at', 'created_at', 'updated_at',
}

NOT_ONGOING = (
    'Daily reports can be added only while the project is Ongoing '
    '(it is Accepted).'
)
NOT_THE_ENGINEER = 'Only the site engineer assigned to this project can file its reports.'
NOT_THE_AUTHOR_EDIT = 'Only the site engineer who wrote this report can edit it.'
NOT_THE_AUTHOR_SUBMIT = 'Only the site engineer who wrote this report can submit it.'
NOT_THE_OWNER_REVIEW = 'Only the owner of this project can review its reports.'
REPORTS_STAFF_ONLY = 'Only the project team can see the site reports.'
ALREADY_DONE = '"Pour slab" is already done.'


class SiteReportCase(APITestCase):
    """Five roles, two projects (A assigned, B not) and one linked to-do."""

    def setUp(self):
        # A pinned clock: Manila is already on the next day at 20:00 UTC.
        patcher = mock.patch('django.utils.timezone.now', return_value=NOW_UTC)
        patcher.start()
        self.addCleanup(patcher.stop)

        self.admin = make_user('admin@example.com', [Role.ADMIN])
        self.owner = make_user('maria@example.com', [Role.OWNER])
        self.other_owner = make_user('owner2@example.com', [Role.OWNER])
        self.engineer = make_user('ramon@example.com', [Role.SITE_ENGINEER])
        self.engineer2 = make_user('eng2@example.com', [Role.SITE_ENGINEER])
        self.accountant = make_user('liza@example.com', [Role.ACCOUNTANT])
        self.client_user = make_user('elena@example.com', [Role.CLIENT])
        self.client_record = Client.objects.create(
            name='Acme Holdings', user=self.client_user,
        )

        self.project = self.make_project('PRJ-A', 'Tower A')
        self.other_project = self.make_project('PRJ-B', 'Tower B')
        self.join(self.project, self.owner, RoleOnProject.OWNER)
        self.join(self.project, self.engineer, RoleOnProject.SITE_ENGINEER)
        self.join(self.project, self.engineer2, RoleOnProject.SITE_ENGINEER)
        self.join(self.project, self.client_user, RoleOnProject.CLIENT)
        self.category = Category.objects.create(
            project=self.project, name='Siteworks', sort_order=1,
        )
        self.todo = Todo.objects.create(
            category=self.category, title='Pour slab',
            start_date=date(2026, 11, 1), end_date=date(2026, 11, 30),
        )
        self.other_category = Category.objects.create(
            project=self.other_project, name='Siteworks', sort_order=1,
        )
        self.other_todo = Todo.objects.create(
            category=self.other_category, title='Excavate B',
            start_date=date(2026, 11, 1), end_date=date(2026, 11, 30),
        )
        self.material = MaterialItem.objects.create(name='Portland cement', unit='bag')
        self.equipment = EquipmentItem.objects.create(name='Backhoe')

    # --- fixtures ---
    def make_project(self, code, name, **extra):
        defaults = {
            'location': 'Cebu City',
            'client': self.client_record,
            'contract_amount': '1000000.00',
            'start_date': date(2026, 1, 1),
            'target_end_date': date(2026, 12, 31),
            'status': ProjectStatus.ONGOING,
        }
        defaults.update(extra)
        return Project.objects.create(code=code, name=name, **defaults)

    def join(self, project, user, role_on_project, response=RequestResponse.ACCEPTED):
        return ProjectAssignment.objects.create(
            project=project, user=user, role_on_project=role_on_project,
            response=response,
        )

    def act_as(self, user, role):
        self.client.force_authenticate(user=user)
        self.client.credentials(HTTP_X_ACTIVE_ROLE=role)

    def draft_payload(self, **overrides):
        payload = {
            'project_id': self.project.pk,
            'report_date': TODAY.isoformat(),
            'weather': 'sunny',
            'toolbox_meeting_held': True,
            'manpower': [{'trade': 'Carpentry', 'headcount': 4}],
            'materials': [{'material_id': self.material.pk, 'quantity': '12.5'}],
            'equipment': [{'equipment_id': self.equipment.pk, 'hours_used': '6'}],
            'issues': [{
                'type': 'delay', 'reason': 'rain_typhoon',
                'description': 'Rain all morning.', 'days_lost': '1',
            }],
            'photos': [],
            'todo_ids': [self.todo.pk],
        }
        payload.update(overrides)
        return payload

    def file_draft(self, user=None, **overrides):
        """POST a draft as the default engineer and return the response."""
        self.act_as(user or self.engineer, Role.SITE_ENGINEER)
        return self.client.post(
            '/api/v1/daily-reports/', self.draft_payload(**overrides), format='json',
        )

    def make_report(self, project=None, report_date=None, status='draft', author=None):
        return DailyReport.objects.create(
            project=project or self.project,
            report_date=report_date or TODAY,
            weather='sunny',
            status=status,
            submitted_by=author or self.engineer,
        )

    def make_children(self, report, caption='Slab pour'):
        """Give `report` one row of every child type, with a photo."""
        ReportManpower.objects.create(
            daily_report=report, trade='Carpentry', headcount=4,
        )
        ReportMaterialUsage.objects.create(
            daily_report=report, material=self.material, quantity='12.5',
        )
        EquipmentLog.objects.create(
            daily_report=report, equipment=self.equipment,
            project=report.project, log_date=report.report_date, hours_used='6',
        )
        Issue.objects.create(
            daily_report=report, project=report.project, type='delay',
            reason='rain_typhoon', description='Rain.', days_lost='1',
        )
        photo = ReportPhoto(daily_report=report, caption=caption)
        photo.file.save('slab.png', ContentFile(PNG_BYTES), save=True)
        photo.file_name = 'slab.png'
        photo.save(update_fields=['file_name'])
        return photo


# A one-pixel PNG (magic bytes + filler): the extension and content agree.
PNG_BYTES = b'\x89PNG\r\n\x1a\n' + b'\x00' * 32


class DailyReportDraftTests(SiteReportCase):
    def test_engineer_files_a_draft_with_every_child_and_links_the_todo(self):
        response = self.file_draft()

        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(set(response.data), REPORT_KEYS)
        self.assertEqual(response.data['status'], 'draft')
        self.assertEqual(response.data['submitted_by'], self.engineer.pk)
        self.assertEqual(response.data['report_date'], TODAY.isoformat())
        self.assertTrue(response.data['toolbox_meeting_held'])

        detail = self.client.get(f"/api/v1/daily-reports/{response.data['id']}/")
        self.assertEqual(detail.status_code, 200, detail.data)
        self.assertEqual(set(detail.data), DETAIL_KEYS)
        self.assertEqual(
            [row['trade'] for row in detail.data['manpower']], ['Carpentry'],
        )
        self.assertEqual(set(detail.data['manpower'][0]), MANPOWER_KEYS)
        self.assertEqual(set(detail.data['materials'][0]), MATERIAL_KEYS)
        self.assertEqual(set(detail.data['equipment'][0]), EQUIPMENT_KEYS)
        self.assertEqual(set(detail.data['issues'][0]), ISSUE_KEYS)
        self.assertEqual(detail.data['equipment'][0]['log_date'], TODAY.isoformat())
        self.assertEqual(
            [row['id'] for row in detail.data['todos']], [self.todo.pk],
        )
        self.assertEqual(
            detail.data['todos'][0]['daily_report_id'], response.data['id'],
        )
        self.todo.refresh_from_db()
        self.assertEqual(self.todo.daily_report_id, response.data['id'])

    def test_report_date_uses_the_server_manila_clock(self):
        """20:00 UTC is already the next day in Manila (decision 06 #11)."""
        self.assertEqual(timezone.localdate(), TODAY)
        self.assertNotEqual(NOW_UTC.date(), TODAY)  # pinned UTC day, not the host clock

        response = self.file_draft()

        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(response.data['report_date'], TODAY.isoformat())

    def test_future_date_is_refused(self):
        response = self.file_draft(
            report_date=(TODAY + timedelta(days=1)).isoformat(),
        )

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(
            response.data['detail'],
            'A daily report cannot be dated in the future.',
        )

    def test_missing_date_is_refused(self):
        response = self.file_draft(report_date=None)

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(response.data['detail'], 'Choose the report date.')

    def test_a_second_report_on_the_same_date_is_refused(self):
        self.assertEqual(self.file_draft().status_code, 201)

        response = self.file_draft()

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(
            response.data['detail'],
            'There is already a report for this project on this date.',
        )

    def test_project_must_be_ongoing(self):
        self.project.status = ProjectStatus.ACCEPTED
        self.project.save(update_fields=['status'])

        response = self.file_draft()

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(response.data['detail'], NOT_ONGOING)

    def test_only_the_assigned_site_engineer_can_file(self):
        self.act_as(self.owner, Role.OWNER)

        response = self.client.post(
            '/api/v1/daily-reports/', self.draft_payload(), format='json',
        )

        self.assertEqual(response.status_code, 403, response.data)
        self.assertEqual(response.data['detail'], NOT_THE_ENGINEER)

    def test_an_engineer_outside_the_project_gets_404(self):
        self.act_as(self.engineer, Role.SITE_ENGINEER)

        response = self.client.post(
            '/api/v1/daily-reports/',
            self.draft_payload(project_id=self.other_project.pk),
            format='json',
        )

        self.assertEqual(response.status_code, 404, response.data)

    def test_row_refusals_use_the_mock_texts(self):
        cases = (
            ({'manpower': [{'trade': 'Carpentry', 'headcount': 0}]},
             'Headcount must be greater than 0.'),
            ({'manpower': [{'trade': '  ', 'headcount': 2}]},
             'Choose a trade for each manpower row.'),
            ({'materials': [{'material_id': None, 'quantity': 1}]},
             'Choose a material from the list.'),
            ({'materials': [{'material_id': 999999, 'quantity': 1}]},
             'Choose a material from the list.'),
            ({'materials': []}, None),
            ({'equipment': [{'equipment_id': None, 'hours_used': 2}]},
             'Choose a piece of equipment from the list.'),
            ({'equipment': [{'equipment_id': 999999, 'hours_used': 2}]},
             'Choose a piece of equipment from the list.'),
            ({'issues': [{'type': 'delay', 'reason': 'rain_typhoon',
                          'description': '  ', 'days_lost': 0}]},
             'Describe each issue.'),
            ({'issues': [{'type': 'delay', 'reason': 'rain_typhoon',
                          'description': 'Rain.', 'days_lost': -1}]},
             'Days lost cannot be negative.'),
            ({'todo_ids': [self.other_todo.pk]},
             'Choose a to-do from this project.'),
            ({'todo_ids': [999999]}, 'Choose a to-do from this project.'),
        )
        for index, (overrides, expected) in enumerate(cases):
            with self.subTest(overrides=overrides):
                payload = self.draft_payload(
                    report_date=(TODAY - timedelta(days=index)).isoformat(),
                    **overrides,
                )
                self.act_as(self.engineer, Role.SITE_ENGINEER)

                response = self.client.post(
                    '/api/v1/daily-reports/', payload, format='json',
                )

                if expected is None:
                    self.assertEqual(response.status_code, 201, response.data)
                    continue
                self.assertEqual(response.status_code, 400, response.data)
                self.assertEqual(response.data['detail'], expected)

    def test_quantity_and_hours_refusals(self):
        cases = (
            ({'materials': [{'material_id': self.material.pk, 'quantity': 0}]},
             'Quantity must be greater than 0.'),
            ({'equipment': [{'equipment_id': self.equipment.pk, 'hours_used': 0}]},
             'Hours must be greater than 0.'),
            ({'equipment': [{'equipment_id': self.equipment.pk, 'hours_used': 25}]},
             'Hours cannot exceed 24 in a day.'),
        )
        for index, (overrides, expected) in enumerate(cases):
            with self.subTest(overrides=overrides):
                payload = self.draft_payload(
                    report_date=(TODAY - timedelta(days=index)).isoformat(),
                    **overrides,
                )
                self.act_as(self.engineer, Role.SITE_ENGINEER)

                response = self.client.post(
                    '/api/v1/daily-reports/', payload, format='json',
                )

                self.assertEqual(response.status_code, 400, response.data)
                self.assertEqual(response.data['detail'], expected)

    def test_an_invalid_nested_id_refuses_before_any_write(self):
        """Brief 2.2: bad nested ids must not leave a half-saved report."""
        payload = self.draft_payload(
            materials=[{'material_id': 999999, 'quantity': 1}],
        )
        self.act_as(self.engineer, Role.SITE_ENGINEER)

        response = self.client.post('/api/v1/daily-reports/', payload, format='json')

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(response.data['detail'], 'Choose a material from the list.')
        self.assertEqual(DailyReport.objects.count(), 0)
        self.assertEqual(ReportManpower.objects.count(), 0)
        self.todo.refresh_from_db()
        self.assertIsNone(self.todo.daily_report_id)

    def test_an_invalid_nested_id_on_update_keeps_the_previous_rows(self):
        created = self.file_draft()
        report_id = created.data['id']

        self.act_as(self.engineer, Role.SITE_ENGINEER)
        response = self.client.put(
            f'/api/v1/daily-reports/{report_id}/',
            self.draft_payload(
                manpower=[{'trade': 'Electrical', 'headcount': 2}],
                materials=[{'material_id': 999999, 'quantity': 1}],
            ),
            format='json',
        )

        self.assertEqual(response.status_code, 400, response.data)
        detail = self.client.get(f'/api/v1/daily-reports/{report_id}/')
        self.assertEqual(
            [row['trade'] for row in detail.data['manpower']], ['Carpentry'],
        )
        self.assertEqual(len(detail.data['materials']), 1)

    def test_a_todo_already_done_elsewhere_cannot_be_linked(self):
        self.todo.is_done = True
        self.todo.done_by = self.engineer
        self.todo.save(update_fields=['is_done', 'done_by'])
        other = self.make_report(report_date=TODAY - timedelta(days=1))
        self.todo.daily_report_id = other.pk
        self.todo.save(update_fields=['daily_report_id'])

        response = self.file_draft()

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(response.data['detail'], ALREADY_DONE)

    def test_only_the_author_can_edit_a_draft(self):
        report = self.make_report()
        self.act_as(self.engineer2, Role.SITE_ENGINEER)

        response = self.client.put(
            f'/api/v1/daily-reports/{report.pk}/',
            self.draft_payload(),
            format='json',
        )

        self.assertEqual(response.status_code, 403, response.data)
        self.assertEqual(response.data['detail'], NOT_THE_AUTHOR_EDIT)

    def test_an_author_editing_another_projects_report_gets_404(self):
        report = self.make_report(project=self.other_project, author=self.engineer)
        self.act_as(self.engineer, Role.SITE_ENGINEER)

        response = self.client.put(
            f'/api/v1/daily-reports/{report.pk}/',
            self.draft_payload(),
            format='json',
        )

        self.assertEqual(response.status_code, 404, response.data)

    def test_a_locked_report_cannot_be_edited(self):
        report = self.make_report(status='approved')
        self.act_as(self.engineer, Role.SITE_ENGINEER)

        response = self.client.put(
            f'/api/v1/daily-reports/{report.pk}/',
            self.draft_payload(),
            format='json',
        )

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(
            response.data['detail'],
            'This report is approved and can no longer be edited.',
        )

    def test_a_returned_report_is_editable_again(self):
        report = self.make_report(status='returned')
        self.act_as(self.engineer, Role.SITE_ENGINEER)

        response = self.client.put(
            f'/api/v1/daily-reports/{report.pk}/',
            self.draft_payload(),
            format='json',
        )

        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data['status'], 'returned')

    def test_server_owned_keys_cannot_be_set_through_the_body(self):
        payload = self.draft_payload(
            status='approved', submitted_by=self.owner.pk,
            reviewed_by=self.owner.pk, id=9999,
        )
        self.act_as(self.engineer, Role.SITE_ENGINEER)

        response = self.client.post('/api/v1/daily-reports/', payload, format='json')

        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(response.data['status'], 'draft')
        self.assertEqual(response.data['submitted_by'], self.engineer.pk)
        self.assertIsNone(response.data['reviewed_by'])
        self.assertNotEqual(response.data['id'], 9999)

    def test_unlinking_a_todo_clears_the_link(self):
        created = self.file_draft()
        self.act_as(self.engineer, Role.SITE_ENGINEER)

        response = self.client.put(
            f"/api/v1/daily-reports/{created.data['id']}/",
            self.draft_payload(todo_ids=[]),
            format='json',
        )

        self.assertEqual(response.status_code, 200, response.data)
        self.todo.refresh_from_db()
        self.assertIsNone(self.todo.daily_report_id)


class DailyReportListTests(SiteReportCase):
    def test_list_is_newest_first_and_filters(self):
        older = self.make_report(report_date=TODAY - timedelta(days=2))
        newer = self.make_report(report_date=TODAY)
        self.make_report(
            project=self.other_project, report_date=TODAY, status='submitted',
        )
        self.act_as(self.owner, Role.OWNER)

        response = self.client.get(
            f'/api/v1/daily-reports/?project={self.project.pk},{self.other_project.pk}',
        )

        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual([row['id'] for row in response.data], [newer.pk, older.pk])
        self.assertEqual(set(response.data[0]), REPORT_KEYS)

    def test_out_of_scope_project_ids_are_dropped_silently(self):
        mine = self.make_report()
        self.make_report(project=self.other_project)
        self.act_as(self.engineer, Role.SITE_ENGINEER)

        response = self.client.get(
            f'/api/v1/daily-reports/?project={self.other_project.pk}',
        )

        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data, [])
        self.assertEqual(
            [row['id'] for row in self.client.get('/api/v1/daily-reports/').data],
            [mine.pk],
        )

    def test_status_and_date_filters(self):
        self.make_report(report_date=TODAY - timedelta(days=3))
        submitted = self.make_report(report_date=TODAY, status='submitted')
        self.act_as(self.owner, Role.OWNER)

        by_status = self.client.get('/api/v1/daily-reports/?status=submitted')
        by_date = self.client.get(
            f'/api/v1/daily-reports/?from={TODAY.isoformat()}'
            f'&to={TODAY.isoformat()}',
        )

        self.assertEqual([row['id'] for row in by_status.data], [submitted.pk])
        self.assertEqual([row['id'] for row in by_date.data], [submitted.pk])

    def test_a_junk_filter_is_a_400_not_a_500(self):
        self.act_as(self.owner, Role.OWNER)

        self.assertEqual(
            self.client.get('/api/v1/daily-reports/?project=abc').status_code, 400,
        )
        self.assertEqual(
            self.client.get('/api/v1/daily-reports/?status=nope').status_code, 400,
        )
        self.assertEqual(
            self.client.get('/api/v1/daily-reports/?from=nope').status_code, 400,
        )

    def test_client_cannot_read_the_site_reports(self):
        report = self.make_report()
        self.act_as(self.client_user, Role.CLIENT)

        listing = self.client.get('/api/v1/daily-reports/')
        detail = self.client.get(f'/api/v1/daily-reports/{report.pk}/')

        self.assertEqual(listing.status_code, 403, listing.data)
        self.assertEqual(listing.data['detail'], REPORTS_STAFF_ONLY)
        self.assertEqual(detail.status_code, 403, detail.data)

    def test_another_projects_report_detail_is_404(self):
        report = self.make_report(project=self.other_project)
        self.act_as(self.owner, Role.OWNER)

        response = self.client.get(f'/api/v1/daily-reports/{report.pk}/')

        self.assertEqual(response.status_code, 404, response.data)


class DailyReportWorkflowTests(SiteReportCase):
    def test_submit_marks_linked_todos_done_and_notifies_the_owners(self):
        report = self.make_report()
        self.todo.daily_report_id = report.pk
        self.todo.save(update_fields=['daily_report_id'])
        self.act_as(self.engineer, Role.SITE_ENGINEER)

        response = self.client.post(f'/api/v1/daily-reports/{report.pk}/submit/')

        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data['status'], 'submitted')
        self.todo.refresh_from_db()
        self.assertTrue(self.todo.is_done)
        self.assertTrue(
            AuditLog.objects.filter(
                action='daily_report_submitted',
                entity='daily_report',
                entity_id=report.pk,
            ).exists()
        )
        self.assertTrue(
            AuditLog.objects.filter(action='todo_marked_done', entity_id=self.todo.pk).exists()
        )
        note = Notification.objects.get(user=self.owner, type='report_submitted')
        self.assertEqual(
            note.message,
            f'Daily report for PRJ-A on {TODAY.isoformat()} is waiting for your approval.',
        )

    def test_submit_refusals(self):
        draft = self.make_report()
        self.act_as(self.engineer2, Role.SITE_ENGINEER)
        not_author = self.client.post(f'/api/v1/daily-reports/{draft.pk}/submit/')
        self.assertEqual(not_author.status_code, 403, not_author.data)
        self.assertEqual(not_author.data['detail'], NOT_THE_AUTHOR_SUBMIT)

        approved = self.make_report(
            report_date=TODAY - timedelta(days=1), status='approved',
        )
        self.act_as(self.engineer, Role.SITE_ENGINEER)
        locked = self.client.post(f'/api/v1/daily-reports/{approved.pk}/submit/')
        self.assertEqual(locked.status_code, 400, locked.data)
        self.assertEqual(
            locked.data['detail'],
            'Only draft or returned reports can be submitted.',
        )

    def test_approve_verifies_the_todos_and_notifies_the_author(self):
        report = self.make_report(status='submitted')
        self.todo.daily_report_id = report.pk
        self.todo.is_done = True
        self.todo.done_by = self.engineer
        self.todo.save(update_fields=['daily_report_id', 'is_done', 'done_by'])
        self.act_as(self.owner, Role.OWNER)

        response = self.client.post(f'/api/v1/daily-reports/{report.pk}/approve/')

        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data['status'], 'approved')
        self.assertEqual(response.data['reviewed_by'], self.owner.pk)
        self.todo.refresh_from_db()
        self.assertTrue(self.todo.is_verified)
        self.assertEqual(self.todo.verified_by_id, self.owner.pk)
        self.assertTrue(
            AuditLog.objects.filter(action='todo_verified', entity_id=self.todo.pk).exists()
        )
        self.assertTrue(
            AuditLog.objects.filter(
                action='daily_report_approved', entity_id=report.pk,
            ).exists()
        )
        note = Notification.objects.get(user=self.engineer, type='report_approved')
        self.assertEqual(
            note.message,
            f'Your daily report for {TODAY.isoformat()} was approved.',
        )

    def test_approve_refusals(self):
        draft = self.make_report()
        self.act_as(self.owner, Role.OWNER)
        not_submitted = self.client.post(f'/api/v1/daily-reports/{draft.pk}/approve/')
        self.assertEqual(not_submitted.status_code, 400, not_submitted.data)
        self.assertEqual(
            not_submitted.data['detail'],
            'Only submitted reports can be approved or returned.',
        )

        submitted = self.make_report(
            report_date=TODAY - timedelta(days=1), status='submitted',
        )
        self.act_as(self.engineer2, Role.SITE_ENGINEER)
        not_owner = self.client.post(f'/api/v1/daily-reports/{submitted.pk}/approve/')
        self.assertEqual(not_owner.status_code, 403, not_owner.data)
        self.assertEqual(not_owner.data['detail'], NOT_THE_OWNER_REVIEW)

        self.act_as(self.other_owner, Role.OWNER)
        self.assertEqual(
            self.client.post(f'/api/v1/daily-reports/{submitted.pk}/approve/').status_code,
            404,
        )

        self.act_as(self.owner, Role.OWNER)
        self.assertEqual(
            self.client.post(f'/api/v1/daily-reports/{submitted.pk}/approve/').status_code,
            200,
        )

    def test_return_requires_remarks_and_records_them(self):
        report = self.make_report(status='submitted')
        self.act_as(self.owner, Role.OWNER)

        blank = self.client.post(
            f'/api/v1/daily-reports/{report.pk}/return/', {'remarks': '  '},
            format='json',
        )
        self.assertEqual(blank.status_code, 400, blank.data)
        self.assertEqual(
            blank.data['detail'],
            'Add remarks so the site engineer knows what to fix.',
        )

        response = self.client.post(
            f'/api/v1/daily-reports/{report.pk}/return/',
            {'remarks': ' Attach the delivery receipt.'},
            format='json',
        )
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data['status'], 'returned')
        self.assertEqual(response.data['remarks'], 'Attach the delivery receipt.')
        self.assertTrue(
            AuditLog.objects.filter(
                action='daily_report_returned', entity_id=report.pk,
            ).exists()
        )
        self.assertEqual(
            Notification.objects.get(user=self.engineer).message,
            f'Your daily report for {TODAY.isoformat()} was returned: '
            'Attach the delivery receipt.',
        )

    def test_admin_and_accountant_cannot_review_reports(self):
        report = self.make_report(status='submitted')
        for user, role in ((self.admin, Role.ADMIN), (self.accountant, Role.ACCOUNTANT)):
            self.act_as(user, role)

            response = self.client.post(f'/api/v1/daily-reports/{report.pk}/approve/')

            self.assertEqual(response.status_code, 403, response.data)
            self.assertEqual(response.data['detail'], NOT_THE_OWNER_REVIEW)

    def test_client_cannot_write_a_report_or_review_it(self):
        report = self.make_report(status='submitted')
        self.act_as(self.client_user, Role.CLIENT)

        created = self.client.post(
            '/api/v1/daily-reports/', self.draft_payload(), format='json',
        )
        approved = self.client.post(f'/api/v1/daily-reports/{report.pk}/approve/')

        self.assertEqual(created.status_code, 403, created.data)
        self.assertIn(approved.status_code, (403, 404), approved.data)
        self.assertEqual(DailyReport.objects.count(), 1)


class ApprovedSiteDataTests(SiteReportCase):
    def test_approved_usage_and_equipment_come_only_from_approved_reports(self):
        approved = self.make_report(report_date=TODAY, status='approved')
        self.make_children(approved)
        draft = self.make_report(report_date=TODAY - timedelta(days=1))
        self.make_children(draft)
        self.act_as(self.owner, Role.OWNER)

        usage = self.client.get(
            f'/api/v1/projects/{self.project.pk}/approved-material-usage/',
        )
        equipment = self.client.get(
            f'/api/v1/projects/{self.project.pk}/approved-equipment-logs/',
        )

        self.assertEqual(usage.status_code, 200, usage.data)
        self.assertEqual(len(usage.data), 1)
        self.assertEqual(set(usage.data[0]), MATERIAL_KEYS)
        self.assertEqual(usage.data[0]['daily_report_id'], approved.pk)
        self.assertEqual(equipment.status_code, 200, equipment.data)
        self.assertEqual(len(equipment.data), 1)
        self.assertEqual(set(equipment.data[0]), EQUIPMENT_KEYS)
        self.assertEqual(equipment.data[0]['daily_report_id'], approved.pk)

    def test_approved_lists_are_project_scoped(self):
        self.make_children(self.make_report(status='approved'))
        self.act_as(self.owner, Role.OWNER)

        response = self.client.get(
            f'/api/v1/projects/{self.other_project.pk}/approved-material-usage/',
        )

        self.assertEqual(response.status_code, 404, response.data)

    def test_approved_photos_reach_the_client_for_approved_reports_only(self):
        approved = self.make_report(report_date=TODAY, status='approved')
        approved_photo = self.make_children(approved)
        draft = self.make_report(report_date=TODAY - timedelta(days=1))
        self.make_children(draft)
        self.act_as(self.client_user, Role.CLIENT)

        response = self.client.get(
            f'/api/v1/report-photos/approved/?project={self.project.pk}',
        )

        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(len(response.data), 1)
        self.assertEqual(set(response.data[0]), {'photo', 'report'})
        self.assertEqual(set(response.data[0]['photo']), PHOTO_KEYS)
        self.assertEqual(response.data[0]['photo']['id'], approved_photo.pk)
        self.assertEqual(response.data[0]['report']['id'], approved.pk)

    def test_approved_photos_are_newest_first_and_scoped(self):
        older = self.make_report(report_date=TODAY - timedelta(days=5), status='approved')
        newer = self.make_report(report_date=TODAY, status='approved')
        self.make_children(older)
        self.make_children(newer)
        hidden = self.make_report(
            project=self.other_project, report_date=TODAY, status='approved',
        )
        self.make_children(hidden)
        self.act_as(self.engineer, Role.SITE_ENGINEER)

        response = self.client.get('/api/v1/report-photos/approved/')

        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(
            [row['report']['id'] for row in response.data], [newer.pk, older.pk],
        )

    def test_photos_with_and_without_taken_at_sort_together(self):
        report = self.make_report(status='approved')
        self.make_children(report, caption='no timestamp')
        timed = self.make_children(report, caption='timestamped')
        timed.taken_at = datetime(2026, 11, 15, 9, 0, tzinfo=UTC)
        timed.save(update_fields=['taken_at'])
        self.act_as(self.owner, Role.OWNER)

        response = self.client.get(
            f'/api/v1/report-photos/approved/?project={self.project.pk}',
        )

        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(
            [row['photo']['id'] for row in response.data],
            [timed.pk, response.data[1]['photo']['id']],
        )
        self.assertEqual(response.data[0]['photo']['caption'], 'timestamped')

    def test_approved_photos_outside_the_project_get_404(self):
        self.act_as(self.engineer, Role.SITE_ENGINEER)

        response = self.client.get(
            f'/api/v1/report-photos/approved/?project={self.other_project.pk}',
        )

        self.assertEqual(response.status_code, 404, response.data)


class NonFiniteDecimalTests(SiteReportCase):
    """Review 2.2 blocker 2: `NaN`/`Infinity` are refused, never written.

    Python's `json.loads` (DRF's JSONParser) accepts the literals `NaN`,
    `Infinity` and `-Infinity`, so a draft can carry a non-finite number that
    `Decimal` parses fine but that raises `InvalidOperation` on the first
    comparison. Every numeric row must refuse it as the contract's `400`.
    """

    def post_raw(self, body):
        self.act_as(self.engineer, Role.SITE_ENGINEER)
        return self.client.post(
            '/api/v1/daily-reports/', body, content_type='application/json',
        )

    def test_as_decimal_refuses_every_non_finite_form(self):
        from . import rules

        for value in (
            'NaN', 'sNaN', 'Infinity', '-Infinity', 'inf', '-inf', 'nan',
            float('nan'), float('inf'), float('-inf'),
        ):
            with self.subTest(value=value):
                self.assertIsNone(rules.as_decimal(value))

        for value in ('12.5', 12.5, 0, '0'):
            with self.subTest(finite=value):
                self.assertIsNotNone(rules.as_decimal(value))

    def test_a_non_finite_number_in_any_row_is_a_400_and_writes_nothing(self):
        cases = (
            ({'materials': [{'material_id': self.material.pk, 'quantity': 'NaN'}]},
             'Quantity must be greater than 0.'),
            ({'materials': [{'material_id': self.material.pk, 'quantity': 'Infinity'}]},
             'Quantity must be greater than 0.'),
            ({'equipment': [{'equipment_id': self.equipment.pk, 'hours_used': 'NaN'}]},
             'Hours must be greater than 0.'),
            ({'equipment': [{'equipment_id': self.equipment.pk, 'hours_used': 'Infinity'}]},
             'Hours must be greater than 0.'),
            ({'issues': [{'type': 'delay', 'reason': 'rain_typhoon',
                          'description': 'Rain.', 'days_lost': '-Infinity'}]},
             'Days lost cannot be negative.'),
        )
        for index, (overrides, expected) in enumerate(cases):
            with self.subTest(overrides=overrides):
                payload = self.draft_payload(
                    report_date=(TODAY - timedelta(days=index)).isoformat(),
                    **overrides,
                )
                self.act_as(self.engineer, Role.SITE_ENGINEER)

                response = self.client.post(
                    '/api/v1/daily-reports/', payload, format='json',
                )

                self.assertEqual(response.status_code, 400, response.data)
                self.assertEqual(response.data['detail'], expected)

    def test_json_nan_and_infinity_literals_are_a_400_not_a_500(self):
        """The parser accepts the bare literals; the server must still refuse."""
        body = (
            '{"project_id": %d, "report_date": "%s", "weather": "sunny",'
            ' "materials": [{"material_id": %d, "quantity": NaN}],'
            ' "equipment": [{"equipment_id": %d, "hours_used": Infinity}]}'
            % (
                self.project.pk, TODAY.isoformat(), self.material.pk,
                self.equipment.pk,
            )
        )

        response = self.post_raw(body)

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(DailyReport.objects.count(), 0)
        self.assertEqual(ReportMaterialUsage.objects.count(), 0)
        self.assertEqual(EquipmentLog.objects.count(), 0)

    def test_a_non_finite_latitude_on_a_kept_photo_is_dropped_not_stored(self):
        report = self.make_report(status='draft')
        photo = self.make_children(report)
        self.act_as(self.engineer, Role.SITE_ENGINEER)

        response = self.client.put(
            f'/api/v1/daily-reports/{report.pk}/',
            {
                'report_date': report.report_date.isoformat(),
                'weather': 'sunny',
                'photos': [{'id': photo.pk, 'latitude': 'NaN',
                            'longitude': 'Infinity'}],
            },
            format='json',
        )

        self.assertEqual(response.status_code, 200, response.data)
        photo.refresh_from_db()
        self.assertIsNone(photo.latitude)
        self.assertIsNone(photo.longitude)


class ReportFilingActiveRoleTests(SiteReportCase):
    """Review 2.2 warning: filing follows the **active** role (security check 4).

    The demo partner account holds `owner` + `site_engineer`; acting as `owner`
    must not buy site-engineer rights. Switching to `site_engineer` must work.
    """

    def setUp(self):
        super().setUp()
        self.both = make_user('partner@example.com', [Role.OWNER, Role.SITE_ENGINEER])
        self.join(self.project, self.both, RoleOnProject.OWNER)
        self.join(self.project, self.both, RoleOnProject.SITE_ENGINEER)

    def test_filing_as_owner_is_refused_even_when_the_engineer_role_is_held(self):
        self.act_as(self.both, Role.OWNER)

        response = self.client.post(
            '/api/v1/daily-reports/', self.draft_payload(), format='json',
        )

        self.assertEqual(response.status_code, 403, response.data)
        self.assertEqual(response.data['detail'], NOT_THE_ENGINEER)
        self.assertEqual(DailyReport.objects.count(), 0)

    def test_switching_to_the_site_engineer_role_files_the_draft(self):
        self.act_as(self.both, Role.SITE_ENGINEER)

        response = self.client.post(
            '/api/v1/daily-reports/', self.draft_payload(), format='json',
        )

        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(response.data['submitted_by'], self.both.pk)

    def test_editing_and_submitting_as_owner_is_refused(self):
        report = self.make_report(author=self.both)
        self.act_as(self.both, Role.OWNER)

        edit = self.client.put(
            f'/api/v1/daily-reports/{report.pk}/',
            self.draft_payload(),
            format='json',
        )
        submit = self.client.post(f'/api/v1/daily-reports/{report.pk}/submit/')

        self.assertEqual(edit.status_code, 403, edit.data)
        self.assertEqual(edit.data['detail'], NOT_THE_AUTHOR_EDIT)
        self.assertEqual(submit.status_code, 403, submit.data)
        self.assertEqual(submit.data['detail'], NOT_THE_AUTHOR_SUBMIT)
        report.refresh_from_db()
        self.assertEqual(report.status, 'draft')

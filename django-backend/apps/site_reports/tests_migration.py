"""Migration 0006 regression: no legacy to-do report id is lost.

Phase 2.1 shipped `Todo.daily_report_id` as a bare integer. 2.2 turns it into a
real FK, and a plain `makemigrations` would have dropped the column (and every
value in it). This test populates the pre-0006 schema with three to-dos — one
pointing at a real report, one at an id that matches nothing, one with no value
— migrates forward, and asserts the FK is live and the unmatched value survived
in `legacy_daily_report_id` instead of being silently dropped.

`TransactionTestCase` because migrations must run outside a transaction.
"""

# Pyright here runs without django-stubs, so historical model managers are untyped.
# pyright: reportAttributeAccessIssue=false, reportArgumentType=false

from datetime import date

from django.db import connection
from django.db.migrations.executor import MigrationExecutor
from django.test import TransactionTestCase

from ..projects.models import Todo
from ..users.models import Role
from ..users.tests import make_user
from .models import DailyReport

# The last schema before the FK conversion (0006 depends on site_reports.0001).
PRE_FK = [
    ('apps_projects', '0005_legacy_project_data'),
    ('apps_site_reports', '0001_initial'),
]

ORPHAN_ID = 999999


class TodoDailyReportForeignKeyTests(TransactionTestCase):
    """The integer becomes an FK without dropping the values it held."""

    # Data migrations (the company seed) must still be there for later suites.
    serialized_rollback = True

    def setUp(self):
        executor = MigrationExecutor(connection)
        executor.migrate(PRE_FK)
        old = executor.loader.project_state(PRE_FK).apps

        OldProject = old.get_model('apps_projects', 'Project')
        OldCategory = old.get_model('apps_projects', 'Category')
        OldTodo = old.get_model('apps_projects', 'Todo')
        OldReport = old.get_model('apps_site_reports', 'DailyReport')

        self.author = make_user('legacy.engineer@example.com', [Role.SITE_ENGINEER])
        project = OldProject.objects.create(code='PRJ-FK', name='FK migration job')
        category = OldCategory.objects.create(project=project, name='Siteworks')
        report = OldReport.objects.create(
            project=project,
            report_date=date(2026, 11, 10),
            weather='sunny',
            status='submitted',
            submitted_by_id=self.author.pk,
        )

        self.report_id = report.pk
        self.todo_ids = {
            'linked': OldTodo.objects.create(
                category=category, title='Linked', start_date=date(2026, 11, 1),
                end_date=date(2026, 11, 2), daily_report_id=report.pk,
            ).pk,
            'orphan': OldTodo.objects.create(
                category=category, title='Orphan', start_date=date(2026, 11, 1),
                end_date=date(2026, 11, 2), daily_report_id=ORPHAN_ID,
            ).pk,
            'empty': OldTodo.objects.create(
                category=category, title='Empty', start_date=date(2026, 11, 1),
                end_date=date(2026, 11, 2), daily_report_id=None,
            ).pk,
        }

        MigrationExecutor(connection).migrate(
            executor.loader.graph.leaf_nodes(),
        )

    def todo(self, key):
        return Todo.objects.get(pk=self.todo_ids[key])

    def test_the_column_is_a_real_foreign_key_now(self):
        todo = self.todo('linked')

        self.assertEqual(todo.daily_report_id, self.report_id)
        self.assertEqual(todo.daily_report, DailyReport.objects.get(pk=self.report_id))
        self.assertIsNone(todo.legacy_daily_report_id)

    def test_an_id_that_matched_no_report_is_preserved_not_dropped(self):
        todo = self.todo('orphan')

        self.assertIsNone(todo.daily_report_id)
        self.assertEqual(todo.legacy_daily_report_id, ORPHAN_ID)

    def test_an_empty_value_stays_empty(self):
        todo = self.todo('empty')

        self.assertIsNone(todo.daily_report_id)
        self.assertIsNone(todo.legacy_daily_report_id)

    def test_no_to_do_row_was_lost(self):
        self.assertEqual(Todo.objects.count(), 3)

    def test_deleting_the_report_nulls_the_link_instead_of_the_to_do(self):
        DailyReport.objects.get(pk=self.report_id).delete()

        todo = self.todo('linked')

        self.assertIsNone(todo.daily_report_id)
        self.assertEqual(Todo.objects.count(), 3)

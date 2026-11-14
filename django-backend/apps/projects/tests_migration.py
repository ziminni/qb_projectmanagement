"""Migration 0004/0005 regression: legacy project data must survive.

Review 2.1 blocker: `0004` used to drop `Contract`, `ProjectPhase`,
`Milestone` and three `Project` columns without copying anything. The migration
is now additive and `0005` folds only the values whose meaning is provable,
keeping every original row and column. This test populates the pre-0004 schema,
migrates forward, and asserts the legacy records are all still there.

Named `tests_migration` (starts with `test`) so Django's default discovery finds
it; `TransactionTestCase` because migrations must run outside a transaction.
"""

# Pyright here runs without django-stubs, so historical model managers are untyped.
# pyright: reportAttributeAccessIssue=false, reportArgumentType=false

from datetime import date
from decimal import Decimal

from django.db import connection
from django.db.migrations.executor import MigrationExecutor
from django.test import TransactionTestCase

from ..company.models import Company
from ..users.models import Role, User
from .models import (
    Category,
    Client,
    Contract,
    Milestone,
    Project,
    ProjectAssignment,
    ProjectPhase,
    Site,
    Todo,
)

LEGACY = [('apps_projects', '0003_alter_project_manager')]
# The real leaf after 2.2's FK conversion; keeping the suite at the latest
# schema stops this test from leaving the database at an older migration.
LATEST = [('apps_projects', '0006_todo_daily_report_fk')]
# Demo-only password for the legacy manager row in this suite.
DEMO_PASSWORD = 's3cret-pass-123'  # noqa: S105 - test fixture, not a credential


class LegacyProjectDataPreservationTests(TransactionTestCase):
    """Every legacy row and column survives the 0004/0005 migration."""

    # Data migrations (the company seed) must still be there for later suites.
    serialized_rollback = True

    def setUp(self):
        executor = MigrationExecutor(connection)
        executor.migrate(LEGACY)
        old = executor.loader.project_state(LEGACY).apps

        OldSite = old.get_model('apps_projects', 'Site')
        OldProject = old.get_model('apps_projects', 'Project')
        OldContract = old.get_model('apps_projects', 'Contract')
        OldPhase = old.get_model('apps_projects', 'ProjectPhase')
        OldMilestone = old.get_model('apps_projects', 'Milestone')

        company = Company.objects.first()
        self.manager = User.objects.create_user(
            email='legacy.manager@example.com', password=DEMO_PASSWORD,
            full_name='Legacy Manager', company=company, roles=[Role.OWNER],
        )

        site = OldSite.objects.create(code='SITE-L', name='Legacy Site')
        self.legacy_ids = {}

        self.legacy_ids['single'] = OldProject.objects.create(
            code='PRJ-SINGLE', name='Single Contract', site=site,
            status='IN_PROGRESS', budget_amount=Decimal('1500000.00'),
            description='Legacy description kept.', manager_id=self.manager.pk,
            start_date=date(2025, 1, 6), target_end_date=date(2025, 12, 1),
        ).pk
        self.legacy_ids['planning'] = OldProject.objects.create(
            code='PRJ-PLANNING', name='Planned Only', site=site,
            status='PLANNING', budget_amount=Decimal('0.00'),
        ).pk
        self.legacy_ids['cancelled'] = OldProject.objects.create(
            code='PRJ-CANCELLED', name='Cancelled Job', site=site,
            status='CANCELLED',
        ).pk
        self.legacy_ids['conflict'] = OldProject.objects.create(
            code='PRJ-CONFLICT', name='Two Contracts', site=site,
            status='SUSPENDED', budget_amount=Decimal('750000.00'),
        ).pk
        self.legacy_ids['completed'] = OldProject.objects.create(
            code='PRJ-DONE', name='Completed Job', site=site,
            status='COMPLETED', actual_end_date=date(2025, 11, 20),
        ).pk

        OldContract.objects.create(
            project_id=self.legacy_ids['single'], contract_no='CT-LEG-1',
            client_name='Acme Holdings', client_contact='Elena Cruz',
            amount=Decimal('2000000.00'), retention_percent=Decimal('5.00'),
            signed_date=date(2025, 1, 3), status='ACTIVE', notes='Legacy notes.',
        )
        for contract_no, amount in (('CT-LEG-2', '900000.00'), ('CT-LEG-3', '300000.00')):
            OldContract.objects.create(
                project_id=self.legacy_ids['conflict'], contract_no=contract_no,
                client_name=f'{contract_no} Client', amount=Decimal(amount),
            )

        phase = OldPhase.objects.create(
            project_id=self.legacy_ids['single'], name='Siteworks', sequence=1,
            status='IN_PROGRESS', progress_percent=Decimal('40.00'),
            planned_start=date(2025, 1, 6), planned_end=date(2025, 5, 30),
        )
        OldMilestone.objects.create(
            project_id=self.legacy_ids['single'], phase=phase, title='Slab poured',
            due_date=date(2025, 3, 15), notes='Legacy milestone.',
        )

        self.contract_count = OldContract.objects.count()
        self.phase_count = OldPhase.objects.count()
        self.milestone_count = OldMilestone.objects.count()

        executor = MigrationExecutor(connection)
        executor.migrate(LATEST)

    def project(self, key):
        return Project.objects.get(pk=self.legacy_ids[key])

    def test_every_legacy_row_is_still_there(self):
        self.assertEqual(Project.objects.count(), 5)
        self.assertEqual(Contract.objects.count(), self.contract_count)
        self.assertEqual(ProjectPhase.objects.count(), self.phase_count)
        self.assertEqual(Milestone.objects.count(), self.milestone_count)
        self.assertEqual(Site.objects.filter(code='SITE-L').count(), 1)

    def test_the_deleted_project_columns_are_all_preserved(self):
        project = self.project('single')

        self.assertEqual(project.budget_amount, Decimal('1500000.00'))
        self.assertEqual(project.description, 'Legacy description kept.')
        self.assertEqual(project.manager_id, self.manager.pk)

    def test_the_legacy_contract_columns_and_rows_are_untouched(self):
        contract = Contract.objects.get(contract_no='CT-LEG-1')

        self.assertEqual(contract.project_id, self.legacy_ids['single'])
        self.assertEqual(contract.amount, Decimal('2000000.00'))
        self.assertEqual(contract.retention_percent, Decimal('5.00'))
        self.assertEqual(contract.client_name, 'Acme Holdings')
        self.assertEqual(contract.client_contact, 'Elena Cruz')
        self.assertEqual(contract.notes, 'Legacy notes.')
        self.assertEqual(contract.status, 'ACTIVE')

    def test_phases_and_milestones_keep_their_rows_and_values(self):
        phase = ProjectPhase.objects.get(project_id=self.legacy_ids['single'])
        milestone = Milestone.objects.get(title='Slab poured')

        self.assertEqual(phase.name, 'Siteworks')
        self.assertEqual(phase.progress_percent, Decimal('40.00'))
        self.assertEqual(phase.status, 'IN_PROGRESS')
        self.assertEqual(milestone.phase_id, phase.pk)
        self.assertEqual(milestone.due_date, date(2025, 3, 15))
        self.assertEqual(milestone.notes, 'Legacy milestone.')

    def test_legacy_status_codes_are_preserved_and_remapped(self):
        expected = {
            'single': ('ongoing', 'IN_PROGRESS'),
            'planning': ('accepted', 'PLANNING'),
            'cancelled': ('closed', 'CANCELLED'),
            'conflict': ('on_hold', 'SUSPENDED'),
            'completed': ('completed', 'COMPLETED'),
        }
        for key, (new_status, legacy_status) in expected.items():
            project = self.project(key)
            self.assertEqual(project.status, new_status, key)
            self.assertEqual(project.legacy_status, legacy_status, key)

    def test_a_single_contract_is_folded_into_the_project(self):
        project = self.project('single')
        client = Client.objects.get(pk=project.client_id)

        self.assertEqual(project.contract_amount, Decimal('2000000.00'))
        self.assertEqual(project.retention_pct, Decimal('5.00'))
        self.assertEqual(client.name, 'Acme Holdings')
        self.assertEqual(client.contact_person, 'Elena Cruz')
        self.assertEqual(project.start_date, date(2025, 1, 6))

    def test_conflicting_contracts_are_left_alone_not_guessed(self):
        project = self.project('conflict')

        self.assertEqual(project.contract_amount, Decimal('0.00'))
        self.assertEqual(project.retention_pct, Decimal('0.00'))
        self.assertIsNone(project.client_id)
        self.assertEqual(
            sorted(
                Contract.objects.filter(
                    project_id=self.legacy_ids['conflict'],
                ).values_list('amount', flat=True)
            ),
            [Decimal('300000.00'), Decimal('900000.00')],
        )

    def test_the_legacy_manager_becomes_the_project_owner(self):
        assignment = ProjectAssignment.objects.get(
            project_id=self.legacy_ids['single'],
            user=self.manager,
            role_on_project='owner',
        )

        self.assertEqual(assignment.response, 'accepted')

    def test_no_category_or_todo_invents_data_it_cannot_prove(self):
        # A phase/milestone has no provable Category/Todo equivalent (decision 05).
        self.assertEqual(Category.objects.count(), 0)
        self.assertEqual(Todo.objects.count(), 0)

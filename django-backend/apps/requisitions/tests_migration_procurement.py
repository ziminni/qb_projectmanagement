"""Migration 0004 regression: the legacy requisition rows are preserved.

Phase 3 extends the pre-existing requisition tables additively (the rule Phase
2's 0004/0005 set). The risk this test guards is the *mapping*: legacy rows must
keep every column and get the documented status translation, with the raw code
kept in `legacy_status`.

Why this replays `forwards()` instead of driving `MigrationExecutor`: three
`TransactionTestCase`s that each roll the schema backwards and forwards cannot
coexist in one run — a rollback of `apps_projects` unapplies every dependent
migration and the next class restores stale rows (`duplicate key ...
django_content_type`), which was reproduced here. The mapping function is the
mutable part; the schema is proven by `makemigrations --check` (no drift) and by
every other test in this app touching the new tables.

    DRAFT/PENDING/APPROVED/PARTIALLY_APPROVED -> pending
    REJECTED/CANCELLED                        -> rejected
    RELEASED                                  -> ordered
"""

# Pyright here runs without django-stubs, so model managers are untyped.
# pyright: reportAttributeAccessIssue=false

from datetime import date
from decimal import Decimal

from django.apps import apps as global_apps
from django.test import TestCase
from django.utils import timezone

from ..company.models import Company
from ..projects.models import Project, ProjectStatus, Site
from ..users.models import Role, User
from .models import MaterialRequest, MaterialRequestItem, ReleaseToken

DEMO_PASSWORD = 's3cret-pass-123'  # noqa: S105 - test fixture, not a credential


class LegacyRequisitionDataPreservationTests(TestCase):
    def setUp(self):
        if not Company.objects.exists():
            Company.objects.create(name='BuildPro Test')
        self.engineer = User.objects.create_user(
            email='legacy.engineer@example.com', password=DEMO_PASSWORD,
            full_name='Legacy Engineer', company=Company.objects.first(),
            roles=[Role.SITE_ENGINEER],
        )
        self.manager = User.objects.create_user(
            email='legacy.pm@example.com', password=DEMO_PASSWORD,
            full_name='Legacy Manager', company=Company.objects.first(),
            roles=[Role.OWNER],
        )
        self.site = Site.objects.create(code='SITE-R', name='Requisition Site')
        self.project = Project.objects.create(
            code='PRJ-REQ', name='Legacy Requisition Job',
            site=self.site, status=ProjectStatus.ONGOING,
            start_date=date(2025, 1, 6), target_end_date=date(2025, 12, 1),
        )

        self.legacy_ids = {}
        for legacy in ('DRAFT', 'PENDING', 'APPROVED', 'REJECTED', 'RELEASED', 'CANCELLED'):
            row = MaterialRequest.objects.create(
                request_no=f'REQ-{legacy}',
                project=self.project,
                site=self.site,
                requested_by=self.engineer,
                # A pre-Phase-3 row: the old code, written before `status` had
                # the Phase 3 choices (choices are not enforced in the DB).
                status=legacy,
                needed_date=date(2025, 2, 1),
                reviewed_by=self.manager,
                rejection_reason='Legacy reason.' if legacy == 'REJECTED' else '',
            )
            self.legacy_ids[legacy] = row.pk
            MaterialRequestItem.objects.create(
                material_request=row, item_sku='CEM-40KG',
                description='Cement', unit='bag',
                quantity_requested=Decimal('10.00'),
                quantity_approved=Decimal('8.00'),
                quantity_released=Decimal('6.00'),
                unit_cost=Decimal('250.00'),
            )

        ReleaseToken.objects.create(
            material_request_id=self.legacy_ids['RELEASED'],
            # A release-token code, not a credential: the legacy bearer
            # secret this build retires from the API.
            token='LEGACYTOKEN0001',  # noqa: S105
            issued_at=timezone.now(),
            expires_at=timezone.now(),
            status='REDEEMED',
            pos_reference='POS-LEG-1',
        )

        # The migration's own code path, run against these rows.
        migration = __import__(
            'apps.requisitions.migrations.0004_legacy_procurement_data',
            fromlist=['forwards'],
        )
        migration.forwards(global_apps, None)

    def test_every_legacy_request_and_item_survives(self):
        self.assertEqual(MaterialRequest.objects.count(), 6)
        self.assertEqual(MaterialRequestItem.objects.count(), 6)
        self.assertEqual(ReleaseToken.objects.count(), 1)

    def test_the_legacy_columns_are_all_preserved(self):
        row = MaterialRequest.objects.get(pk=self.legacy_ids['APPROVED'])
        item = row.items.get()

        self.assertEqual(row.request_no, 'REQ-APPROVED')
        self.assertEqual(row.priority, 'NORMAL')
        self.assertEqual(row.needed_date, date(2025, 2, 1))
        self.assertEqual(row.reviewed_by_id, self.manager.pk)
        self.assertEqual(item.item_sku, 'CEM-40KG')
        self.assertEqual(item.quantity_requested, Decimal('10.00'))
        self.assertEqual(item.quantity_approved, Decimal('8.00'))
        self.assertEqual(item.quantity_released, Decimal('6.00'))
        self.assertEqual(item.unit_cost, Decimal('250.00'))

        token = ReleaseToken.objects.get()
        self.assertEqual(token.token, 'LEGACYTOKEN0001')
        self.assertEqual(token.pos_reference, 'POS-LEG-1')
        self.assertEqual(token.status, 'REDEEMED')

    def test_the_status_mapping_is_the_documented_one(self):
        expected = {
            'DRAFT': 'pending',
            'PENDING': 'pending',
            'APPROVED': 'pending',
            'REJECTED': 'rejected',
            'RELEASED': 'ordered',
            'CANCELLED': 'rejected',
        }
        for legacy, mapped in expected.items():
            row = MaterialRequest.objects.get(pk=self.legacy_ids[legacy])
            self.assertEqual(row.status, mapped, legacy)
            self.assertEqual(row.legacy_status, legacy, legacy)

    def test_needed_by_and_approved_by_are_folded_only_where_provable(self):
        released = MaterialRequest.objects.get(pk=self.legacy_ids['RELEASED'])
        approved = MaterialRequest.objects.get(pk=self.legacy_ids['APPROVED'])

        # The needed-by date is the same fact under its new column name.
        self.assertEqual(released.needed_by, date(2025, 2, 1))
        # approved_by means "the owner who answered with an order": only the
        # released row provably had one.
        self.assertEqual(released.approved_by_id, self.manager.pk)
        self.assertIsNone(approved.approved_by_id)

    def test_the_reverse_migration_restores_the_raw_status(self):
        migration = __import__(
            'apps.requisitions.migrations.0004_legacy_procurement_data',
            fromlist=['backwards'],
        )
        migration.backwards(global_apps, None)

        for legacy, pk in self.legacy_ids.items():
            self.assertEqual(MaterialRequest.objects.get(pk=pk).status, legacy)

    def test_rejection_reason_and_reviewer_are_kept(self):
        rejected = MaterialRequest.objects.get(pk=self.legacy_ids['REJECTED'])

        self.assertEqual(rejected.status, 'rejected')
        self.assertEqual(rejected.rejection_reason, 'Legacy reason.')
        self.assertEqual(rejected.reviewed_by_id, self.manager.pk)

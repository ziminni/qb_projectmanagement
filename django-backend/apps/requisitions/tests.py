"""Pre-Phase-3 requisition tests: preserved rows, retired routes.

The Phase 3 build retired the legacy release-token API (a 128-bit bearer
secret any authenticated caller could `redeem/`, and an unscoped
`requisitions/` CRUD that bypassed Phase 2 project scoping). The **rows and
models stay** — `ReleaseToken` / `PosSyncLog` / the legacy request columns are
history — so their model tests are kept and only the route tests are replaced
by explicit "this path is gone" assertions.

The Phase 3 wire contract is tested in `tests_procurement.py`; the legacy data
mapping is tested in `tests_migration_procurement.py`.
"""

# Pyright here runs without django-stubs, so model managers are untyped.
# pyright: reportAttributeAccessIssue=false

from datetime import timedelta
from decimal import Decimal

from django.test import TestCase
from django.utils import timezone
from rest_framework.test import APIClient

from ..company.models import Company
from ..projects.models import Project, ProjectStatus, Site
from ..users.models import Role, User
from .models import (
    MaterialRequest,
    MaterialRequestItem,
    MaterialRequestStatus,
    ReleaseToken,
    TokenStatus,
)

FIXTURE_PASSWORD = 's3cret-pass-123'  # noqa: S105 - test fixture, not a credential


class RequisitionFixtures(TestCase):
    @classmethod
    def setUpTestData(cls):
        cls.site = Site.objects.create(code='SITE-900', name='Makati Tower')
        cls.project = Project.objects.create(
            code='PRJ-900',
            name='Tower A',
            site=cls.site,
            status=ProjectStatus.ONGOING,
        )
        cls.engineer = User.objects.create_user(
            email='eng1@example.com', password=FIXTURE_PASSWORD,
            full_name='Engineer One', company=Company.objects.first(),
            roles=[Role.SITE_ENGINEER],
        )
        cls.pm = User.objects.create_user(
            email='pm1@example.com', password=FIXTURE_PASSWORD,
            full_name='PM One', company=Company.objects.first(),
            roles=[Role.OWNER],
        )

    def make_request(self, **overrides):
        defaults = {
            'project': self.project,
            'site': self.site,
            'requested_by': self.engineer,
        }
        defaults.update(overrides)
        return MaterialRequest.objects.create(**defaults)


class MaterialRequestModelTests(RequisitionFixtures):
    def test_new_requests_start_pending_and_keep_the_legacy_columns(self):
        material_request = self.make_request(priority='NORMAL')

        self.assertEqual(material_request.status, MaterialRequestStatus.PENDING)
        self.assertTrue(material_request.is_editable)
        self.assertEqual(material_request.priority, 'NORMAL')
        # Phase 3 does not write these legacy columns, but they still hold data.
        self.assertEqual(material_request.legacy_status, '')
        self.assertEqual(material_request.number, f'MR-{material_request.pk:04d}')

    def test_reject_records_reason_and_reviewer(self):
        material_request = self.make_request()

        material_request.reject(self.pm, reason='Budget exhausted for this phase.')

        material_request.refresh_from_db()
        self.assertEqual(material_request.status, MaterialRequestStatus.REJECTED)
        self.assertEqual(
            material_request.rejection_reason, 'Budget exhausted for this phase.',
        )
        self.assertEqual(material_request.reviewed_by, self.pm)
        self.assertFalse(material_request.is_editable)

    def test_legacy_columns_and_totals_are_still_readable(self):
        material_request = self.make_request(request_no='REQ-0001')
        item = MaterialRequestItem.objects.create(
            material_request=material_request, item_sku='CEM-40KG',
            quantity_requested=Decimal('10'), quantity_approved=Decimal('10'),
            unit_cost=Decimal('250.00'),
        )

        self.assertEqual(item.approved_value, Decimal('2500.00'))
        self.assertEqual(item.quantity, Decimal('10'))
        self.assertEqual(material_request.request_no, 'REQ-0001')


class ReleaseTokenTests(RequisitionFixtures):
    """The legacy model keeps working; only its API surface is retired."""

    def test_issue_for_creates_active_token_with_expiry(self):
        token = ReleaseToken.issue_for(
            self.make_request(), user=self.pm, ttl_hours=48,
        )

        self.assertEqual(token.status, TokenStatus.ACTIVE)
        self.assertTrue(token.is_redeemable)
        self.assertEqual(token.issued_by, self.pm)
        self.assertEqual(len(token.token), 32)
        self.assertEqual(token.token, token.token.upper())
        self.assertGreater(token.expires_at, timezone.now() + timedelta(hours=47))

    def test_token_uses_configured_default_ttl(self):
        token = ReleaseToken.issue_for(self.make_request())

        self.assertAlmostEqual(
            (token.expires_at - token.issued_at).total_seconds() / 3600,
            72,  # settings.RELEASE_TOKEN_TTL_HOURS default
            delta=1,
        )

    def test_expired_token_is_not_redeemable(self):
        token = ReleaseToken.issue_for(self.make_request(), ttl_hours=-1)

        self.assertTrue(token.is_expired)
        self.assertFalse(token.is_redeemable)

    def test_mark_redeemed_records_pos_reference(self):
        token = ReleaseToken.issue_for(self.make_request(), user=self.pm)

        token.mark_redeemed(pos_reference='POS-SALE-7781', redeemed_by_name='Clerk Ana')

        self.assertEqual(token.status, TokenStatus.REDEEMED)
        self.assertEqual(token.pos_reference, 'POS-SALE-7781')
        self.assertEqual(token.redeemed_by_name, 'Clerk Ana')
        self.assertIsNotNone(token.redeemed_at)

    def test_tokens_are_unique_across_requests(self):
        first = ReleaseToken.issue_for(self.make_request(), user=self.pm)
        second = ReleaseToken.issue_for(self.make_request(), user=self.pm)

        self.assertNotEqual(first.token, second.token)

    def test_revoke_blocks_redemption(self):
        token = ReleaseToken.issue_for(self.make_request(), user=self.pm)

        token.revoke(reason='Superseded by REQ-0002.')

        self.assertEqual(token.status, TokenStatus.REVOKED)
        self.assertFalse(token.is_redeemable)
        self.assertIn('Superseded by REQ-0002.', token.notes)


class LegacyRoutesRetiredTests(RequisitionFixtures):
    """Every pre-Phase-3 requisition route is gone, including `redeem/`."""

    def setUp(self):
        self.client = APIClient()
        self.client.force_authenticate(user=self.pm)

    def test_health_endpoint_is_public(self):
        response = APIClient().get('/api/health/')

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['system'], 'cpms')

    def test_legacy_collections_are_retired(self):
        for path in (
            '/api/v1/requisitions/',
            '/api/v1/requisition-items/',
            '/api/v1/release-tokens/',
            '/api/v1/pos-sync-logs/',
        ):
            response = self.client.get(path)
            self.assertEqual(response.status_code, 404, path)

    def test_the_bearer_token_redeem_callback_is_retired(self):
        token = ReleaseToken.issue_for(self.make_request(), user=self.pm)

        response = self.client.post(
            '/api/v1/release-tokens/redeem/',
            {'token': token.token, 'pos_reference': 'POS-1'},
            format='json',
        )

        self.assertEqual(response.status_code, 404)
        token.refresh_from_db()
        self.assertEqual(token.status, TokenStatus.ACTIVE)

    def test_the_legacy_approval_actions_are_retired(self):
        material_request = self.make_request()

        for action in ('approve', 'reject', 'issue_token', 'push_to_pos'):
            response = self.client.post(
                f'/api/v1/requisitions/{material_request.pk}/{action}/', {},
                format='json',
            )
            self.assertEqual(response.status_code, 404, action)

    def test_procurement_routes_require_authentication(self):
        anonymous = APIClient()

        self.assertEqual(anonymous.get('/api/v1/material-requests/').status_code, 401)
        self.assertEqual(anonymous.get('/api/v1/purchase-orders/').status_code, 401)
        self.assertEqual(anonymous.get('/api/v1/deliveries/').status_code, 401)

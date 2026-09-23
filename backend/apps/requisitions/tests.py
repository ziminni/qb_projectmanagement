"""Tests for material requisitions and the POS release-token contract."""

from datetime import timedelta
from decimal import Decimal

from django.test import TestCase
from django.utils import timezone
from rest_framework.test import APIClient

from ..projects.models import Project, ProjectStatus, Site
from ..users.models import User, UserRole
from .models import (
    MaterialRequest,
    MaterialRequestItem,
    ReleaseToken,
    RequestStatus,
    TokenStatus,
)


class RequisitionFixtures(TestCase):
    @classmethod
    def setUpTestData(cls):
        cls.site = Site.objects.create(code='SITE-900', name='Makati Tower')
        cls.project = Project.objects.create(
            code='PRJ-900',
            name='Tower A',
            site=cls.site,
            status=ProjectStatus.IN_PROGRESS,
        )
        cls.engineer = User.objects.create_user(
            username='eng1', email='eng1@example.com', password='s3cret-pass-123',
            role=UserRole.ENGINEER,
        )
        cls.pm = User.objects.create_user(
            username='pm1', email='pm1@example.com', password='s3cret-pass-123',
            role=UserRole.PROJECT_MANAGER,
        )

    def make_request(self, **overrides):
        defaults = {
            'request_no': 'REQ-0001',
            'project': self.project,
            'site': self.site,
            'requested_by': self.engineer,
        }
        defaults.update(overrides)
        return MaterialRequest.objects.create(**defaults)


class MaterialRequestTests(RequisitionFixtures):
    def test_new_request_defaults_to_draft_and_normal_priority(self):
        material_request = self.make_request()

        self.assertEqual(material_request.status, RequestStatus.DRAFT)
        self.assertEqual(material_request.priority, 'NORMAL')
        self.assertTrue(material_request.is_editable)

    def test_approve_stamps_reviewer_and_locks_editing(self):
        material_request = self.make_request(status=RequestStatus.PENDING)

        material_request.approve(self.pm)

        self.assertEqual(material_request.status, RequestStatus.APPROVED)
        self.assertEqual(material_request.reviewed_by, self.pm)
        self.assertIsNotNone(material_request.reviewed_at)
        self.assertFalse(material_request.is_editable)

    def test_partial_approval_sets_partial_status(self):
        material_request = self.make_request(status=RequestStatus.PENDING)

        material_request.approve(self.pm, partial=True)

        self.assertEqual(material_request.status, RequestStatus.PARTIALLY_APPROVED)

    def test_reject_records_reason(self):
        material_request = self.make_request(status=RequestStatus.PENDING)

        material_request.reject(self.pm, reason='Budget exhausted for this phase.')

        self.assertEqual(material_request.status, RequestStatus.REJECTED)
        self.assertEqual(material_request.rejection_reason, 'Budget exhausted for this phase.')

    def test_total_approved_value_sums_line_items(self):
        material_request = self.make_request()
        MaterialRequestItem.objects.create(
            material_request=material_request, item_sku='CEM-40KG',
            quantity_requested=Decimal('10'), quantity_approved=Decimal('10'),
            unit_cost=Decimal('250.00'),
        )
        MaterialRequestItem.objects.create(
            material_request=material_request, item_sku='SND-1M',
            quantity_requested=Decimal('3'), quantity_approved=Decimal('2'),
            unit_cost=Decimal('1200.00'),
        )

        # 10 * 250 + 2 * 1200
        self.assertEqual(material_request.total_approved_value, Decimal('4900.00'))

    def test_outstanding_quantity_tracks_releases(self):
        item = MaterialRequestItem.objects.create(
            material_request=self.make_request(), item_sku='STL-10MM',
            quantity_requested=Decimal('100'), quantity_approved=Decimal('100'),
            quantity_released=Decimal('40'),
        )

        self.assertEqual(item.outstanding_quantity, Decimal('60'))


class ReleaseTokenTests(RequisitionFixtures):
    def test_issue_for_creates_active_token_with_expiry(self):
        material_request = self.make_request(status=RequestStatus.APPROVED)

        token = ReleaseToken.issue_for(material_request, user=self.pm, ttl_hours=48)

        self.assertEqual(token.status, TokenStatus.ACTIVE)
        self.assertTrue(token.is_redeemable)
        self.assertEqual(token.issued_by, self.pm)
        self.assertEqual(len(token.token), 32)
        self.assertEqual(token.token, token.token.upper())
        # Expiry should land ~48h out.
        self.assertGreater(token.expires_at, timezone.now() + timedelta(hours=47))

    def test_token_uses_configured_default_ttl(self):
        material_request = self.make_request(status=RequestStatus.APPROVED)

        token = ReleaseToken.issue_for(material_request)

        self.assertAlmostEqual(
            (token.expires_at - token.issued_at).total_seconds() / 3600,
            72,  # settings.RELEASE_TOKEN_TTL_HOURS default
            delta=1,
        )

    def test_expired_token_is_not_redeemable(self):
        material_request = self.make_request(status=RequestStatus.APPROVED)
        token = ReleaseToken.issue_for(material_request, ttl_hours=-1)

        self.assertTrue(token.is_expired)
        self.assertFalse(token.is_redeemable)

    def test_mark_redeemed_records_pos_reference(self):
        material_request = self.make_request(status=RequestStatus.APPROVED)
        token = ReleaseToken.issue_for(material_request, user=self.pm)

        token.mark_redeemed(pos_reference='POS-SALE-7781', redeemed_by_name='Clerk Ana')

        self.assertEqual(token.status, TokenStatus.REDEEMED)
        self.assertEqual(token.pos_reference, 'POS-SALE-7781')
        self.assertEqual(token.redeemed_by_name, 'Clerk Ana')
        self.assertIsNotNone(token.redeemed_at)

    def test_tokens_are_unique_across_requests(self):
        first = ReleaseToken.issue_for(
            self.make_request(request_no='REQ-A'), user=self.pm,
        )
        second = ReleaseToken.issue_for(
            self.make_request(request_no='REQ-B'), user=self.pm,
        )

        self.assertNotEqual(first.token, second.token)

    def test_revoke_blocks_redemption(self):
        material_request = self.make_request(status=RequestStatus.APPROVED)
        token = ReleaseToken.issue_for(material_request, user=self.pm)

        token.revoke(reason='Superseded by REQ-0002.')

        self.assertEqual(token.status, TokenStatus.REVOKED)
        self.assertFalse(token.is_redeemable)
        self.assertIn('Superseded by REQ-0002.', token.notes)


class ReleaseTokenAPITests(RequisitionFixtures):
    """End-to-end proof that the DRF wiring and URLconf are live."""

    def setUp(self):
        self.client = APIClient()
        self.client.force_authenticate(user=self.pm)

    def test_health_endpoint_is_public(self):
        response = APIClient().get('/api/health/')

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['system'], 'cpms')

    def test_redeem_marks_token_and_releases_quantities(self):
        material_request = self.make_request(status=RequestStatus.APPROVED)
        MaterialRequestItem.objects.create(
            material_request=material_request, item_sku='CEM-40KG',
            quantity_requested=Decimal('10'), quantity_approved=Decimal('10'),
            unit_cost=Decimal('250.00'),
        )
        token = ReleaseToken.issue_for(material_request, user=self.pm)

        response = self.client.post(
            '/api/v1/release-tokens/redeem/',
            {'token': token.token, 'pos_reference': 'POS-1', 'redeemed_by_name': 'Ana'},
            format='json',
        )

        self.assertEqual(response.status_code, 200, response.data)

        token.refresh_from_db()
        material_request.refresh_from_db()
        item = material_request.items.get()

        self.assertEqual(token.status, TokenStatus.REDEEMED)
        self.assertEqual(material_request.status, RequestStatus.RELEASED)
        self.assertEqual(item.quantity_released, Decimal('10'))

    def test_redeem_rejects_unknown_token(self):
        response = self.client.post(
            '/api/v1/release-tokens/redeem/',
            {'token': 'DOES-NOT-EXIST'},
            format='json',
        )

        self.assertEqual(response.status_code, 404)

    def test_redeem_rejects_already_redeemed_token(self):
        material_request = self.make_request(status=RequestStatus.APPROVED)
        token = ReleaseToken.issue_for(material_request, user=self.pm)
        token.mark_redeemed(pos_reference='POS-FIRST')

        response = self.client.post(
            '/api/v1/release-tokens/redeem/',
            {'token': token.token},
            format='json',
        )

        self.assertEqual(response.status_code, 409)

    def test_engineer_cannot_issue_tokens(self):
        material_request = self.make_request(status=RequestStatus.APPROVED)
        self.client.force_authenticate(user=self.engineer)

        response = self.client.post(
            f'/api/v1/requisitions/{material_request.pk}/issue_token/',
            {},
            format='json',
        )

        self.assertEqual(response.status_code, 403)

    def test_requisition_list_requires_authentication(self):
        response = APIClient().get('/api/v1/requisitions/')

        self.assertEqual(response.status_code, 401)
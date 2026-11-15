"""Phase 3 / task 3.1a wire-contract tests: requests, orders, receipts, stock.

Every rule the contract states for the operational scope has a test here:
project scoping (`404`), the role matrix (`403`), finance redaction, zero-write
refusals, decimal/precision refusals, receipt limits under a row lock, derived
site inventory, the advisory budget check, cancellation, and the durable POS
outbox row.

The financial routes (payables, payments, delivered-value) are out of scope by
contract and are not tested — they are blocked on the owner/accounting facts
listed in `planning/backend-integration/contracts/phase-3-procurement.md`.
"""

# Pyright here runs without django-stubs, so model managers are untyped.
# pyright: reportAttributeAccessIssue=false, reportArgumentType=false

import base64
import json
import threading
from datetime import date, timedelta
from decimal import Decimal

from django.core.files.uploadedfile import SimpleUploadedFile
from django.db import connections
from django.test import TransactionTestCase
from django.utils import timezone
from rest_framework.test import APIClient, APITestCase

from ..company.models import Company
from ..master_data.models import MaterialItem, Supplier
from ..projects.models import (
    Category,
    Client,
    Project,
    ProjectAssignment,
    ProjectStatus,
    RequestResponse,
    RoleOnProject,
)
from ..site_reports.models import DailyReport, DailyReportStatus, ReportMaterialUsage
from ..users.models import AuditLog, Notification, Role
from ..users.tests import make_user
from .models import (
    Delivery,
    DeliveryItem,
    MaterialRequest,
    MaterialRequestItem,
    MaterialRequestStatus,
    MaterialSource,
    PosOutboxJob,
    PosOutboxOperation,
    PosOutboxState,
    PosSyncStatus,
    PurchaseOrder,
    PurchaseOrderStatus,
    SiteCount,
)

# A one-pixel PNG: real magic bytes, so the upload validator accepts it.
PNG_BYTES = base64.b64decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=='
)


def png(name='receipt.png'):
    return SimpleUploadedFile(name, PNG_BYTES, content_type='image/png')


class ProcurementFixtures:
    """Two projects (A in scope, B not), all five roles and the master data.

    A mixin (not a `TestCase`) so the threaded concurrency test can reuse the
    same fixtures on a `TransactionTestCase`, whose rows are really committed.
    """

    def setUp(self):
        # A TransactionTestCase flushes the database, so the seeded company may
        # be gone: create one rather than depending on another suite's state.
        if not Company.objects.exists():
            Company.objects.create(name='BuildPro Test')
        self.admin = make_user('admin@example.com', [Role.ADMIN])
        self.owner = make_user('maria@example.com', [Role.OWNER])
        self.other_owner = make_user('owner2@example.com', [Role.OWNER])
        self.engineer = make_user('ramon@example.com', [Role.SITE_ENGINEER])
        self.other_engineer = make_user('eng2@example.com', [Role.SITE_ENGINEER])
        self.accountant = make_user('liza@example.com', [Role.ACCOUNTANT])
        self.client_user = make_user('elena@example.com', [Role.CLIENT])
        self.client_record = Client.objects.create(
            name='Acme Holdings', user=self.client_user,
        )

        self.project = self.make_project('PRJ-A', 'Tower A')
        self.other_project = self.make_project('PRJ-B', 'Tower B')
        self.join(self.project, self.owner, RoleOnProject.OWNER)
        self.join(self.project, self.engineer, RoleOnProject.SITE_ENGINEER)
        self.join(self.other_project, self.other_owner, RoleOnProject.OWNER)
        self.join(self.other_project, self.other_engineer, RoleOnProject.SITE_ENGINEER)

        self.category = Category.objects.create(
            project=self.project, name='Siteworks', sort_order=1,
            budget=Decimal('400000.00'),
        )
        self.other_category = Category.objects.create(
            project=self.other_project, name='Siteworks', sort_order=1,
            budget=Decimal('100000.00'),
        )
        self.cement = MaterialItem.objects.create(
            name='Portland Cement', unit='bag', default_unit_cost=Decimal('250.00'),
            pos_code='CEM-40KG',
        )
        self.sand = MaterialItem.objects.create(
            name='Washed Sand', unit='cu.m', default_unit_cost=Decimal('1200.00'),
        )
        self.own_store = Supplier.objects.create(
            name='BuildPro Hardware', is_own_store=True, pos_payer_id=7,
        )

    # --- fixtures -------------------------------------------------------
    def make_project(self, code, name, status=ProjectStatus.ONGOING):
        return Project.objects.create(
            code=code, name=name, client=self.client_record,
            contract_amount=Decimal('1000000.00'),
            start_date=date(2026, 1, 1), target_end_date=date(2026, 6, 30),
            status=status,
        )

    def join(self, project, user, role_on_project):
        return ProjectAssignment.objects.create(
            project=project, user=user, role_on_project=role_on_project,
            response=RequestResponse.ACCEPTED,
        )

    def act_as(self, user, role):
        self.client.force_authenticate(user=user)
        self.client.credentials(HTTP_X_ACTIVE_ROLE=role)

    def request_payload(self, **overrides):
        payload = {
            'project_id': self.project.pk,
            'needed_by': (timezone.localdate() + timedelta(days=3)).isoformat(),
            'items': [
                {'description': 'Cement for the slab', 'unit': 'bag', 'quantity': 40},
            ],
            'counts': [],
        }
        payload.update(overrides)
        return payload

    def make_request(self, project=None, user=None, status=MaterialRequestStatus.PENDING):
        project = project or self.project
        material_request = MaterialRequest.objects.create(
            project=project,
            requested_by=user or self.engineer,
            status=status,
            needed_by=timezone.localdate() + timedelta(days=3),
        )
        material_request.request_no = material_request.number
        material_request.save(update_fields=['request_no'])
        return material_request

    def add_item(self, material_request, description='Cement', quantity='10.00'):
        return MaterialRequestItem.objects.create(
            material_request=material_request,
            description=description,
            unit='bag',
            quantity_requested=Decimal(quantity),
        )

    def place_order(self, material_request=None, **overrides):
        """POST an own-store order and return the parsed response."""
        material_request = material_request or self.make_request()
        self.act_as(self.owner, Role.OWNER)
        payload = {
            'request_id': material_request.pk,
            'category_id': self.category.pk,
            'source': 'own_store',
            'delivery_address': 'Gate 2, Tower A site',
            'lines': [
                {
                    'material_id': self.cement.pk,
                    'description': 'Portland Cement',
                    'unit': 'bag',
                    'quantity': 10,
                    'unit_price': '250.00',
                },
            ],
            'covers_item_ids': [],
        }
        payload.update(overrides)
        return material_request, self.client.post(
            '/api/v1/purchase-orders/', payload, format='json',
        )

    def confirm_delivery(self, order, lines, files=None):
        self.act_as(self.engineer, Role.SITE_ENGINEER)
        payload = {'lines': json.dumps(lines)}
        if files:
            payload.update(files)
        return self.client.post(
            f'/api/v1/purchase-orders/{order.pk}/deliveries/', payload,
            format='multipart',
        )


class ProcurementCase(ProcurementFixtures, APITestCase):
    """The normal case: fixtures plus an API client (one rolled-back test)."""


# --------------------------------------------------------------------------
# Material requests
# --------------------------------------------------------------------------

class MaterialRequestCreateTests(ProcurementCase):
    def test_site_engineer_creates_a_request_with_server_owned_fields(self):
        self.act_as(self.engineer, Role.SITE_ENGINEER)
        response = self.client.post(
            '/api/v1/material-requests/', self.request_payload(), format='json',
        )

        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(response.data['status'], 'pending')
        self.assertEqual(response.data['requested_by'], self.engineer.pk)
        self.assertIsNone(response.data['approved_by'])
        self.assertEqual(response.data['project_id'], self.project.pk)
        self.assertEqual(
            response.data['needed_by'],
            (timezone.localdate() + timedelta(days=3)).isoformat(),
        )
        material_request = MaterialRequest.objects.get(pk=response.data['id'])
        self.assertEqual(material_request.request_no, f'MR-{material_request.pk:04d}')
        self.assertEqual(material_request.items.count(), 1)
        self.assertTrue(
            AuditLog.objects.filter(
                action='material_request_created', entity_id=material_request.pk,
            ).exists()
        )
        self.assertTrue(Notification.objects.filter(
            user=self.owner, type='material_request',
            message=f'{material_request.number} for PRJ-A is waiting for you.',
        ).exists())

    def test_site_count_stores_the_server_expected_snapshot(self):
        # Deliver 10 cement so the system thinks 10 bags are on site.
        material_request, response = self.place_order()
        self.assertEqual(response.status_code, 201, response.data)
        order = PurchaseOrder.objects.get(pk=response.data['id'])
        line = order.items.get()
        self.confirm_delivery(order, [{'po_item_id': line.pk, 'received': 10, 'damaged': 0}])

        self.act_as(self.engineer, Role.SITE_ENGINEER)
        response = self.client.post('/api/v1/material-requests/', self.request_payload(
            counts=[{
                'material_id': self.cement.pk, 'name': 'Portland Cement',
                'unit': 'bag', 'expected': '10.00', 'counted': '9',
            }],
        ), format='json')

        self.assertEqual(response.status_code, 201, response.data)
        count = SiteCount.objects.get(material_request_id=response.data['id'])
        self.assertEqual(count.expected, Decimal('10.00'))
        self.assertEqual(count.counted, Decimal('9.00'))

    def test_missing_count_refuses_and_writes_nothing(self):
        material_request, response = self.place_order()
        order = PurchaseOrder.objects.get(pk=response.data['id'])
        self.confirm_delivery(order, [
            {'po_item_id': order.items.get().pk, 'received': 5, 'damaged': 0},
        ])
        before = MaterialRequest.objects.count()

        self.act_as(self.engineer, Role.SITE_ENGINEER)
        response = self.client.post(
            '/api/v1/material-requests/', self.request_payload(), format='json',
        )

        self.assertEqual(response.status_code, 400)
        self.assertEqual(
            response.data['detail'],
            'Count the Portland Cement on site before requesting more.',
        )
        self.assertEqual(MaterialRequest.objects.count(), before)

    def test_stale_expected_is_a_retryable_conflict_and_writes_nothing(self):
        material_request, response = self.place_order()
        order = PurchaseOrder.objects.get(pk=response.data['id'])
        self.confirm_delivery(order, [
            {'po_item_id': order.items.get().pk, 'received': 10, 'damaged': 0},
        ])
        before = MaterialRequest.objects.count()

        self.act_as(self.engineer, Role.SITE_ENGINEER)
        response = self.client.post('/api/v1/material-requests/', self.request_payload(
            counts=[{
                'material_id': self.cement.pk, 'name': 'Portland Cement',
                'unit': 'bag', 'expected': '7.00', 'counted': '7',
            }],
        ), format='json')

        self.assertEqual(response.status_code, 409)
        self.assertEqual(response.data['code'], 'STALE_SITE_COUNT')
        self.assertEqual(MaterialRequest.objects.count(), before)

    def test_needed_by_is_required_and_cannot_be_in_the_past(self):
        self.act_as(self.engineer, Role.SITE_ENGINEER)
        yesterday = (timezone.localdate() - timedelta(days=1)).isoformat()

        past = self.client.post(
            '/api/v1/material-requests/',
            self.request_payload(needed_by=yesterday), format='json',
        )
        missing = self.client.post(
            '/api/v1/material-requests/',
            self.request_payload(needed_by=None), format='json',
        )

        self.assertEqual(past.status_code, 400)
        self.assertEqual(past.data['detail'], 'The needed-by date cannot be in the past.')
        self.assertEqual(missing.status_code, 400)
        self.assertEqual(missing.data['detail'], 'Choose the needed-by date.')
        self.assertEqual(MaterialRequest.objects.count(), 0)

    def test_at_least_one_item_and_quantity_rules(self):
        self.act_as(self.engineer, Role.SITE_ENGINEER)

        empty = self.client.post(
            '/api/v1/material-requests/', self.request_payload(items=[]), format='json',
        )
        zero = self.client.post('/api/v1/material-requests/', self.request_payload(
            items=[{'description': 'Cement', 'unit': 'bag', 'quantity': 0}],
        ), format='json')
        blank = self.client.post('/api/v1/material-requests/', self.request_payload(
            items=[{'description': '  ', 'unit': 'bag', 'quantity': 1}],
        ), format='json')
        precise = self.client.post('/api/v1/material-requests/', self.request_payload(
            items=[{'description': 'Cement', 'unit': 'bag', 'quantity': '1.005'}],
        ), format='json')
        infinite = self.client.post('/api/v1/material-requests/', self.request_payload(
            items=[{'description': 'Cement', 'unit': 'bag', 'quantity': 'Infinity'}],
        ), format='json')

        self.assertEqual(empty.data['detail'], 'Add at least one item.')
        self.assertEqual(zero.data['detail'], 'Quantity must be greater than 0.')
        self.assertEqual(blank.data['detail'], 'Enter the item.')
        self.assertEqual(precise.data['detail'], 'Use at most 2 decimal places.')
        self.assertEqual(infinite.data['detail'], 'Quantity must be greater than 0.')
        for response in (empty, zero, blank, precise, infinite):
            self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(MaterialRequest.objects.count(), 0)

    def test_request_needs_an_ongoing_project(self):
        self.project.status = ProjectStatus.ACCEPTED
        self.project.save(update_fields=['status'])
        self.act_as(self.engineer, Role.SITE_ENGINEER)

        response = self.client.post(
            '/api/v1/material-requests/', self.request_payload(), format='json',
        )

        self.assertEqual(response.status_code, 400)
        self.assertEqual(
            response.data['detail'],
            'Material requests can be added only while the project is Ongoing '
            '(it is Accepted).',
        )

    def test_only_the_assigned_site_engineer_may_request(self):
        self.act_as(self.owner, Role.OWNER)
        as_owner = self.client.post(
            '/api/v1/material-requests/', self.request_payload(), format='json',
        )
        self.act_as(self.accountant, Role.ACCOUNTANT)
        as_accountant = self.client.post(
            '/api/v1/material-requests/', self.request_payload(), format='json',
        )

        self.assertEqual(as_owner.status_code, 403)
        self.assertEqual(as_accountant.status_code, 403)
        self.assertEqual(
            as_owner.data['detail'],
            'Only the site engineer assigned to this project can request materials.',
        )
        self.assertEqual(MaterialRequest.objects.count(), 0)

    def test_untracked_count_material_id_is_validated_and_writes_nothing(self):
        """A junk or unknown `material_id` is a `400`, never a `500` 500-write."""
        self.act_as(self.engineer, Role.SITE_ENGINEER)
        before = (MaterialRequest.objects.count(), SiteCount.objects.count())
        refused = {}
        for bad in ('abc', '1.5', -5, True, 10 ** 12, 10 ** 30, 999999):
            refused[bad] = self.client.post(
                '/api/v1/material-requests/', self.request_payload(counts=[{
                    'material_id': bad, 'name': 'Rebar 12mm', 'unit': 'pc',
                    'expected': '0', 'counted': '2',
                }]), format='json',
            )

        # Absent or null ids are still legitimate evidence: name only.
        null_id = self.client.post('/api/v1/material-requests/', self.request_payload(
            counts=[{
                'material_id': None, 'name': 'Rebar 12mm', 'unit': 'pc',
                'expected': '0', 'counted': '2',
            }],
        ), format='json')
        omitted = self.client.post(
            '/api/v1/material-requests/', self.request_payload(counts=[{
                'name': 'Coco lumber', 'unit': 'pc', 'expected': '0', 'counted': '3',
            }]), format='json',
        )

        self.assertEqual(null_id.status_code, 201, null_id.data)
        self.assertEqual(omitted.status_code, 201, omitted.data)
        self.assertEqual(
            SiteCount.objects.get(material_request_id=null_id.data['id']).material_id,
            None,
        )
        for bad, response in refused.items():
            self.assertEqual(response.status_code, 400, (bad, response.data))
            self.assertEqual(
                response.data['detail'],
                'Pick the counted material from the price list or leave it blank.',
            )
        self.assertEqual(
            (MaterialRequest.objects.count(), SiteCount.objects.count()),
            (before[0] + 2, before[1] + 2),
        )

    def test_a_valid_count_material_id_is_kept(self):
        self.act_as(self.engineer, Role.SITE_ENGINEER)

        response = self.client.post('/api/v1/material-requests/', self.request_payload(
            counts=[{
                'material_id': self.sand.pk, 'name': 'Washed Sand', 'unit': 'cu.m',
                'expected': '0', 'counted': '0',
            }],
        ), format='json')

        self.assertEqual(response.status_code, 201, response.data)
        count = SiteCount.objects.get(material_request_id=response.data['id'])
        self.assertEqual(count.material_id, self.sand.pk)

    def test_other_projects_are_404_and_clients_have_no_procurement(self):
        self.act_as(self.other_engineer, Role.SITE_ENGINEER)
        cross = self.client.post(
            '/api/v1/material-requests/', self.request_payload(), format='json',
        )
        self.act_as(self.client_user, Role.CLIENT)
        client = self.client.get('/api/v1/material-requests/')

        self.assertEqual(cross.status_code, 404)
        self.assertEqual(client.status_code, 403)
        self.assertEqual(client.data['detail'], 'Only the project team can see procurement records.')


class MaterialRequestRejectTests(ProcurementCase):
    def test_owner_rejects_a_pending_request(self):
        material_request = self.make_request()
        self.act_as(self.owner, Role.OWNER)

        response = self.client.post(
            f'/api/v1/material-requests/{material_request.pk}/reject/',
            {'reason': 'Use the stock left on site.'}, format='json',
        )

        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data['status'], 'rejected')
        material_request.refresh_from_db()
        self.assertEqual(material_request.rejection_reason, 'Use the stock left on site.')
        self.assertEqual(material_request.reviewed_by, self.owner)
        self.assertTrue(Notification.objects.filter(
            user=self.engineer, type='material_request',
        ).exists())

    def test_blank_reason_refuses_and_writes_nothing(self):
        material_request = self.make_request()
        self.act_as(self.owner, Role.OWNER)

        response = self.client.post(
            f'/api/v1/material-requests/{material_request.pk}/reject/',
            {'reason': '   '}, format='json',
        )

        self.assertEqual(response.status_code, 400)
        self.assertEqual(response.data['detail'], 'Give a reason for rejecting.')
        material_request.refresh_from_db()
        self.assertEqual(material_request.status, MaterialRequestStatus.PENDING)

    def test_only_a_pending_request_can_be_rejected(self):
        material_request = self.make_request(status=MaterialRequestStatus.ORDERED)
        self.act_as(self.owner, Role.OWNER)

        response = self.client.post(
            f'/api/v1/material-requests/{material_request.pk}/reject/',
            {'reason': 'Too late.'}, format='json',
        )

        self.assertEqual(response.status_code, 400)
        self.assertEqual(
            response.data['detail'],
            'This request is ordered and cannot be rejected by a owner / project manager.',
        )
        material_request.refresh_from_db()
        self.assertEqual(material_request.status, MaterialRequestStatus.ORDERED)

    def test_role_matrix_and_cross_project_scope(self):
        material_request = self.make_request()
        for user, role in (
            (self.engineer, Role.SITE_ENGINEER),
            (self.admin, Role.ADMIN),
            (self.accountant, Role.ACCOUNTANT),
        ):
            self.act_as(user, role)
            response = self.client.post(
                f'/api/v1/material-requests/{material_request.pk}/reject/',
                {'reason': 'No.'}, format='json',
            )
            self.assertEqual(response.status_code, 403, (role, response.data))

        self.act_as(self.other_owner, Role.OWNER)
        cross = self.client.post(
            f'/api/v1/material-requests/{material_request.pk}/reject/',
            {'reason': 'No.'}, format='json',
        )
        self.assertEqual(cross.status_code, 404)


# --------------------------------------------------------------------------
# Purchase orders
# --------------------------------------------------------------------------

class PurchaseOrderTests(ProcurementCase):
    def test_own_store_order_mints_identity_and_enqueues_the_outbox(self):
        material_request = self.make_request()
        item = self.add_item(material_request)

        _, response = self.place_order(
            material_request, covers_item_ids=[item.pk],
        )

        self.assertEqual(response.status_code, 201, response.data)
        order = PurchaseOrder.objects.get(pk=response.data['id'])
        self.assertEqual(order.source, MaterialSource.OWN_STORE)
        self.assertEqual(order.status, PurchaseOrderStatus.RELEASED)
        self.assertEqual(order.supplier, self.own_store)
        self.assertEqual(order.total_amount, Decimal('2500.00'))
        self.assertEqual(order.pos_sync_status, PosSyncStatus.PENDING_SYNC)
        self.assertIsNotNone(order.pos_request_id)
        self.assertIsNotNone(order.pos_token)
        self.assertEqual(order.po_no, f'PO-{timezone.localdate():%Y}-{order.pk:04d}')
        self.assertEqual(response.data['total_amount'], '2500.00')
        self.assertNotIn('pos_token', response.data)
        self.assertNotIn('pos_request_id', response.data)

        job = PosOutboxJob.objects.get(purchase_order=order)
        self.assertEqual(job.operation, PosOutboxOperation.IMPORT)
        self.assertEqual(job.state, PosOutboxState.PENDING)
        self.assertEqual(job.payload['cpms_request_id'], order.po_no)
        self.assertEqual(job.payload['items'], [{'code': 'CEM-40KG', 'quantity': '10.00'}])
        self.assertNotIn('token', json.dumps(job.payload))

        item.refresh_from_db()
        self.assertEqual(item.purchase_order, order)
        material_request.refresh_from_db()
        self.assertEqual(material_request.status, MaterialRequestStatus.ORDERED)
        self.assertEqual(material_request.approved_by, self.owner)

    def test_own_store_requires_a_delivery_address(self):
        _, response = self.place_order(delivery_address='   ')

        self.assertEqual(response.status_code, 400)
        self.assertEqual(response.data['detail'], 'Enter the delivery address.')
        self.assertEqual(PurchaseOrder.objects.count(), 0)
        self.assertEqual(PosOutboxJob.objects.count(), 0)

    def test_own_store_needs_catalog_material_with_a_pos_code(self):
        _, no_material = self.place_order(lines=[{
            'description': 'Cement', 'unit': 'bag', 'quantity': 1, 'unit_price': '250.00',
        }])
        _, no_code = self.place_order(lines=[{
            'material_id': self.sand.pk, 'description': 'Washed Sand',
            'unit': 'cu.m', 'quantity': 1, 'unit_price': '1200.00',
        }])

        self.assertEqual(no_material.status_code, 400)
        self.assertEqual(
            no_material.data['detail'],
            'Pick own-store materials from the store catalog.',
        )
        self.assertEqual(no_code.status_code, 400)
        self.assertIn('POS code', no_code.data['detail'])
        self.assertEqual(PurchaseOrder.objects.count(), 0)

    def test_own_store_supplier_must_be_unambiguous(self):
        _, none = self.place_order()
        self.assertEqual(none.status_code, 201, none.data)

        Supplier.objects.create(name='Second Store', is_own_store=True)
        _, ambiguous = self.place_order()

        self.assertEqual(ambiguous.status_code, 400)
        self.assertEqual(
            ambiguous.data['detail'],
            'More than one own store is set up. Keep exactly one.',
        )

    def test_no_own_store_supplier_is_a_setup_refusal(self):
        Supplier.objects.all().delete()

        _, response = self.place_order()

        self.assertEqual(response.status_code, 400)
        self.assertEqual(
            response.data['detail'], 'Set up the own store in the supplier list first.',
        )
        self.assertEqual(PurchaseOrder.objects.count(), 0)

    def test_external_order_needs_a_private_receipt_photo(self):
        self.act_as(self.owner, Role.OWNER)
        material_request = self.make_request()
        payload = {
            'request_id': material_request.pk,
            'category_id': self.category.pk,
            'source': 'external',
            'store_name': 'Cebu Hardware',
            'or_number': 'OR-7781',
            'lines': json.dumps([{
                'description': 'Cement', 'unit': 'bag', 'quantity': 5,
                'unit_price': '260.00',
            }]),
            'covers_item_ids': '[]',
        }

        missing = self.client.post('/api/v1/purchase-orders/', payload, format='multipart')
        fake = self.client.post(
            '/api/v1/purchase-orders/', {
                **payload,
                'receipt_photo': SimpleUploadedFile(
                    'receipt.png', b'<html>not an image</html>',
                    content_type='image/png',
                ),
            }, format='multipart',
        )

        self.assertEqual(missing.status_code, 400)
        self.assertEqual(missing.data['detail'], 'Attach a photo of the receipt.')
        self.assertEqual(fake.status_code, 400)
        self.assertIn('does not look like', str(fake.data['detail']).lower() + ' '
                      if False else str(fake.data['detail']))
        self.assertEqual(PurchaseOrder.objects.count(), 0)
        self.assertEqual(PosOutboxJob.objects.count(), 0)

    def test_external_order_stores_private_evidence_and_never_touches_the_pos(self):
        self.act_as(self.owner, Role.OWNER)
        material_request = self.make_request()
        response = self.client.post('/api/v1/purchase-orders/', {
            'request_id': material_request.pk,
            'category_id': self.category.pk,
            'source': 'external',
            'store_name': 'Cebu Hardware',
            'or_number': 'OR-7781',
            'lines': json.dumps([{
                'description': 'Cement', 'unit': 'bag', 'quantity': 5,
                'unit_price': '260.00',
            }]),
            'receipt_photo': png(),
        }, format='multipart')

        self.assertEqual(response.status_code, 201, response.data)
        order = PurchaseOrder.objects.get(pk=response.data['id'])
        self.assertEqual(order.status, PurchaseOrderStatus.PURCHASED)
        self.assertEqual(order.pos_sync_status, PosSyncStatus.NOT_APPLICABLE)
        self.assertIsNone(order.pos_request_id)
        self.assertTrue(order.receipt_file_name)
        self.assertNotIn('/', order.receipt_file_name)
        self.assertFalse(PosOutboxJob.objects.exists())
        self.assertTrue(response.data['receipt_photo_url'].startswith('http'))
        self.assertIn(f'/receipt/{order.receipt_file_name}', response.data['receipt_photo_url'])
        # The stored file lives under the private media root, never a public URL.
        self.assertTrue(order.receipt_file.path.startswith(str(order.receipt_file.storage.location)))

    def test_category_must_belong_to_the_request_project(self):
        _, response = self.place_order(category_id=self.other_category.pk)

        self.assertEqual(response.status_code, 400)
        self.assertEqual(
            response.data['detail'], 'Choose the budget category of this project.',
        )

    def test_rejected_request_cannot_be_ordered(self):
        material_request = self.make_request(status=MaterialRequestStatus.REJECTED)

        _, response = self.place_order(material_request)

        self.assertEqual(response.status_code, 400)
        self.assertEqual(response.data['detail'], 'This request was rejected.')

    def test_coverage_is_unique_and_must_belong_to_the_request(self):
        material_request = self.make_request()
        item = self.add_item(material_request)
        other_request = self.make_request()
        foreign_item = self.add_item(other_request, description='Sand')

        _, foreign = self.place_order(material_request, covers_item_ids=[foreign_item.pk])
        self.assertEqual(foreign.status_code, 400)
        self.assertEqual(foreign.data['detail'], 'An item is not on this request.')

        _, first = self.place_order(material_request, covers_item_ids=[item.pk])
        self.assertEqual(first.status_code, 201, first.data)
        _, second = self.place_order(material_request, covers_item_ids=[item.pk])
        self.assertEqual(second.status_code, 400)
        self.assertEqual(
            second.data['detail'],
            'Cement is already covered by another order.',
        )

    def test_order_line_refusals(self):
        _, empty = self.place_order(lines=[])
        _, price = self.place_order(lines=[{
            'material_id': self.cement.pk, 'description': 'Cement',
            'unit': 'bag', 'quantity': 1, 'unit_price': '-1',
        }])
        _, precision = self.place_order(lines=[{
            'material_id': self.cement.pk, 'description': 'Cement',
            'unit': 'bag', 'quantity': 1, 'unit_price': '1.005',
        }])
        _, no_description = self.place_order(lines=[{
            'material_id': self.cement.pk, 'description': ' ',
            'unit': 'bag', 'quantity': 1, 'unit_price': '1',
        }])

        self.assertEqual(empty.data['detail'], 'Add at least one material.')
        self.assertEqual(price.data['detail'], 'Enter a unit price of 0 or more.')
        self.assertEqual(precision.data['detail'], 'Use at most 2 decimal places.')
        self.assertEqual(no_description.data['detail'], 'Enter the material.')
        self.assertEqual(PurchaseOrder.objects.count(), 0)

    def test_role_matrix_and_scope_for_placing_orders(self):
        material_request = self.make_request()
        for user, role in (
            (self.engineer, Role.SITE_ENGINEER),
            (self.admin, Role.ADMIN),
            (self.accountant, Role.ACCOUNTANT),
        ):
            self.act_as(user, role)
            response = self.client.post('/api/v1/purchase-orders/', {
                'request_id': material_request.pk,
                'category_id': self.category.pk,
                'source': 'own_store',
                'delivery_address': 'Site',
                'lines': [{
                    'material_id': self.cement.pk, 'description': 'Cement',
                    'unit': 'bag', 'quantity': 1, 'unit_price': '250.00',
                }],
            }, format='json')
            self.assertEqual(response.status_code, 403, (role, response.data))

        other_request = self.make_request(project=self.other_project)
        self.act_as(self.owner, Role.OWNER)
        cross = self.client.post('/api/v1/purchase-orders/', {
            'request_id': other_request.pk,
            'category_id': self.other_category.pk,
            'source': 'own_store',
            'delivery_address': 'Site',
            'lines': [{
                'material_id': self.cement.pk, 'description': 'Cement',
                'unit': 'bag', 'quantity': 1, 'unit_price': '250.00',
            }],
        }, format='json')
        self.assertEqual(cross.status_code, 404)
        self.assertEqual(PurchaseOrder.objects.count(), 0)

    def test_body_cannot_set_server_owned_fields(self):
        material_request = self.make_request()

        _, response = self.place_order(
            material_request,
            status='delivered',
            total_amount='1.00',
            po_no='PO-FAKE',
            approved_by=self.engineer.pk,
        )

        self.assertEqual(response.status_code, 201, response.data)
        order = PurchaseOrder.objects.get(pk=response.data['id'])
        self.assertEqual(order.status, PurchaseOrderStatus.RELEASED)
        self.assertEqual(order.total_amount, Decimal('2500.00'))
        self.assertNotEqual(order.po_no, 'PO-FAKE')
        self.assertEqual(order.approved_by, self.owner)


class RedactionAndScopeTests(ProcurementCase):
    def test_finance_keys_are_omitted_for_non_finance_roles(self):
        _, response = self.place_order()
        order_id = response.data['id']

        for user, role in ((self.engineer, Role.SITE_ENGINEER), (self.admin, Role.ADMIN)):
            self.act_as(user, role)
            listing = self.client.get('/api/v1/purchase-orders/')
            detail = self.client.get(f'/api/v1/purchase-orders/{order_id}/')

            self.assertEqual(listing.status_code, 200, listing.data)
            row = listing.data[0]
            self.assertNotIn('total_amount', row)
            self.assertNotIn('receipt_photo_url', row)
            self.assertNotIn('unit_price', detail.data['items'][0])
            self.assertNotIn('total_amount', detail.data['order'])

        self.act_as(self.owner, Role.OWNER)
        visible = self.client.get(f'/api/v1/purchase-orders/{order_id}/')
        self.assertEqual(visible.data['order']['total_amount'], '2500.00')
        self.assertEqual(visible.data['items'][0]['unit_price'], '250.00')

    def test_admin_audit_trail_carries_no_money(self):
        """`admin` is not a finance role but can read the audit log."""
        _, response = self.place_order()
        order_id = response.data['id']

        self.act_as(self.admin, Role.ADMIN)
        listing = self.client.get(
            f'/api/v1/audit-logs/?entity=purchase_order&entity_id={order_id}'
        )

        self.assertEqual(listing.status_code, 200, listing.data)
        self.assertEqual(len(listing.data['results']), 1, listing.data)
        row = listing.data['results'][0]
        self.assertEqual(row['details']['lines'], 1)
        self.assertEqual(row['details']['source'], 'own_store')
        self.assertEqual(row['details']['request_id'], PurchaseOrder.objects.get(
            pk=order_id).material_request_id)
        self.assertNotIn('total', row['details'])
        body = json.dumps(listing.data)
        self.assertNotIn('2500', body)
        self.assertNotIn('total', body)
        self.assertNotIn(
            '2500',
            ' '.join(Notification.objects.values_list('message', flat=True)),
        )

    def test_or_number_is_finance_only(self):
        """OR evidence is finance-sensitive (contract access section)."""
        self.act_as(self.owner, Role.OWNER)
        material_request = self.make_request()
        payload = {
            'request_id': material_request.pk,
            'category_id': self.category.pk,
            'source': 'external',
            'store_name': 'Cebu Hardware',
            'or_number': 'OR-7781',
            'lines': json.dumps([{
                'description': 'Cement', 'unit': 'bag', 'quantity': 5,
                'unit_price': '260.00',
            }]),
            'covers_item_ids': '[]',
        }
        created = self.client.post(
            '/api/v1/purchase-orders/', {**payload, 'receipt_photo': png()},
            format='multipart',
        )

        self.assertEqual(created.status_code, 201, created.data)
        self.assertEqual(created.data['or_number'], 'OR-7781')
        order_id = created.data['id']

        for user, role in ((self.admin, Role.ADMIN), (self.engineer, Role.SITE_ENGINEER)):
            self.act_as(user, role)
            row = self.client.get(f'/api/v1/purchase-orders/{order_id}/')
            listing = self.client.get('/api/v1/purchase-orders/')

            self.assertEqual(row.status_code, 200, row.data)
            self.assertNotIn('or_number', row.data['order'])
            self.assertNotIn('or_number', listing.data[0])

        self.act_as(self.accountant, Role.ACCOUNTANT)
        finance = self.client.get(f'/api/v1/purchase-orders/{order_id}/')
        self.assertEqual(finance.data['order']['or_number'], 'OR-7781')

    def test_lists_are_scoped_and_ignore_foreign_project_filters(self):
        own_request = self.make_request()
        other_request = self.make_request(project=self.other_project)
        _, own = self.place_order(own_request)
        self.act_as(self.other_owner, Role.OWNER)
        _, other = self.place_order(other_request, category_id=self.other_category.pk)

        self.act_as(self.owner, Role.OWNER)
        listing = self.client.get(
            f'/api/v1/purchase-orders/?project={self.project.pk},{self.other_project.pk}'
        )
        self.assertEqual(listing.status_code, 200, listing.data)
        self.assertEqual([row['id'] for row in listing.data], [own.data['id']])

        self.act_as(self.other_owner, Role.OWNER)
        cross = self.client.get(f'/api/v1/purchase-orders/{own.data["id"]}/')
        cross_request = self.client.get(f'/api/v1/material-requests/{own_request.pk}/')
        cross_inventory = self.client.get(f'/api/v1/projects/{self.project.pk}/site-inventory/')

        self.assertEqual(cross.status_code, 404)
        self.assertEqual(cross_request.status_code, 404)
        self.assertEqual(cross_inventory.status_code, 404)

    def test_request_detail_is_a_wrapper_with_counts(self):
        material_request = self.make_request()
        self.add_item(material_request)
        SiteCount.objects.create(
            material_request=material_request, material=self.cement,
            name='Portland Cement', unit='bag',
            expected=Decimal('2.00'), counted=Decimal('1.00'),
        )
        self.act_as(self.engineer, Role.SITE_ENGINEER)

        response = self.client.get(f'/api/v1/material-requests/{material_request.pk}/')

        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(set(response.data), {'request', 'items', 'counts'})
        self.assertEqual(response.data['items'][0]['quantity'], '10.00')
        self.assertEqual(response.data['counts'][0]['counted'], '1.00')

    def test_receipt_evidence_is_finance_only(self):
        self.act_as(self.owner, Role.OWNER)
        material_request = self.make_request()
        created = self.client.post('/api/v1/purchase-orders/', {
            'request_id': material_request.pk,
            'category_id': self.category.pk,
            'source': 'external',
            'store_name': 'Cebu Hardware',
            'or_number': 'OR-1',
            'lines': json.dumps([{
                'description': 'Cement', 'unit': 'bag', 'quantity': 1,
                'unit_price': '260.00',
            }]),
            'receipt_photo': png(),
        }, format='multipart')
        order = PurchaseOrder.objects.get(pk=created.data['id'])
        url = f'/api/v1/purchase-orders/{order.pk}/receipt/{order.receipt_file_name}'

        as_owner = self.client.get(url)
        self.act_as(self.engineer, Role.SITE_ENGINEER)
        as_engineer = self.client.get(url)
        self.act_as(self.accountant, Role.ACCOUNTANT)
        as_accountant = self.client.get(url)
        self.act_as(self.owner, Role.OWNER)
        wrong_name = self.client.get(f'/api/v1/purchase-orders/{order.pk}/receipt/other.png')

        self.assertEqual(as_owner.status_code, 200)
        self.assertEqual(as_owner['Cache-Control'], 'private, no-store')
        self.assertEqual(as_engineer.status_code, 404)
        self.assertEqual(as_accountant.status_code, 200)
        self.assertEqual(wrong_name.status_code, 404)


# --------------------------------------------------------------------------
# Deliveries and derived inventory
# --------------------------------------------------------------------------

class DeliveryTests(ProcurementCase):
    def setUp(self):
        super().setUp()
        _, response = self.place_order()
        self.order = PurchaseOrder.objects.get(pk=response.data['id'])
        self.line = self.order.items.get()

    def test_partial_then_full_receipt_updates_the_order_status(self):
        partial = self.confirm_delivery(self.order, [
            {'po_item_id': self.line.pk, 'received': 4, 'damaged': 1},
        ])
        self.assertEqual(partial.status_code, 201, partial.data)
        self.order.refresh_from_db()
        self.order.refresh_from_db()
        self.assertEqual(self.order.status, PurchaseOrderStatus.PARTIALLY_DELIVERED)

        rest = self.confirm_delivery(self.order, [
            {'po_item_id': self.line.pk, 'received': 6, 'damaged': 0},
        ])
        self.assertEqual(rest.status_code, 201, rest.data)
        self.order.refresh_from_db()
        self.assertEqual(self.order.status, PurchaseOrderStatus.DELIVERED)
        self.assertEqual(
            DeliveryItem.objects.filter(delivery__purchase_order=self.order).count(), 2,
        )
        self.assertEqual(
            sum(row.qty_received for row in DeliveryItem.objects.all()), Decimal('10.00'),
        )

    def test_cumulative_receipt_cannot_exceed_the_ordered_quantity(self):
        self.confirm_delivery(self.order, [
            {'po_item_id': self.line.pk, 'received': 7, 'damaged': 0},
        ])
        before = Delivery.objects.count()

        response = self.confirm_delivery(self.order, [
            {'po_item_id': self.line.pk, 'received': 4, 'damaged': 0},
        ])

        self.assertEqual(response.status_code, 400)
        self.assertEqual(response.data['detail'], 'Only 3 left to receive on this line.')
        self.assertEqual(Delivery.objects.count(), before)

    def test_receipt_refusals_write_nothing(self):
        before = (Delivery.objects.count(), DeliveryItem.objects.count())

        damaged = self.confirm_delivery(self.order, [
            {'po_item_id': self.line.pk, 'received': 2, 'damaged': 3},
        ])
        unknown = self.confirm_delivery(self.order, [
            {'po_item_id': 999999, 'received': 1, 'damaged': 0},
        ])
        empty = self.confirm_delivery(self.order, [
            {'po_item_id': self.line.pk, 'received': 0, 'damaged': 0},
        ])
        negative = self.confirm_delivery(self.order, [
            {'po_item_id': self.line.pk, 'received': -1, 'damaged': 0},
        ])
        duplicated = self.confirm_delivery(self.order, [
            {'po_item_id': self.line.pk, 'received': 1, 'damaged': 0},
            {'po_item_id': self.line.pk, 'received': 1, 'damaged': 0},
        ])

        self.assertEqual(damaged.data['detail'], 'Damaged cannot exceed received.')
        self.assertEqual(unknown.data['detail'], 'Unknown PO line.')
        self.assertEqual(empty.data['detail'], 'Enter the quantity received.')
        self.assertEqual(negative.data['detail'], 'Quantities cannot be negative.')
        self.assertEqual(duplicated.data['detail'], 'Each PO line can be received once per delivery.')
        for response in (damaged, unknown, empty, negative, duplicated):
            self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual((Delivery.objects.count(), DeliveryItem.objects.count()), before)

    def test_bad_receipt_photo_refuses_and_leaves_no_file_row(self):
        response = self.confirm_delivery(
            self.order,
            [{'po_item_id': self.line.pk, 'received': 1, 'damaged': 0}],
            files={'receipt_photo': SimpleUploadedFile(
                'receipt.png', b'not-a-png', content_type='image/png',
            )},
        )

        self.assertEqual(response.status_code, 400)
        self.assertEqual(Delivery.objects.count(), 0)

    def test_receipt_refuses_an_empty_payload_before_the_line_checks(self):
        # The mock checks "any received > 0" first, then per-line ids.
        response = self.confirm_delivery(self.order, [
            {'po_item_id': 999999, 'received': 0, 'damaged': 0},
        ])

        self.assertEqual(response.status_code, 400)
        self.assertEqual(response.data['detail'], 'Enter the quantity received.')

    def test_only_the_assigned_site_engineer_confirms(self):
        self.act_as(self.owner, Role.OWNER)
        as_owner = self.client.post(
            f'/api/v1/purchase-orders/{self.order.pk}/deliveries/',
            {'lines': json.dumps([{'po_item_id': self.line.pk, 'received': 1, 'damaged': 0}])},
            format='multipart',
        )
        self.act_as(self.admin, Role.ADMIN)
        as_admin = self.client.post(
            f'/api/v1/purchase-orders/{self.order.pk}/deliveries/',
            {'lines': json.dumps([{'po_item_id': self.line.pk, 'received': 1, 'damaged': 0}])},
            format='multipart',
        )
        self.act_as(self.other_engineer, Role.SITE_ENGINEER)
        cross = self.client.post(
            f'/api/v1/purchase-orders/{self.order.pk}/deliveries/',
            {'lines': json.dumps([{'po_item_id': self.line.pk, 'received': 1, 'damaged': 0}])},
            format='multipart',
        )

        self.assertEqual(as_owner.status_code, 403)
        self.assertEqual(as_admin.status_code, 403)
        self.assertEqual(
            as_owner.data['detail'],
            'Only the site engineer on this project confirms its deliveries.',
        )
        self.assertEqual(cross.status_code, 404)
        self.assertEqual(Delivery.objects.count(), 0)

    def test_a_delivered_order_has_nothing_left_to_receive(self):
        self.confirm_delivery(self.order, [
            {'po_item_id': self.line.pk, 'received': 10, 'damaged': 0},
        ])

        response = self.confirm_delivery(self.order, [
            {'po_item_id': self.line.pk, 'received': 1, 'damaged': 0},
        ])

        self.assertEqual(response.status_code, 400)
        self.assertEqual(
            response.data['detail'],
            'This PO is delivered; there is nothing to receive.',
        )

    def test_delivery_list_is_newest_first_with_its_order(self):
        self.confirm_delivery(self.order, [
            {'po_item_id': self.line.pk, 'received': 1, 'damaged': 0},
        ])
        self.act_as(self.engineer, Role.SITE_ENGINEER)

        response = self.client.get(f'/api/v1/deliveries/?project={self.project.pk}')

        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(len(response.data), 1)
        self.assertEqual(set(response.data[0]), {'delivery', 'order'})
        self.assertEqual(
            response.data[0]['delivery']['delivery']['purchase_order_id'], self.order.pk,
        )


class SiteInventoryTests(ProcurementCase):
    def test_inventory_is_received_minus_damaged_minus_approved_usage(self):
        material_request, response = self.place_order()
        order = PurchaseOrder.objects.get(pk=response.data['id'])
        line = order.items.get()
        self.confirm_delivery(order, [
            {'po_item_id': line.pk, 'received': 10, 'damaged': 2},
        ])

        report = DailyReport.objects.create(
            project=self.project, report_date=timezone.localdate(),
            weather='sunny', status=DailyReportStatus.DRAFT,
            submitted_by=self.engineer,
        )
        ReportMaterialUsage.objects.create(
            daily_report=report, material=self.cement, quantity=Decimal('5.00'),
        )
        draft_inventory = self.inventory()

        self.assertEqual(draft_inventory[0]['received'], '10.00')
        self.assertEqual(draft_inventory[0]['damaged'], '2.00')
        self.assertEqual(draft_inventory[0]['used'], '0.00')

        report.status = DailyReportStatus.APPROVED
        report.save(update_fields=['status'])
        approved_inventory = self.inventory()

        self.assertEqual(approved_inventory[0]['used'], '5.00')
        self.assertEqual(approved_inventory[0]['material_id'], self.cement.pk)
        self.assertEqual(approved_inventory[0]['name'], 'Portland Cement')

    def test_more_used_than_delivered_stays_negative(self):
        report = DailyReport.objects.create(
            project=self.project, report_date=timezone.localdate(),
            weather='sunny', status=DailyReportStatus.APPROVED,
            submitted_by=self.engineer,
        )
        ReportMaterialUsage.objects.create(
            daily_report=report, material=self.sand, quantity=Decimal('3.00'),
        )

        inventory = self.inventory()

        self.assertEqual(inventory[0]['received'], '0.00')
        self.assertEqual(inventory[0]['used'], '3.00')

    def inventory(self):
        self.act_as(self.engineer, Role.SITE_ENGINEER)
        response = self.client.get(f'/api/v1/projects/{self.project.pk}/site-inventory/')
        self.assertEqual(response.status_code, 200, response.data)
        return response.data

    def test_client_has_no_inventory_read(self):
        self.act_as(self.client_user, Role.CLIENT)
        response = self.client.get(f'/api/v1/projects/{self.project.pk}/site-inventory/')
        self.assertEqual(response.status_code, 403)


# --------------------------------------------------------------------------
# Cancellation
# --------------------------------------------------------------------------

class CancellationTests(ProcurementCase):
    def test_cancel_reopens_coverage_and_the_request_queue(self):
        material_request = self.make_request()
        item = self.add_item(material_request)
        _, response = self.place_order(material_request, covers_item_ids=[item.pk])
        order = PurchaseOrder.objects.get(pk=response.data['id'])

        self.act_as(self.owner, Role.OWNER)
        cancelled = self.client.post(f'/api/v1/purchase-orders/{order.pk}/cancel/')

        self.assertEqual(cancelled.status_code, 200, cancelled.data)
        self.assertEqual(cancelled.data['status'], 'cancelled')
        item.refresh_from_db()
        self.assertIsNone(item.purchase_order)
        material_request.refresh_from_db()
        self.assertEqual(material_request.status, MaterialRequestStatus.PENDING)
        order.refresh_from_db()
        self.assertEqual(order.pos_sync_status, PosSyncStatus.NOT_APPLICABLE)
        self.assertEqual(
            PosOutboxJob.objects.get(purchase_order=order).state,
            PosOutboxState.CANCELLED,
        )

    def test_cancel_refuses_once_anything_arrived(self):
        _, response = self.place_order()
        order = PurchaseOrder.objects.get(pk=response.data['id'])
        self.confirm_delivery(order, [
            {'po_item_id': order.items.get().pk, 'received': 1, 'damaged': 0},
        ])

        self.act_as(self.owner, Role.OWNER)
        refused = self.client.post(f'/api/v1/purchase-orders/{order.pk}/cancel/')

        self.assertEqual(refused.status_code, 400)
        self.assertEqual(refused.data['detail'], 'A PO with deliveries cannot be cancelled.')
        order.refresh_from_db()
        self.assertEqual(order.status, PurchaseOrderStatus.PARTIALLY_DELIVERED)

    def test_a_purchase_already_paid_at_the_store_cannot_be_cancelled(self):
        self.act_as(self.owner, Role.OWNER)
        material_request = self.make_request()
        created = self.client.post('/api/v1/purchase-orders/', {
            'request_id': material_request.pk,
            'category_id': self.category.pk,
            'source': 'external',
            'store_name': 'Cebu Hardware',
            'or_number': 'OR-2',
            'lines': json.dumps([{
                'description': 'Cement', 'unit': 'bag', 'quantity': 1,
                'unit_price': '260.00',
            }]),
            'receipt_photo': png(),
        }, format='multipart')
        order = PurchaseOrder.objects.get(pk=created.data['id'])

        refused = self.client.post(f'/api/v1/purchase-orders/{order.pk}/cancel/')

        self.assertEqual(refused.status_code, 400)
        self.assertEqual(
            refused.data['detail'],
            'A purchase already paid at the store cannot be cancelled.',
        )
        order.refresh_from_db()
        self.assertEqual(order.status, PurchaseOrderStatus.PURCHASED)

    def test_cancel_is_idempotent_and_role_checked(self):
        _, response = self.place_order()
        order = PurchaseOrder.objects.get(pk=response.data['id'])
        self.act_as(self.engineer, Role.SITE_ENGINEER)
        refused = self.client.post(f'/api/v1/purchase-orders/{order.pk}/cancel/')
        self.assertEqual(refused.status_code, 403)

        self.act_as(self.owner, Role.OWNER)
        first = self.client.post(f'/api/v1/purchase-orders/{order.pk}/cancel/')
        second = self.client.post(f'/api/v1/purchase-orders/{order.pk}/cancel/')

        self.assertEqual(first.status_code, 200)
        self.assertEqual(second.status_code, 200)
        self.assertEqual(second.data['status'], 'cancelled')

    def test_cancel_of_a_synced_order_keeps_a_close_intent(self):
        _, response = self.place_order()
        order = PurchaseOrder.objects.get(pk=response.data['id'])
        order.pos_sync_status = PosSyncStatus.SYNCED
        order.save(update_fields=['pos_sync_status'])

        self.act_as(self.owner, Role.OWNER)
        self.client.post(f'/api/v1/purchase-orders/{order.pk}/cancel/')

        self.assertTrue(PosOutboxJob.objects.filter(
            purchase_order=order, operation=PosOutboxOperation.CLOSE,
        ).exists())
        order.refresh_from_db()
        self.assertEqual(order.pos_sync_status, PosSyncStatus.SYNCED)


# --------------------------------------------------------------------------
# Advisory budget check
# --------------------------------------------------------------------------

class BudgetCheckTests(ProcurementCase):
    def test_owner_gets_budget_committed_and_request_cost(self):
        _, first = self.place_order()
        second = self.make_request()
        self.act_as(self.owner, Role.OWNER)
        self.client.post('/api/v1/purchase-orders/', {
            'request_id': second.pk,
            'category_id': self.category.pk,
            'source': 'own_store',
            'delivery_address': 'Site',
            'lines': [{
                'material_id': self.cement.pk, 'description': 'Cement',
                'unit': 'bag', 'quantity': 4, 'unit_price': '250.00',
            }],
        }, format='json')
        self.client.post(f'/api/v1/purchase-orders/{first.data["id"]}/cancel/')

        response = self.client.get(
            f'/api/v1/categories/{self.category.pk}/procurement-budget/?amount=1000'
        )

        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data['budget'], '400000.00')
        # The cancelled order is not committed; only the live 4 x 250 is.
        self.assertEqual(response.data['committed'], '1000.00')
        self.assertEqual(response.data['request_cost'], '1000.00')

    def test_amount_is_required_finite_and_never_a_float(self):
        self.act_as(self.owner, Role.OWNER)
        missing = self.client.get(f'/api/v1/categories/{self.category.pk}/procurement-budget/')
        nan = self.client.get(
            f'/api/v1/categories/{self.category.pk}/procurement-budget/?amount=NaN'
        )
        precise = self.client.get(
            f'/api/v1/categories/{self.category.pk}/procurement-budget/?amount=1.005'
        )

        self.assertEqual(missing.status_code, 400)
        self.assertEqual(missing.data['detail'], 'Enter the amount to check.')
        self.assertEqual(nan.status_code, 400)
        self.assertEqual(precise.status_code, 400)

    def test_budget_check_is_finance_only_and_scoped(self):
        for user, role in (
            (self.engineer, Role.SITE_ENGINEER),
            (self.admin, Role.ADMIN),
            (self.client_user, Role.CLIENT),
        ):
            self.act_as(user, role)
            response = self.client.get(
                f'/api/v1/categories/{self.category.pk}/procurement-budget/?amount=10'
            )
            self.assertEqual(response.status_code, 403, (role, response.data))

        self.act_as(self.other_owner, Role.OWNER)
        cross = self.client.get(
            f'/api/v1/categories/{self.category.pk}/procurement-budget/?amount=10'
        )
        self.assertEqual(cross.status_code, 404)

    def test_accountant_may_check_any_project_budget(self):
        self.act_as(self.accountant, Role.ACCOUNTANT)
        response = self.client.get(
            f'/api/v1/categories/{self.other_category.pk}/procurement-budget/?amount=0'
        )
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data['committed'], '0.00')


# --------------------------------------------------------------------------
# Concurrency: the receipt limit holds under a row lock
# --------------------------------------------------------------------------

class ReceiptConcurrencyTests(ProcurementFixtures, TransactionTestCase):
    """Two site engineers race for the last bags; only one receipt may win.

    `TransactionTestCase` on purpose: worker threads get their own database
    connection, which cannot see rows an `APITestCase` transaction has not
    committed — the first attempt proved that by answering `403` to both
    threads (no visible user roles).
    """

    client_class = APIClient

    # Like the migration tests: this class flushes the database, so restore the
    # serialized state afterwards or the next migration test deserialises stale
    # rows (duplicate key ... django_content_type).
    serialized_rollback = True

    def test_simultaneous_receipts_cannot_exceed_the_ordered_quantity(self):
        _, response = self.place_order()
        order = PurchaseOrder.objects.get(pk=response.data['id'])
        line = order.items.get()
        url = f'/api/v1/purchase-orders/{order.pk}/deliveries/'
        payload = {'lines': json.dumps([
            {'po_item_id': line.pk, 'received': 10, 'damaged': 0},
        ])}
        results = []
        barrier = threading.Barrier(2)

        def worker():
            client = APIClient()
            try:
                client.force_authenticate(user=self.engineer)
                client.credentials(HTTP_X_ACTIVE_ROLE=Role.SITE_ENGINEER)
                barrier.wait(timeout=10)
                results.append(client.post(url, payload, format='multipart').status_code)
            finally:
                connections.close_all()

        threads = [threading.Thread(target=worker) for _ in range(2)]
        for thread in threads:
            thread.start()
        for thread in threads:
            thread.join(timeout=30)

        self.assertEqual(sorted(results), [201, 400], results)
        self.assertEqual(
            sum(row.qty_received for row in DeliveryItem.objects.all()),
            Decimal('10.00'),
        )


class OrderCoverageConcurrencyTests(ProcurementFixtures, TransactionTestCase):
    """Two orders race to cover the same requested item; only one may win.

    `TransactionTestCase` for the same reason as the receipt race: the worker
    threads need rows another connection has committed, and the coverage
    re-check must happen **inside** the atomic block, under the request lock.
    """

    client_class = APIClient

    # This class flushes the database; restore the serialized state afterwards.
    serialized_rollback = True

    def test_simultaneous_orders_cannot_both_cover_the_same_item(self):
        material_request = self.make_request()
        item = self.add_item(material_request)
        payload = {
            'request_id': material_request.pk,
            'category_id': self.category.pk,
            'source': 'own_store',
            'delivery_address': 'Gate 2, Tower A site',
            'lines': [{
                'material_id': self.cement.pk, 'description': 'Portland Cement',
                'unit': 'bag', 'quantity': 10, 'unit_price': '250.00',
            }],
            'covers_item_ids': [item.pk],
        }
        results = []
        barrier = threading.Barrier(2)

        def worker():
            client = APIClient()
            try:
                client.force_authenticate(user=self.owner)
                client.credentials(HTTP_X_ACTIVE_ROLE=Role.OWNER)
                barrier.wait(timeout=10)
                results.append(
                    client.post(
                        '/api/v1/purchase-orders/', payload, format='json',
                    ).status_code
                )
            finally:
                connections.close_all()

        threads = [threading.Thread(target=worker) for _ in range(2)]
        for thread in threads:
            thread.start()
        for thread in threads:
            thread.join(timeout=30)

        self.assertEqual(sorted(results), [201, 400], results)
        orders = list(PurchaseOrder.objects.all())
        self.assertEqual(len(orders), 1, orders)
        covering = MaterialRequestItem.objects.filter(purchase_order__isnull=False)
        self.assertEqual([row.pk for row in covering], [item.pk])
        # Only the winner left an import intent (+ its audit and notification).
        self.assertEqual(PosOutboxJob.objects.count(), 1)
        self.assertEqual(PosOutboxJob.objects.get().purchase_order_id, orders[0].pk)

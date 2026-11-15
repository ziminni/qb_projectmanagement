"""Live reads from the store: the catalogue (price + stock status) and the debt.

The store owns the price and the debt record; CPMS only asks. Every test fakes the
POS client at the one seam the views use, so no network is involved.
"""

from unittest import mock

from rest_framework.test import APITestCase

from ..users.models import Role
from .pos_client import PosConfigError, PosNotFound, PosTransportError
from .tests_procurement import ProcurementFixtures

CATALOG_URL = '/api/v1/pos-catalog/'
SEAM = 'apps.requisitions.pos_live_views.get_pos_client'


class FakePos:
    def __init__(self, materials=None, payables=None):
        self.materials = materials
        self.payables = payables
        self.payable_calls = []

    def _answer(self, value):
        if isinstance(value, BaseException):
            raise value
        return value

    def list_materials(self):
        return self._answer(self.materials)

    def project_payables(self, cpms_project_id):
        self.payable_calls.append(cpms_project_id)
        return self._answer(self.payables)


ROWS = [
    {'code': 'CEM-40KG', 'product': 'Portland Cement 40kg', 'unit': 'BAG',
     'price': '275.00', 'stock_status': 'low'},
    {'code': 'NAIL-4', 'product': 'Common Nail 4in', 'unit': 'KG',
     'price': '95.50', 'stock_status': 'in_stock'},
]


class PosCatalogTests(ProcurementFixtures, APITestCase):
    def get(self, pos, user=None, role=Role.OWNER):
        self.act_as(user or self.owner, role)
        with mock.patch(SEAM, return_value=pos):
            return self.client.get(CATALOG_URL)

    def test_owner_sees_the_stores_price_and_stock_with_the_cpms_material_id(self):
        response = self.get(FakePos(materials=ROWS))

        self.assertEqual(response.status_code, 200, response.data)
        by_code = {row['code']: row for row in response.data}
        cement = by_code['CEM-40KG']
        self.assertEqual(cement['material_id'], self.cement.pk)
        self.assertEqual(cement['price'], '275.00')
        self.assertEqual(cement['stock_status'], 'low')
        self.assertEqual(cement['unit'], 'BAG')
        # A store item no CPMS material points at cannot be ordered yet.
        self.assertIsNone(by_code['NAIL-4']['material_id'])

    def test_a_row_carries_only_the_allowed_keys(self):
        leaky = [dict(ROWS[0], cost='1.00', on_hand='99', id=5)]

        [row] = self.get(FakePos(materials=leaky)).data

        self.assertEqual(
            set(row),
            {'code', 'product', 'unit', 'price', 'stock_status', 'material_id'},
        )

    def test_an_unreadable_price_is_unknown_never_zero(self):
        rows = [dict(ROWS[0], price='free'), dict(ROWS[1], price=None, stock_status='??')]

        data = self.get(FakePos(materials=rows)).data

        self.assertIsNone(data[0]['price'])
        self.assertIsNone(data[1]['price'])
        self.assertIsNone(data[1]['stock_status'])

    def test_only_the_active_owner_reads_the_store_catalogue(self):
        for user, role in (
            (self.accountant, Role.ACCOUNTANT),
            (self.engineer, Role.SITE_ENGINEER),
            (self.client_user, Role.CLIENT),
            (self.admin, Role.ADMIN),
        ):
            with self.subTest(role=role):
                pos = FakePos(materials=ROWS)
                self.assertEqual(self.get(pos, user, role).status_code, 403)

    def test_a_store_that_cannot_be_reached_is_a_502_without_internals(self):
        response = self.get(FakePos(materials=PosTransportError('boom 10.0.0.5:8000')))

        self.assertEqual(response.status_code, 502)
        self.assertNotIn('10.0.0.5', str(response.data))
        self.assertIn('store', response.data['detail'].lower())

    def test_a_store_that_is_not_configured_is_a_503(self):
        response = self.get(FakePos(materials=PosConfigError('no url')))

        self.assertEqual(response.status_code, 503)


class PosPayablesTests(ProcurementFixtures, APITestCase):
    def url(self, project=None):
        return f'/api/v1/projects/{(project or self.project).pk}/pos-payables/'

    def get(self, pos, user=None, role=Role.OWNER, project=None):
        self.act_as(user or self.owner, role)
        with mock.patch(SEAM, return_value=pos):
            return self.client.get(self.url(project))

    def test_owner_reads_what_the_project_owes_the_store(self):
        pos = FakePos(payables={'total': '2750.00', 'paid': '500.00', 'balance': '2250.00'})

        response = self.get(pos)

        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data['total'], '2750.00')
        self.assertEqual(response.data['paid'], '500.00')
        self.assertEqual(response.data['balance'], '2250.00')
        self.assertTrue(response.data['at_store'])
        self.assertIn('fetched_at', response.data)
        # The store knows the project by its CPMS code.
        self.assertEqual(pos.payable_calls, ['PRJ-A'])

    def test_the_accountant_reads_it_too(self):
        pos = FakePos(payables={'total': '1.00', 'paid': '0.00', 'balance': '1.00'})

        self.assertEqual(self.get(pos, self.accountant, Role.ACCOUNTANT).status_code, 200)

    def test_the_site_engineer_and_client_never_see_the_debt(self):
        for user, role in (
            (self.engineer, Role.SITE_ENGINEER),
            (self.client_user, Role.CLIENT),
            (self.admin, Role.ADMIN),
        ):
            with self.subTest(role=role):
                pos = FakePos(payables={'total': '1.00', 'paid': '0.00', 'balance': '1.00'})
                self.assertEqual(self.get(pos, user, role).status_code, 403)
                self.assertEqual(pos.payable_calls, [], 'the store must not even be asked')

    def test_a_project_outside_the_owners_scope_is_a_404(self):
        pos = FakePos(payables={'total': '1.00', 'paid': '0.00', 'balance': '1.00'})

        response = self.get(pos, project=self.other_project)

        self.assertEqual(response.status_code, 404)
        self.assertEqual(pos.payable_calls, [])

    def test_a_project_the_store_has_never_seen_owes_nothing_yet(self):
        pos = FakePos(payables=PosNotFound('PROJECT_NOT_FOUND', 404, 'unknown'))

        response = self.get(pos)

        self.assertEqual(response.status_code, 200)
        self.assertFalse(response.data['at_store'])
        self.assertEqual(response.data['balance'], '0.00')

    def test_an_unreadable_answer_is_a_502_never_a_made_up_zero(self):
        for bad in (
            {'total': 'abc', 'paid': '0.00', 'balance': '0.00'},
            {'total': '1.00', 'paid': None, 'balance': '1.00'},
            {'total': '1.00'},
        ):
            with self.subTest(bad=bad):
                self.assertEqual(self.get(FakePos(payables=bad)).status_code, 502)

    def test_a_store_that_cannot_be_reached_is_a_502(self):
        response = self.get(FakePos(payables=PosTransportError('down')))

        self.assertEqual(response.status_code, 502)

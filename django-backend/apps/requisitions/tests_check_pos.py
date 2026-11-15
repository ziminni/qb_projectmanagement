# pyright: reportAttributeAccessIssue=false
"""`manage.py check_pos`: one command that says whether CPMS can use the store."""

from io import StringIO
from unittest import mock

from django.core.management import call_command
from django.core.management.base import CommandError
from django.test import TestCase, override_settings

from ..master_data.models import MaterialItem, Supplier
from .pos_client import PosAuthError

CLIENT = 'apps.requisitions.management.commands.check_pos.get_pos_client'
SETTINGS = {
    'POS_API_BASE_URL': 'https://shop.trycloudflare.com',
    'POS_API_GATEWAY_HEADER_NAME': 'X-QB-Gateway-Key',
    'POS_API_GATEWAY_HEADER_VALUE': 'secret-key-value',
}


@override_settings(**SETTINGS)
class CheckPosTests(TestCase):
    def setUp(self):
        self.store = Supplier.objects.create(name='Our store', is_own_store=True, pos_payer_id=4)
        MaterialItem.objects.create(name='Cement', unit='bag', pos_code='QB000001-7')
        self.client = mock.Mock()
        self.client.list_customers.return_value = [{'id': 4, 'name': 'Dela Cruz Construction'}]
        self.client.list_materials.return_value = [{'code': 'QB000001-7'}]

    def run_check(self):
        out = StringIO()
        with mock.patch(CLIENT, return_value=self.client):
            call_command('check_pos', stdout=out)
        return out.getvalue()

    def test_everything_ready(self):
        out = self.run_check()
        self.assertIn('https://shop.trycloudflare.com', out)
        self.assertIn('gateway key: set', out)
        self.assertIn('Dela Cruz Construction', out)
        self.assertIn('1 of 1', out)
        self.assertIn('READY', out)
        self.assertNotIn('secret-key-value', out)

    def test_unreachable_store_fails_with_the_reason(self):
        self.client.list_customers.side_effect = PosAuthError('The store refused the sign-in.')
        with self.assertRaises(CommandError) as caught:
            self.run_check()
        self.assertIn('refused the sign-in', str(caught.exception))

    def test_a_payer_pos_does_not_list_fails(self):
        self.store.pos_payer_id = 1788
        self.store.save()
        with self.assertRaises(CommandError) as caught:
            self.run_check()
        self.assertIn('1788', str(caught.exception))

    def test_a_material_code_pos_does_not_sell_fails(self):
        self.client.list_materials.return_value = []
        with self.assertRaises(CommandError) as caught:
            self.run_check()
        self.assertIn('QB000001-7', str(caught.exception))

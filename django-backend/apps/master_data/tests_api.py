"""Phase 1.2 wire-contract tests: master lists (materials, suppliers, trades, equipment).

Every check in `planning/backend-integration/contracts/phase-1-auth-and-admin.md`
under "Company, settings and master lists (task 1.2)" has a test here.
"""

# Pyright here runs without django-stubs, so model managers are untyped.
# pyright: reportAttributeAccessIssue=false, reportArgumentType=false, reportOptionalMemberAccess=false

from unittest import mock

from rest_framework.test import APITestCase

from ..users.models import AuditLog, Role
from ..users.tests import make_user
from .serializers import MaterialItemSerializer, SupplierSerializer, TradeSerializer

MATERIALS_URL = '/api/v1/master-data/materials/'
SUPPLIERS_URL = '/api/v1/master-data/suppliers/'
TRADES_URL = '/api/v1/master-data/trades/'
EQUIPMENT_URL = '/api/v1/master-data/equipment/'
LISTS = (MATERIALS_URL, SUPPLIERS_URL, TRADES_URL, EQUIPMENT_URL)


def material(**overrides):
    payload = {'name': 'Portland cement 40 kg', 'unit': 'bag',
               'default_unit_cost': 260}
    payload.update(overrides)
    return payload


def supplier(**overrides):
    payload = {'name': 'Batangas Steel Supply', 'contact_person': 'Rico Tan',
               'phone': '043 555 0161', 'address': 'Batangas City'}
    payload.update(overrides)
    return payload


def equipment(**overrides):
    payload = {'name': 'One-bagger concrete mixer', 'ownership': 'owned',
               'rate': 800, 'rate_unit': 'day'}
    payload.update(overrides)
    return payload


class MasterDataTestCase(APITestCase):
    def setUp(self):
        # One user per role: a test that signs in and out of the same role
        # (to check redaction from both sides) must not try to create it twice.
        self._users = {}

    def sign_in(self, user, role=None):
        self.client.force_authenticate(user=user)
        if role:
            self.client.credentials(HTTP_X_ACTIVE_ROLE=role)
        return user

    def user_in(self, role, email=None):
        if email is None and role in self._users:
            return self._users[role]
        user = make_user(email or f'{role}@example.com', [role])
        self._users.setdefault(role, user)
        return user

    def sign_in_role(self, role):
        return self.sign_in(self.user_in(role), role)

    def create(self, url, payload):
        response = self.client.post(url, payload, format='json')
        self.assertIn(response.status_code, (200, 201), response.data)
        return response.data


class AccessTests(MasterDataTestCase):
    def test_the_client_role_has_no_master_data_access(self):
        self.sign_in_role(Role.CLIENT)

        for url in LISTS:
            self.assertEqual(self.client.get(url).status_code, 403, url)

    def test_staff_roles_read_every_list(self):
        for role in (Role.ADMIN, Role.OWNER, Role.ACCOUNTANT, Role.SITE_ENGINEER):
            self.sign_in_role(role)

            for url in LISTS:
                response = self.client.get(url)
                self.assertEqual(response.status_code, 200, (role, url))

    def test_field_staff_and_the_accountant_cannot_write(self):
        for role in (Role.SITE_ENGINEER, Role.ACCOUNTANT, Role.CLIENT):
            self.sign_in_role(role)

            attempts = [
                (MATERIALS_URL, material()),
                (SUPPLIERS_URL, supplier()),
                (TRADES_URL, {'name': 'Mason'}),
                (EQUIPMENT_URL, equipment()),
            ]
            for url, payload in attempts:
                self.assertEqual(
                    self.client.post(url, payload, format='json').status_code,
                    403,
                    (role, url),
                )

    def test_both_admin_and_the_project_manager_may_write(self):
        for role in (Role.ADMIN, Role.OWNER):
            self.sign_in_role(role)

            self.create(MATERIALS_URL, material(name=f'Material for {role}'))
            self.create(SUPPLIERS_URL, supplier(name=f'Supplier for {role}'))
            self.create(TRADES_URL, {'name': f'Trade for {role}'})
            self.create(EQUIPMENT_URL, equipment(name=f'Equipment for {role}'))

    def test_a_dangling_active_role_is_refused_and_unknown_role_on_write(self):
        self.sign_in(self.user_in(Role.OWNER), Role.ADMIN)

        response = self.client.post(MATERIALS_URL, material(), format='json')

        self.assertEqual(response.status_code, 403)
        self.assertEqual(response.data['code'], 'ROLE_NOT_HELD')


class MaterialTests(MasterDataTestCase):
    def test_a_material_round_trips_with_a_null_store_sku_and_pos_code(self):
        self.sign_in_role(Role.OWNER)

        created = self.create(MATERIALS_URL, material())
        fetched = self.client.get(f'{MATERIALS_URL}{created["id"]}/')

        self.assertEqual(fetched.status_code, 200, fetched.data)
        self.assertEqual(
            set(fetched.data),
            {'id', 'name', 'unit', 'default_unit_cost', 'store_sku', 'pos_code',
             'created_at', 'updated_at'},
        )
        self.assertEqual(fetched.data['unit'], 'bag')
        self.assertIsNone(fetched.data['store_sku'])
        self.assertIsNone(fetched.data['pos_code'])

    def test_a_blank_store_sku_is_serialized_as_null(self):
        self.sign_in_role(Role.OWNER)

        created = self.client.post(MATERIALS_URL, material(store_sku=''),
                                   format='json')

        self.assertEqual(created.status_code, 201, created.data)
        self.assertIsNone(created.data['store_sku'])

    def test_the_pos_code_and_store_sku_are_stored_and_returned(self):
        self.sign_in_role(Role.ADMIN)

        created = self.create(MATERIALS_URL, material(
            store_sku='CEM-40', pos_code='QB000001-7'))

        self.assertEqual(created['store_sku'], 'CEM-40')
        self.assertEqual(created['pos_code'], 'QB000001-7')

    def test_names_are_trimmed_and_unique_case_insensitively(self):
        self.sign_in_role(Role.OWNER)
        self.create(MATERIALS_URL, material(name='Portland cement 40 kg'))

        for name in ('portland CEMENT 40 kg', '  Portland cement 40 kg  '):
            response = self.client.post(MATERIALS_URL, material(name=name),
                                        format='json')

            self.assertEqual(response.status_code, 400, name)
            self.assertEqual(response.data['detail'],
                             'A material with this name already exists.')

        stored = self.client.post(MATERIALS_URL, material(name='  Gravel 3/4"  '),
                                  format='json')
        self.assertEqual(stored.data['name'], 'Gravel 3/4"')

    def test_a_duplicate_own_row_is_allowed_on_update(self):
        self.sign_in_role(Role.OWNER)
        created = self.create(MATERIALS_URL, material())

        response = self.client.patch(f'{MATERIALS_URL}{created["id"]}/',
                                     {'name': 'Portland cement 40 kg'},
                                     format='json')

        self.assertEqual(response.status_code, 200, response.data)

    def test_required_and_negative_amount_messages(self):
        self.sign_in_role(Role.OWNER)

        cases = [
            (material(name='   '), 'Enter the material name.'),
            (material(unit=''), 'Enter the unit.'),
            (material(default_unit_cost=-1), 'The unit cost cannot be negative.'),
        ]
        for payload, message in cases:
            response = self.client.post(MATERIALS_URL, payload, format='json')

            self.assertEqual(response.status_code, 400, (payload, response.data))
            self.assertEqual(response.data['detail'], message, payload)

    def test_a_material_cannot_be_deleted(self):
        self.sign_in_role(Role.OWNER)
        created = self.create(MATERIALS_URL, material())

        response = self.client.delete(f'{MATERIALS_URL}{created["id"]}/')

        self.assertEqual(response.status_code, 405)

    def test_reads_are_ordered_by_name(self):
        self.sign_in_role(Role.OWNER)
        for name in ('Washed sand', 'CHB 4"', 'Gravel 3/4"'):
            self.create(MATERIALS_URL, material(name=name))

        response = self.client.get(MATERIALS_URL)

        self.assertEqual([row['name'] for row in response.data['results']],
                         ['CHB 4"', 'Gravel 3/4"', 'Washed sand'])

    def test_a_create_and_an_update_each_write_one_audit_row(self):
        admin = self.sign_in_role(Role.ADMIN)

        created = self.create(MATERIALS_URL, material())
        self.client.patch(f'{MATERIALS_URL}{created["id"]}/',
                          {'name': 'Portland cement 50 kg'}, format='json')

        rows = AuditLog.objects.filter(entity='material').order_by('created_at')
        self.assertEqual([row.action for row in rows],
                         ['material_created', 'material_updated'])
        self.assertEqual(rows[0].entity_id, created['id'])
        self.assertEqual(rows[0].user_id, admin.pk)
        self.assertEqual(rows[1].details, {'name': 'Portland cement 50 kg'})

    def test_a_refusal_writes_no_audit_row(self):
        self.sign_in_role(Role.ADMIN)

        self.client.post(MATERIALS_URL, material(unit=''), format='json')

        self.assertEqual(AuditLog.objects.filter(entity='material').count(), 0)


class DuplicateNameRaceTests(MasterDataTestCase):
    """A lost duplicate-name race surfaces the mock's refusal, not a 500.

    The race is simulated by skipping the serializer's pre-check: that is what a
    concurrent request sees (no duplicate yet) before the database's unique index
    answers. The response and the audit trail must match a refused save.
    """

    @staticmethod
    def without_name_precheck(serializer):
        return mock.patch.object(serializer, 'validate_name',
                                 lambda self, value: value)

    def test_a_concurrent_duplicate_create_is_refused_and_writes_no_audit_row(self):
        cases = (
            (MATERIALS_URL, lambda: material(), MaterialItemSerializer,
             'material', 'A material with this name already exists.'),
            (SUPPLIERS_URL, lambda: supplier(), SupplierSerializer,
             'supplier', 'A supplier with this name already exists.'),
            (TRADES_URL, lambda: {'name': 'Mason'}, TradeSerializer,
             'trade', 'This trade is already listed.'),
        )
        self.sign_in_role(Role.OWNER)

        for url, payload, serializer, entity, message in cases:
            self.create(url, payload())
            before = AuditLog.objects.filter(entity=entity).count()

            with self.without_name_precheck(serializer):
                response = self.client.post(url, payload(), format='json')

            self.assertEqual(response.status_code, 400, (entity, response.data))
            self.assertEqual(response.data['detail'], message, entity)
            self.assertEqual(AuditLog.objects.filter(entity=entity).count(),
                             before, entity)

    def test_a_concurrent_duplicate_rename_is_refused(self):
        self.sign_in_role(Role.OWNER)
        self.create(MATERIALS_URL, material(name='Portland cement 40 kg'))
        second = self.create(MATERIALS_URL, material(name='Gravel 3/4"'))

        with self.without_name_precheck(MaterialItemSerializer):
            response = self.client.patch(
                f'{MATERIALS_URL}{second["id"]}/',
                {'name': 'Portland cement 40 kg'}, format='json')

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(response.data['detail'],
                         'A material with this name already exists.')
        self.assertEqual(AuditLog.objects.filter(
            entity='material', action='material_updated').count(), 0)


class PriceRedactionTests(MasterDataTestCase):
    def test_the_unit_cost_is_zero_for_admin_and_field_staff_and_real_for_finance(self):
        self.sign_in_role(Role.OWNER)
        created = self.create(MATERIALS_URL, material(default_unit_cost=260))

        expectations = {
            Role.OWNER: 260.0,
            Role.ACCOUNTANT: 260.0,
            Role.ADMIN: 0.0,
            Role.SITE_ENGINEER: 0.0,
        }
        for role, expected in expectations.items():
            self.sign_in_role(role)

            response = self.client.get(f'{MATERIALS_URL}{created["id"]}/')

            self.assertEqual(float(response.data['default_unit_cost']), expected,
                             role)

    def test_the_equipment_rate_is_zero_for_admin_and_real_for_finance(self):
        self.sign_in_role(Role.OWNER)
        created = self.create(EQUIPMENT_URL, equipment(rate=800))

        for role, expected in {Role.OWNER: 800.0, Role.ADMIN: 0.0,
                               Role.SITE_ENGINEER: 0.0}.items():
            self.sign_in_role(role)

            response = self.client.get(f'{EQUIPMENT_URL}{created["id"]}/')

            self.assertEqual(float(response.data['rate']), expected, role)

    def test_a_non_finance_write_never_changes_a_stored_price(self):
        self.sign_in_role(Role.OWNER)
        created = self.create(MATERIALS_URL, material(default_unit_cost=260))

        self.sign_in_role(Role.ADMIN)
        self.client.patch(f'{MATERIALS_URL}{created["id"]}/',
                          {'name': 'Cement', 'default_unit_cost': 1},
                          format='json')

        self.sign_in_role(Role.OWNER)
        fetched = self.client.get(f'{MATERIALS_URL}{created["id"]}/')
        self.assertEqual(float(fetched.data['default_unit_cost']), 260.0)
        self.assertEqual(fetched.data['name'], 'Cement')

    def test_a_non_finance_create_stores_zero_rather_than_the_sent_price(self):
        self.sign_in_role(Role.ADMIN)

        created = self.create(MATERIALS_URL, material(default_unit_cost=999))

        self.assertIsNotNone(created['id'])
        self.sign_in_role(Role.OWNER)
        fetched = self.client.get(f'{MATERIALS_URL}{created["id"]}/')
        self.assertEqual(float(fetched.data['default_unit_cost']), 0.0)


class SupplierTests(MasterDataTestCase):
    def test_a_supplier_round_trips_with_own_store_and_pos_payer(self):
        self.sign_in_role(Role.OWNER)

        created = self.create(SUPPLIERS_URL, supplier(
            name='BuildRight Hardware (own store)', is_own_store=True,
            pos_payer_id=42))
        fetched = self.client.get(f'{SUPPLIERS_URL}{created["id"]}/')

        self.assertEqual(
            set(fetched.data),
            {'id', 'name', 'contact_person', 'phone', 'address', 'is_own_store',
             'pos_payer_id', 'created_at', 'updated_at'},
        )
        self.assertTrue(fetched.data['is_own_store'])
        self.assertEqual(fetched.data['pos_payer_id'], 42)

    def test_is_own_store_defaults_to_false_and_the_payer_stays_null(self):
        self.sign_in_role(Role.OWNER)

        created = self.create(SUPPLIERS_URL, supplier())

        self.assertFalse(created['is_own_store'])
        self.assertIsNone(created['pos_payer_id'])

    def test_the_own_store_comes_first_then_names(self):
        self.sign_in_role(Role.OWNER)
        self.create(SUPPLIERS_URL, supplier(name='Batangas Steel Supply'))
        self.create(SUPPLIERS_URL, supplier(name='Lipa Aggregates Trading'))
        self.create(SUPPLIERS_URL, supplier(name='BuildRight Hardware',
                                            is_own_store=True))
        self.create(SUPPLIERS_URL, supplier(name='Southern Roofing Corp.'))

        response = self.client.get(SUPPLIERS_URL)

        self.assertEqual(
            [row['name'] for row in response.data['results']],
            ['BuildRight Hardware', 'Batangas Steel Supply',
             'Lipa Aggregates Trading', 'Southern Roofing Corp.'],
        )

    def test_duplicate_supplier_names_are_refused_with_the_mock_text(self):
        self.sign_in_role(Role.OWNER)
        self.create(SUPPLIERS_URL, supplier())

        response = self.client.post(SUPPLIERS_URL,
                                    supplier(name='  batangas steel supply '),
                                    format='json')

        self.assertEqual(response.status_code, 400)
        self.assertEqual(response.data['detail'],
                         'A supplier with this name already exists.')

    def test_a_pos_payer_id_outside_the_bigint_range_is_refused(self):
        self.sign_in_role(Role.OWNER)
        biggest = self.create(SUPPLIERS_URL, supplier(
            name='Big payer id store', pos_payer_id=2**63 - 1))
        self.assertEqual(biggest['pos_payer_id'], 2**63 - 1)

        created = self.client.post(SUPPLIERS_URL, supplier(
            name='Overflowing payer id store', pos_payer_id=2**63), format='json')
        patched = self.client.patch(f'{SUPPLIERS_URL}{biggest["id"]}/',
                                    {'pos_payer_id': 2**63}, format='json')

        for response in (created, patched):
            self.assertEqual(response.status_code, 400, response.data)
            self.assertEqual(
                response.data['detail'],
                'Ensure this value is less than or equal to 9223372036854775807.',
            )

    def test_the_supplier_name_is_required(self):
        self.sign_in_role(Role.OWNER)

        response = self.client.post(SUPPLIERS_URL, supplier(name=' '),
                                    format='json')

        self.assertEqual(response.status_code, 400)
        self.assertEqual(response.data['detail'], 'Enter the supplier name.')

    def test_a_supplier_cannot_be_deleted(self):
        self.sign_in_role(Role.OWNER)
        created = self.create(SUPPLIERS_URL, supplier())

        self.assertEqual(
            self.client.delete(f'{SUPPLIERS_URL}{created["id"]}/').status_code,
            405,
        )


class TradeTests(MasterDataTestCase):
    def test_a_trade_round_trips_and_is_ordered_by_name(self):
        self.sign_in_role(Role.OWNER)
        for name in ('Mason', 'Carpenter', 'Tile setter'):
            self.create(TRADES_URL, {'name': name})

        response = self.client.get(TRADES_URL)

        self.assertEqual([row['name'] for row in response.data['results']],
                         ['Carpenter', 'Mason', 'Tile setter'])

    def test_a_duplicate_trade_is_refused_with_the_mock_text(self):
        self.sign_in_role(Role.OWNER)
        self.create(TRADES_URL, {'name': 'Mason'})

        response = self.client.post(TRADES_URL, {'name': 'mason '}, format='json')

        self.assertEqual(response.status_code, 400)
        self.assertEqual(response.data['detail'], 'This trade is already listed.')

    def test_the_trade_name_is_required(self):
        self.sign_in_role(Role.OWNER)

        response = self.client.post(TRADES_URL, {'name': ''}, format='json')

        self.assertEqual(response.status_code, 400)
        self.assertEqual(response.data['detail'], 'Enter the trade name.')

    def test_a_trade_is_deleted_and_audited(self):
        admin = self.sign_in_role(Role.ADMIN)
        created = self.create(TRADES_URL, {'name': 'Welder'})

        response = self.client.delete(f'{TRADES_URL}{created["id"]}/')

        self.assertEqual(response.status_code, 204)
        self.assertEqual(
            self.client.get(f'{TRADES_URL}{created["id"]}/').status_code, 404)

        rows = AuditLog.objects.filter(entity='trade').order_by('created_at', 'id')
        self.assertEqual([row.action for row in rows],
                         ['trade_created', 'trade_deleted'])
        self.assertEqual(rows[1].entity_id, created['id'])
        self.assertEqual(rows[1].user_id, admin.pk)
        self.assertEqual(rows[1].details, {'name': 'Welder'})

    def test_field_staff_cannot_delete_a_trade(self):
        self.sign_in_role(Role.OWNER)
        created = self.create(TRADES_URL, {'name': 'Welder'})

        self.sign_in_role(Role.SITE_ENGINEER)
        response = self.client.delete(f'{TRADES_URL}{created["id"]}/')

        self.assertEqual(response.status_code, 403)
        self.assertEqual(
            self.client.get(f'{TRADES_URL}{created["id"]}/').status_code, 200)


class EquipmentTests(MasterDataTestCase):
    def test_equipment_round_trips_with_both_enums(self):
        self.sign_in_role(Role.OWNER)

        created = self.create(EQUIPMENT_URL, equipment(
            name='Backhoe', ownership='rented', rate=1800, rate_unit='hour'))
        fetched = self.client.get(f'{EQUIPMENT_URL}{created["id"]}/')

        self.assertEqual(
            set(fetched.data),
            {'id', 'name', 'ownership', 'rate', 'rate_unit', 'created_at',
             'updated_at'},
        )
        self.assertEqual(fetched.data['ownership'], 'rented')
        self.assertEqual(fetched.data['rate_unit'], 'hour')

    def test_an_unknown_enum_value_is_refused(self):
        self.sign_in_role(Role.OWNER)

        response = self.client.post(EQUIPMENT_URL,
                                    equipment(ownership='leased'),
                                    format='json')

        self.assertEqual(response.status_code, 400, response.data)
        self.assertIn('not a valid choice', response.data['detail'])

    def test_required_name_and_rate_messages(self):
        self.sign_in_role(Role.OWNER)

        cases = [
            (equipment(name='  '), 'Enter the equipment name.'),
            (equipment(rate=-5), 'The rate cannot be negative.'),
        ]
        for payload, message in cases:
            response = self.client.post(EQUIPMENT_URL, payload, format='json')

            self.assertEqual(response.status_code, 400, (payload, response.data))
            self.assertEqual(response.data['detail'], message, payload)

    def test_duplicate_equipment_names_are_accepted_like_the_mock(self):
        self.sign_in_role(Role.OWNER)

        first = self.client.post(EQUIPMENT_URL, equipment(), format='json')
        second = self.client.post(EQUIPMENT_URL, equipment(), format='json')

        self.assertEqual(first.status_code, 201, first.data)
        self.assertEqual(second.status_code, 201, second.data)

    def test_equipment_cannot_be_deleted(self):
        self.sign_in_role(Role.OWNER)
        created = self.create(EQUIPMENT_URL, equipment())

        self.assertEqual(
            self.client.delete(f'{EQUIPMENT_URL}{created["id"]}/').status_code,
            405,
        )

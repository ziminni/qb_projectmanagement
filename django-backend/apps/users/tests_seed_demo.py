"""Task 5.1 — the `seed_demo` command reproduces `MockData`, safely and idempotently.

Contract proved here:
1. a second run creates no duplicate rows;
2. it refuses to run unless `DEBUG` is on or `--i-know-this-is-demo` is passed;
3. every demo account logs in through the real login endpoint with the mock
   password, including the active-role (`X-Active-Role`) rules for the account
   that holds two roles;
4. every mapped `pos_code` is a real POS selling-unit barcode (`QB000001-7` …),
   matched to the same product and unit, and no unmapped material invents one;
5. `--pos-payer-id` sets the own-store payer, is validated, and a null payer
   prints the operator notice;
6. no password is ever printed;
7. `--reset` removes only the rows the seed itself created.
"""

# Pyright here runs without django-stubs, so model managers are untyped.
# pyright: reportAttributeAccessIssue=false, reportArgumentType=false

from decimal import Decimal
from io import StringIO
from unittest import mock

from django.core.cache import cache
from django.core.management import call_command
from django.core.management.base import CommandError
from django.test import TestCase, override_settings
from rest_framework.test import APIClient, APITestCase

from ..company.models import Company, CompanySettings
from ..labor.models import Attendance, Worker
from ..master_data.models import EquipmentItem, MaterialItem, Supplier, Trade
from ..projects.models import Category, Project, ProjectAssignment, Todo
from .models import Role, User

DEMO_PASSWORD = 'password123'  # noqa: S105 - the documented demo password
OUTSIDER_PASSWORD = 'nope-nope-1'  # noqa: S105 - not a credential, a throwaway
SEED_FLAG = '--i-know-this-is-demo'
LOGIN_URL = '/api/v1/auth/login/'
PROJECTS_URL = '/api/v1/projects/'

# MockData / MockCompanyData counts.
DEMO_EMAILS = [
    'maria@example.ph',
    'ramon@example.ph',
    'ana@example.ph',
    'liza@example.ph',
    'mark@example.ph',
    'elena@example.ph',
]
PROJECT_CODES = ['QB-2026-014', 'QB-2026-018', 'QB-2026-021', 'QB-2026-025']

# What POS's own `seed_demo` derives for a selling unit: `QB{id:06}-{check digit}`.
POS_CODE_PATTERN = r'^QB\d{6}-\d$'
# The biggest id `Supplier.pos_payer_id` (PositiveBigIntegerField) can hold.
MAX_POS_PAYER_ID = 2**63 - 1


def seed(*args, **kwargs):
    """Run the command the way a demo run does, capturing its output."""
    out = StringIO()
    call_command('seed_demo', *args, stdout=out, stderr=out, **kwargs)
    return out.getvalue()


def row_counts():
    """Every table the seed writes, so a second run can be compared."""
    return {
        'users': User.objects.count(),
        'user_roles': sum(len(u.roles) for u in User.objects.all()),
        'companies': Company.objects.count(),
        'clients': Project.objects.model._meta.apps.get_model(
            'apps_projects', 'Client').objects.count(),
        'materials': MaterialItem.objects.count(),
        'suppliers': Supplier.objects.count(),
        'trades': Trade.objects.count(),
        'equipment': EquipmentItem.objects.count(),
        'projects': Project.objects.count(),
        'assignments': ProjectAssignment.objects.count(),
        'categories': Category.objects.count(),
        'todos': Todo.objects.count(),
        'workers': Worker.objects.count(),
        'attendance': Attendance.objects.count(),
    }


class SeedDemoCommandTests(TestCase):
    def test_refuses_to_run_without_debug_or_the_demo_flag(self):
        with self.assertRaises(CommandError):
            seed()

        self.assertEqual(User.objects.count(), 0)
        self.assertEqual(Project.objects.count(), 0)

    @override_settings(DEBUG=True)
    def test_runs_when_debug_is_on(self):
        seed()

        self.assertEqual(User.objects.count(), len(DEMO_EMAILS))

    def test_runs_with_an_explicit_demo_flag(self):
        seed(SEED_FLAG)

        self.assertEqual(User.objects.count(), len(DEMO_EMAILS))

    def test_a_second_run_creates_no_duplicates(self):
        seed(SEED_FLAG)
        first = row_counts()

        seed(SEED_FLAG)

        self.assertEqual(row_counts(), first)

    def test_accounts_hold_the_mock_roles(self):
        seed(SEED_FLAG)

        held = {
            user.email: user.roles
            for user in User.objects.filter(email__in=DEMO_EMAILS)
        }

        self.assertEqual(held['maria@example.ph'], [Role.ADMIN])
        self.assertEqual(held['ramon@example.ph'], [Role.OWNER])
        self.assertEqual(held['ana@example.ph'], [Role.SITE_ENGINEER])
        self.assertEqual(held['liza@example.ph'], [Role.ACCOUNTANT])
        self.assertEqual(held['mark@example.ph'], [Role.CLIENT])
        # A partner who runs a project and also works its site.
        self.assertEqual(held['elena@example.ph'], [Role.OWNER, Role.SITE_ENGINEER])
        self.assertTrue(User.objects.get(email='mark@example.ph').is_active)

    def test_every_demo_account_signs_in_with_the_mock_password(self):
        seed(SEED_FLAG)

        for email in DEMO_EMAILS:
            user = User.objects.get(email=email)
            self.assertTrue(user.check_password(DEMO_PASSWORD), email)

    def test_no_password_reaches_the_output(self):
        output = seed(SEED_FLAG)

        self.assertNotIn(DEMO_PASSWORD, output)
        self.assertNotIn('password123', output.lower())
        # A notice is still printed, so the operator knows a password exists.
        self.assertIn('password', output.lower())

    def test_company_settings_and_master_lists_match_the_mock(self):
        seed(SEED_FLAG)

        company = Company.objects.get()
        self.assertEqual(Company.objects.count(), 1)  # one row per deployment
        self.assertEqual(company.name, 'BuildRight Batangas Construction Inc.')
        self.assertEqual(company.tin, '123-456-789-000')
        self.assertIsNotNone(company.settings)
        self.assertEqual(company.settings.default_retention_pct, Decimal('10.00'))
        self.assertEqual(company.settings.default_down_payment_pct, Decimal('15.00'))

        self.assertEqual(MaterialItem.objects.count(), 12)
        self.assertEqual(Supplier.objects.count(), 4)
        self.assertEqual(Supplier.objects.filter(is_own_store=True).count(), 1)
        self.assertEqual(Trade.objects.count(), 9)
        self.assertEqual(EquipmentItem.objects.count(), 4)

    def test_pos_codes_are_live_pos_selling_unit_barcodes(self):
        seed(SEED_FLAG)

        mapped = MaterialItem.objects.exclude(pos_code__isnull=True).exclude(pos_code='')
        codes = sorted(mapped.values_list('pos_code', flat=True))

        self.assertTrue(codes)
        for code in codes:
            # POS prints and resolves `QB{id:06}-{check digit}`, so an unsuffixed
            # code like `QB000001` comes back as UNKNOWN_MATERIAL.
            self.assertRegex(code, POS_CODE_PATTERN)
        # One barcode, one material: two rows claiming one selling unit would bill
        # the wrong product.
        self.assertEqual(len(codes), len(set(codes)))

        # The mapped materials are POS's own products, by name and unit.
        cement = MaterialItem.objects.get(name='Portland cement 40 kg')
        self.assertEqual(cement.store_sku, 'CEM-40')
        self.assertEqual(cement.pos_code, 'QB000001-7')

        adhesive = MaterialItem.objects.get(name='Tile adhesive 25 kg')
        self.assertEqual(adhesive.unit, 'bag')
        # POS sells this product by KG (QB000009-3) and by BAG (QB000010-9); a
        # 25 kg bag must map to the BAG unit, never to the loose kilogram.
        self.assertEqual(adhesive.pos_code, 'QB000010-9')

    def test_materials_pos_does_not_sell_keep_a_null_pos_code(self):
        seed(SEED_FLAG)

        mapped = MaterialItem.objects.exclude(pos_code__isnull=True).exclude(pos_code='')
        self.assertEqual(
            sorted(mapped.values_list('name', flat=True)),
            ['Portland cement 40 kg', 'Tile adhesive 25 kg'],
        )
        # A fake code is worse than none: CPMS then refuses the own-store PO itself
        # (MISSING_POS_CODE) instead of POS refusing the import later.
        for name in ('Deformed bar 10 mm × 6 m', 'CHB 4"', 'Tie wire #16'):
            self.assertIsNone(MaterialItem.objects.get(name=name).pos_code, name)

    def test_pos_payer_id_option_sets_the_own_store_payer(self):
        seed(SEED_FLAG, '--pos-payer-id', 3)

        self.assertEqual(Supplier.objects.get(is_own_store=True).pos_payer_id, 3)
        # Only the own store bills a POS payer.
        self.assertEqual(
            Supplier.objects.filter(
                is_own_store=False, pos_payer_id__isnull=False,
            ).count(),
            0,
        )

    def test_a_null_payer_prints_the_operator_notice(self):
        output = seed(SEED_FLAG)

        # POS customer ids are not stable across databases, so the seed cannot
        # guess one: it stays null and tells the operator how to set it.
        self.assertIsNone(Supplier.objects.get(is_own_store=True).pos_payer_id)
        self.assertIn('--pos-payer-id', output)
        self.assertIn('integration/cpms/customers/', output)

    def test_the_notice_is_silent_once_a_payer_is_given(self):
        output = seed(SEED_FLAG, '--pos-payer-id', 3)

        self.assertNotIn('integration/cpms/customers/', output)

    def test_auto_pos_payer_discovers_first_pos_customer_when_unset(self):
        fake_client = mock.Mock()
        fake_client.list_customers.return_value = [
            {'id': 42, 'name': 'BuildRight Contractor Account'},
        ]
        with mock.patch(
            'apps.requisitions.pos_client.get_pos_client',
            return_value=fake_client,
        ):
            output = seed(SEED_FLAG, '--auto-pos-payer')

        self.assertEqual(Supplier.objects.get(is_own_store=True).pos_payer_id, 42)
        self.assertNotIn('integration/cpms/customers/', output)

    def test_pos_payer_id_is_validated(self):
        for bad in (0, -4, MAX_POS_PAYER_ID + 1, 'not-a-number'):
            with self.assertRaises(CommandError, msg=repr(bad)):
                seed(SEED_FLAG, '--pos-payer-id', bad)
        # The refused runs wrote nothing.
        self.assertFalse(Supplier.objects.exists())

        # The largest id the bigint column holds is still accepted.
        seed(SEED_FLAG, '--pos-payer-id', MAX_POS_PAYER_ID)
        self.assertEqual(
            Supplier.objects.get(is_own_store=True).pos_payer_id, MAX_POS_PAYER_ID,
        )

    def test_projects_assignments_categories_and_todos_match_the_mock(self):
        seed(SEED_FLAG)

        self.assertEqual(
            sorted(Project.objects.values_list('code', flat=True)), sorted(PROJECT_CODES),
        )
        primary = Project.objects.get(code='QB-2026-014')
        self.assertEqual(primary.status, 'ongoing')
        self.assertEqual(primary.contract_amount, Decimal('2000000.00'))
        self.assertEqual(primary.client.name, 'Mark Villanueva')

        # Only accepted assignments grant project scope.
        self.assertEqual(
            ProjectAssignment.objects.filter(project=primary, response='accepted').count(), 3,
        )
        # Every seeded project has at least one accepted assignment.
        for project in Project.objects.all():
            self.assertTrue(
                project.assignments.filter(response='accepted').exists(), project.code,
            )

        self.assertEqual(Category.objects.count(), 8)
        self.assertEqual(Todo.objects.count(), 27)
        self.assertEqual(
            Todo.objects.filter(category__project=primary, is_verified=True).count(), 7,
        )

    def test_workers_and_a_little_attendance_are_seeded(self):
        seed(SEED_FLAG)

        self.assertEqual(Worker.objects.count(), 11)
        self.assertFalse(Worker.objects.get(full_name='Pablo Garcia').is_active)
        self.assertGreater(Attendance.objects.count(), 0)
        self.assertLess(Attendance.objects.count(), 100)
        # Attendance is always attributed to a seeded user.
        self.assertEqual(
            set(Attendance.objects.values_list('recorded_by__email', flat=True)),
            {'ana@example.ph', 'elena@example.ph'},
        )

    def test_every_seeded_amount_is_a_finite_decimal(self):
        seed(SEED_FLAG)

        # A category budget may be unset on purpose (Category 7 in MockData).
        amounts = (
            list(Project.objects.values_list('contract_amount', flat=True))
            + [budget for budget in Category.objects.values_list('budget', flat=True)
               if budget is not None]
            + list(MaterialItem.objects.values_list('default_unit_cost', flat=True))
            + list(EquipmentItem.objects.values_list('rate', flat=True))
            + list(Worker.objects.values_list('daily_rate', flat=True))
        )
        self.assertTrue(amounts)
        for amount in amounts:
            self.assertIsInstance(amount, Decimal)
            self.assertTrue(amount.is_finite(), amount)

    def test_reset_removes_only_the_rows_the_seed_created(self):
        seed(SEED_FLAG)
        company = Company.objects.get()
        outsider = User.objects.create_user(
            email='outsider@example.com', password=OUTSIDER_PASSWORD,
            full_name='Outsider', company=company, roles=[Role.OWNER],
        )
        foreign_project = Project.objects.create(code='EXT-2026-001', name='Not ours')
        foreign_material = MaterialItem.objects.create(
            name='Foreign material', unit='pc', default_unit_cost=Decimal('1.00'),
        )

        seed(SEED_FLAG, '--reset')

        self.assertTrue(User.objects.filter(pk=outsider.pk).exists())
        self.assertTrue(Project.objects.filter(pk=foreign_project.pk).exists())
        self.assertTrue(MaterialItem.objects.filter(pk=foreign_material.pk).exists())
        # The seeded rows are back, exactly once.
        self.assertEqual(User.objects.filter(email__in=DEMO_EMAILS).count(), len(DEMO_EMAILS))
        self.assertEqual(Project.objects.filter(code__in=PROJECT_CODES).count(), 4)
        self.assertEqual(CompanySettings.objects.count(), 1)


class SeedDemoLoginTests(APITestCase):
    """The seeded rows must work through the real, unpatched login endpoint."""

    def setUp(self):
        cache.clear()
        seed(SEED_FLAG)
        self.client = APIClient()

    def log_in(self, email):
        response = self.client.post(
            LOGIN_URL, {'email': email, 'password': DEMO_PASSWORD}, format='json',
        )
        self.assertEqual(response.status_code, 200, response.data)
        return response.data

    def test_every_demo_account_logs_in_and_gets_its_roles(self):
        expected = {
            'maria@example.ph': ['admin'],
            'ramon@example.ph': ['owner'],
            'ana@example.ph': ['site_engineer'],
            'liza@example.ph': ['accountant'],
            'mark@example.ph': ['client'],
            'elena@example.ph': ['owner', 'site_engineer'],
        }

        for email, roles in expected.items():
            data = self.log_in(email)
            cache.clear()  # the login throttle is per IP, not per account
            self.assertEqual(data['roles'], roles, email)
            self.assertEqual(data['user']['email'], email)
            self.assertNotIn('password', data['user'])

    def test_multi_role_account_acts_in_the_role_the_header_names(self):
        data = self.log_in('elena@example.ph')
        self.client.credentials(
            HTTP_AUTHORIZATION=f'Bearer {data["access"]}',
            HTTP_X_ACTIVE_ROLE='site_engineer',
        )

        held = self.client.get(PROJECTS_URL)
        self.assertEqual(held.status_code, 200, held.data)

        self.client.credentials(
            HTTP_AUTHORIZATION=f'Bearer {data["access"]}',
            HTTP_X_ACTIVE_ROLE='accountant',
        )
        unheld = self.client.get(PROJECTS_URL)
        self.assertEqual(unheld.status_code, 403)
        self.assertEqual(unheld.data['code'], 'ROLE_NOT_HELD')

    def test_client_role_sees_only_its_own_project(self):
        data = self.log_in('mark@example.ph')
        self.client.credentials(
            HTTP_AUTHORIZATION=f'Bearer {data["access"]}',
            HTTP_X_ACTIVE_ROLE='client',
        )

        response = self.client.get(PROJECTS_URL)

        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual([row['code'] for row in response.data], ['QB-2026-014'])

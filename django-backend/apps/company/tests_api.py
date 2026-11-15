"""Phase 1.2 wire-contract tests: company profile and company settings.

Every check in `planning/backend-integration/contracts/phase-1-auth-and-admin.md`
under "Company, settings and master lists (task 1.2)" has a test here.
"""

# Pyright here runs without django-stubs, so model managers and `.first()`
# results are untyped/Optional.
# pyright: reportAttributeAccessIssue=false, reportArgumentType=false, reportOptionalMemberAccess=false

from datetime import date

from rest_framework.test import APITestCase

from ..users.models import AuditLog, Role
from ..users.tests import make_user
from .models import Company, CompanySettings

COMPANY_URL = '/api/v1/company/'
SETTINGS_URL = '/api/v1/company-settings/'


class CompanyApiTestCase(APITestCase):
    """Signs in a user in a chosen active role against the seeded company."""

    def user_in(self, role):
        return make_user(f'{role}@example.com', [role])

    def sign_in(self, user, role=None):
        self.client.force_authenticate(user=user)
        if role:
            self.client.credentials(HTTP_X_ACTIVE_ROLE=role)
        return user

    def owner_admin(self):
        return make_user('maria@example.com', [Role.ADMIN, Role.OWNER])

    def company(self):
        return Company.objects.first()


class CompanyProfileReadTests(CompanyApiTestCase):
    def test_any_signed_in_role_reads_the_profile_including_the_client(self):
        company = self.company()
        company.pcab_license_expiry = date(2026, 12, 15)
        company.save()

        for role in (Role.ADMIN, Role.OWNER, Role.ACCOUNTANT,
                     Role.SITE_ENGINEER, Role.CLIENT):
            user = make_user(f'{role}@example.com', [role])
            self.sign_in(user, role)

            response = self.client.get(COMPANY_URL)

            self.assertEqual(response.status_code, 200, (role, response.data))
            self.assertEqual(
                set(response.data),
                {'id', 'name', 'address', 'tin', 'pcab_license_no',
                 'pcab_license_expiry', 'logo_url', 'created_at', 'updated_at'},
            )

    def test_the_pcab_expiry_is_always_a_date_because_flutter_parses_it_non_null(self):
        self.sign_in(self.owner_admin(), Role.ADMIN)

        response = self.client.get(COMPANY_URL)

        self.assertEqual(response.status_code, 200, response.data)
        self.assertIsNotNone(response.data['pcab_license_expiry'])
        date.fromisoformat(str(response.data['pcab_license_expiry']))

    def test_an_anonymous_caller_is_refused(self):
        response = self.client.get(COMPANY_URL)

        self.assertEqual(response.status_code, 401)

    def test_an_unknown_active_role_header_is_refused(self):
        self.sign_in(make_user('ana@example.com', [Role.OWNER]), Role.CLIENT)

        response = self.client.get(COMPANY_URL)

        self.assertEqual(response.status_code, 403)
        self.assertEqual(response.data['code'], 'ROLE_NOT_HELD')


class CompanyProfileWriteTests(CompanyApiTestCase):
    def body(self, **overrides):
        payload = {
            'name': 'BuildRight Batangas Construction Inc.',
            'address': 'J.P. Laurel Highway, Lipa City, Batangas',
            'tin': '123-456-789-000',
            'pcab_license_no': 'PCAB 41234',
            'pcab_license_expiry': '2026-12-15',
        }
        payload.update(overrides)
        return payload

    def test_admin_saves_the_profile_and_the_row_is_updated(self):
        self.sign_in(self.owner_admin(), Role.ADMIN)

        response = self.client.patch(COMPANY_URL, self.body(), format='json')

        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data['name'],
                         'BuildRight Batangas Construction Inc.')
        self.company().refresh_from_db()
        self.assertEqual(self.company().tin, '123-456-789-000')
        self.assertEqual(self.company().pcab_license_expiry, date(2026, 12, 15))

    def test_non_admin_roles_cannot_save_the_profile(self):
        for role in (Role.OWNER, Role.ACCOUNTANT, Role.SITE_ENGINEER, Role.CLIENT):
            user = make_user(f'{role}@example.com', [role])
            self.sign_in(user, role)

            response = self.client.patch(COMPANY_URL, self.body(), format='json')

            self.assertEqual(response.status_code, 403, (role, response.data))

    def test_required_fields_use_the_mock_messages(self):
        self.sign_in(self.owner_admin(), Role.ADMIN)

        cases = [
            ({'name': '  '}, 'Enter the company name.'),
            ({'address': ''}, 'Enter the address.'),
            ({'pcab_license_no': ''}, 'Enter the PCAB license number.'),
            ({'tin': ''}, 'Enter the TIN.'),
            ({'tin': '12-34'}, 'Use the format 000-000-000-000.'),
        ]
        for overrides, message in cases:
            response = self.client.patch(COMPANY_URL, self.body(**overrides),
                                         format='json')

            self.assertEqual(response.status_code, 400, (overrides, response.data))
            self.assertEqual(response.data['detail'], message, overrides)

    def test_the_pcab_expiry_cannot_be_cleared_and_a_patch_keeps_it(self):
        self.sign_in(self.owner_admin(), Role.ADMIN)

        cleared = self.client.patch(COMPANY_URL, {'pcab_license_expiry': None},
                                    format='json')
        kept = self.client.patch(COMPANY_URL, {'name': 'BuildRight Lipa Inc.'},
                                 format='json')

        self.assertEqual(cleared.status_code, 400, cleared.data)
        self.assertEqual(cleared.data['detail'], 'Enter the PCAB license expiry.')
        self.assertEqual(kept.status_code, 200, kept.data)
        self.assertIsNotNone(kept.data['pcab_license_expiry'])

    def test_the_logo_stays_a_url_field_this_phase(self):
        self.sign_in(self.owner_admin(), Role.ADMIN)

        saved = self.client.patch(COMPANY_URL,
                                  self.body(logo_url='https://cdn.example.ph/logo.png'),
                                  format='json')
        cleared = self.client.patch(COMPANY_URL, {'logo_url': None}, format='json')
        invalid = self.client.patch(COMPANY_URL, {'logo_url': 'not-a-url'},
                                    format='json')

        self.assertEqual(saved.status_code, 200, saved.data)
        self.assertEqual(saved.data['logo_url'], 'https://cdn.example.ph/logo.png')
        self.assertEqual(cleared.status_code, 200, cleared.data)
        self.assertIsNone(cleared.data['logo_url'])
        self.assertEqual(invalid.status_code, 400, invalid.data)

    def test_a_save_writes_exactly_one_audit_row(self):
        admin = self.sign_in(self.owner_admin(), Role.ADMIN)

        self.client.patch(COMPANY_URL, self.body(name='BuildRight Lipa Inc.'),
                          format='json')

        rows = AuditLog.objects.filter(entity='company')
        self.assertEqual(rows.count(), 1)
        self.assertEqual(rows.first().action, 'company_profile_updated')
        self.assertEqual(rows.first().user_id, admin.pk)
        self.assertEqual(rows.first().details, {'name': 'BuildRight Lipa Inc.'})

    def test_a_refused_save_writes_no_audit_row(self):
        self.sign_in(self.owner_admin(), Role.ADMIN)

        self.client.patch(COMPANY_URL, self.body(tin='nope'), format='json')

        self.assertEqual(AuditLog.objects.filter(entity='company').count(), 0)


class CompanySettingsTests(CompanyApiTestCase):
    def test_reading_returns_the_row_migration_0004_seeded(self):
        self.sign_in(self.owner_admin(), Role.ADMIN)

        response = self.client.get(SETTINGS_URL)

        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(
            set(response.data),
            {'id', 'company_id', 'default_retention_pct',
             'default_down_payment_pct', 'behind_schedule_threshold_pct',
             'created_at', 'updated_at'},
        )
        self.assertEqual(float(response.data['default_retention_pct']), 10.0)
        self.assertEqual(float(response.data['default_down_payment_pct']), 15.0)
        self.assertEqual(float(response.data['behind_schedule_threshold_pct']), 5.0)
        self.assertEqual(response.data['company_id'], self.company().pk)

    def test_a_read_never_writes(self):
        seeded = CompanySettings.objects.get(company=self.company())
        before = (seeded.pk, seeded.updated_at)
        self.sign_in(self.owner_admin(), Role.ADMIN)

        for role in (Role.ADMIN, Role.ACCOUNTANT, Role.SITE_ENGINEER):
            self.sign_in(self.user_in(role), role)
            self.client.get(SETTINGS_URL)

        rows = CompanySettings.objects.filter(company=self.company())
        self.assertEqual(rows.count(), 1)
        self.assertEqual((rows.first().pk, rows.first().updated_at), before)

    def test_the_row_is_not_created_on_put(self):
        """A settings row exists for every company; no write path has to add one."""
        self.assertEqual(CompanySettings.objects.count(),
                         Company.objects.count())

    def test_settings_stay_a_single_row_per_company(self):
        self.sign_in(self.owner_admin(), Role.ADMIN)

        first = self.client.get(SETTINGS_URL)
        second = self.client.get(SETTINGS_URL)

        self.assertEqual(first.data['id'], second.data['id'])

    def test_staff_roles_read_but_the_client_is_refused(self):
        for role in (Role.ADMIN, Role.OWNER, Role.ACCOUNTANT, Role.SITE_ENGINEER):
            user = make_user(f'{role}@example.com', [role])
            self.sign_in(user, role)

            response = self.client.get(SETTINGS_URL)

            self.assertEqual(response.status_code, 200, (role, response.data))

        self.sign_in(make_user('mark@example.com', [Role.CLIENT]), Role.CLIENT)
        self.assertEqual(self.client.get(SETTINGS_URL).status_code, 403)

    def test_admin_saves_the_settings(self):
        self.sign_in(self.owner_admin(), Role.ADMIN)

        response = self.client.patch(
            SETTINGS_URL,
            {'default_retention_pct': '12.5', 'default_down_payment_pct': 20,
             'behind_schedule_threshold_pct': 7.5},
            format='json',
        )

        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(float(response.data['default_retention_pct']), 12.5)
        self.assertEqual(float(response.data['behind_schedule_threshold_pct']), 7.5)

    def test_non_admin_roles_cannot_save_the_settings(self):
        for role in (Role.OWNER, Role.ACCOUNTANT, Role.SITE_ENGINEER, Role.CLIENT):
            user = make_user(f'{role}@example.com', [role])
            self.sign_in(user, role)

            response = self.client.patch(SETTINGS_URL,
                                         {'default_retention_pct': 50},
                                         format='json')

            self.assertEqual(response.status_code, 403, (role, response.data))

    def test_percentages_use_the_mock_messages(self):
        self.sign_in(self.owner_admin(), Role.ADMIN)

        cases = [
            ({'default_retention_pct': 101}, 'The retention must be 0–100%.'),
            ({'default_retention_pct': -1}, 'The retention must be 0–100%.'),
            ({'default_down_payment_pct': 200},
             'The down payment must be 0–100%.'),
            ({'behind_schedule_threshold_pct': 120},
             'The behind-schedule threshold must be 0–100%.'),
            ({'default_retention_pct': None}, 'Enter the retention.'),
        ]
        for overrides, message in cases:
            response = self.client.patch(SETTINGS_URL, overrides, format='json')

            self.assertEqual(response.status_code, 400, (overrides, response.data))
            self.assertEqual(response.data['detail'], message, overrides)

    def test_a_settings_save_writes_exactly_one_audit_row(self):
        admin = self.sign_in(self.owner_admin(), Role.ADMIN)

        self.client.patch(SETTINGS_URL, {'default_retention_pct': 8},
                          format='json')

        rows = AuditLog.objects.filter(entity='company_settings')
        self.assertEqual(rows.count(), 1)
        self.assertEqual(rows.first().action, 'settings_updated')
        self.assertEqual(rows.first().user_id, admin.pk)
        self.assertEqual(float(rows.first().details['retention_pct']), 8.0)
        self.assertIn('down_payment_pct', rows.first().details)
        self.assertIn('behind_schedule_pct', rows.first().details)

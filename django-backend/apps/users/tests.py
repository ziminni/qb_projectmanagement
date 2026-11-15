"""Tests for the CPMS user model, the multi-role junction and capabilities."""

# Pyright here runs without django-stubs, so model managers are untyped.
# pyright: reportAttributeAccessIssue=false, reportArgumentType=false

from django.db import IntegrityError
from django.test import TestCase

from ..company.models import Company
from . import capabilities
from .models import AuditLog, Notification, Role, User, UserRole

# Demo-only password for the test users in this suite.
DEMO_PASSWORD = 's3cret-pass-123'  # noqa: S105 - test fixture, not a credential


def make_user(email, roles=(), password=None, **extra):
    """Create a user on the seeded company, optionally holding `roles`."""
    extra.setdefault('full_name', email.split('@')[0].replace('.', ' ').title())
    extra.setdefault('company', Company.objects.first())
    return User.objects.create_user(
        email=email, password=password or DEMO_PASSWORD, roles=list(roles), **extra,
    )


class UserModelTests(TestCase):
    def test_create_user_hashes_password_and_holds_the_given_roles(self):
        user = make_user('jdelacruz@example.com', [Role.SITE_ENGINEER])

        self.assertTrue(user.check_password('s3cret-pass-123'))
        self.assertFalse(user.is_staff)
        self.assertFalse(user.is_superuser)
        self.assertEqual(user.roles, ['site_engineer'])
        self.assertEqual(user.company, Company.objects.first())

    def test_create_superuser_holds_admin_and_owner(self):
        admin = User.objects.create_superuser(
            email='boss@example.com',
            password='s3cret-pass-123',
            full_name='The Boss',
            company=Company.objects.first(),
        )

        self.assertEqual(sorted(admin.roles), ['admin', 'owner'])
        self.assertTrue(admin.is_staff)
        self.assertTrue(admin.is_superuser)

    def test_email_is_stored_lower_case_and_unique_case_insensitively(self):
        user = make_user('Mixed.Case@Example.com')

        self.assertEqual(user.email, 'mixed.case@example.com')
        with self.assertRaises(IntegrityError):
            make_user('MIXED.CASE@example.com')

    def test_full_name_and_email_identify_the_user(self):
        user = make_user('ana@example.com', full_name='Ana Reyes')

        self.assertEqual(user.full_name, 'Ana Reyes')
        self.assertEqual(str(user), 'Ana Reyes <ana@example.com>')

    def test_set_roles_replaces_the_whole_set_and_never_duplicates(self):
        user = make_user('liza@example.com', [Role.SITE_ENGINEER, Role.ACCOUNTANT])

        user.set_roles([Role.ACCOUNTANT, Role.CLIENT, Role.ACCOUNTANT])

        self.assertEqual(user.roles, ['accountant', 'client'])
        self.assertEqual(UserRole.objects.filter(user=user).count(), 2)

    def test_role_requires_a_known_code_and_is_unique_per_user(self):
        user = make_user('mark@example.com', [Role.CLIENT])

        with self.assertRaises(IntegrityError):
            UserRole.objects.create(user=user, role=Role.CLIENT)

    def test_role_flags(self):
        pm = make_user('pm@example.com', [Role.OWNER])
        admin = make_user('admin@example.com', [Role.ADMIN])
        client = make_user('client@example.com', [Role.CLIENT])

        self.assertTrue(pm.is_project_manager)
        self.assertFalse(pm.is_admin)

        self.assertTrue(admin.is_admin)
        self.assertFalse(admin.is_client)

        self.assertTrue(client.is_client)

    def test_only_admin_and_owner_may_approve_requisitions(self):
        self.assertTrue(make_user('a@example.com', [Role.ADMIN]).can_approve_requisitions())
        self.assertTrue(make_user('b@example.com', [Role.OWNER]).can_approve_requisitions())
        self.assertFalse(
            make_user('c@example.com', [Role.SITE_ENGINEER]).can_approve_requisitions()
        )
        self.assertFalse(
            make_user('d@example.com', [Role.ACCOUNTANT]).can_approve_requisitions()
        )
        self.assertFalse(make_user('e@example.com', [Role.CLIENT]).can_approve_requisitions())

    def test_superuser_is_treated_as_admin_even_without_admin_role(self):
        root = User.objects.create_user(
            email='root@example.com',
            password='s3cret-pass-123',
            full_name='Root',
            company=Company.objects.first(),
            is_superuser=True,
        )

        self.assertTrue(root.is_admin)


class CapabilitiesTests(TestCase):
    def test_role_order_drives_the_default_active_role(self):
        user = make_user('multi@example.com', [Role.ACCOUNTANT, Role.ADMIN, Role.OWNER])

        self.assertEqual(capabilities.default_role(user), 'admin')
        self.assertEqual(user.roles, ['admin', 'owner', 'accountant'])

    def test_roleless_user_has_no_default_role(self):
        user = make_user('new@example.com')

        self.assertIsNone(capabilities.default_role(user))

    def test_capability_sets(self):
        self.assertEqual(
            capabilities.ALL_PROJECTS_ROLES,
            frozenset({Role.ADMIN, Role.ACCOUNTANT}),
        )
        self.assertEqual(
            capabilities.FINANCE_ROLES,
            frozenset({Role.OWNER, Role.ACCOUNTANT}),
        )
        self.assertNotIn(Role.CLIENT, capabilities.STAFF_ROLES)
        self.assertTrue(capabilities.sees_finance('owner'))
        self.assertFalse(capabilities.sees_finance('site_engineer'))
        self.assertTrue(capabilities.sees_all_projects('accountant'))


class LegacyRoleMigrationTests(TestCase):
    """The legacy single `role` must map onto the agreed 5-role model (decision 03)."""

    def test_legacy_roles_map_to_the_agreed_codes(self):
        import importlib

        migration = importlib.import_module(
            'apps.users.migrations.0002_email_login_multi_role',
        )

        self.assertEqual(
            migration.LEGACY_ROLE_MAP,
            {
                'ADMIN': 'admin',
                'PROJECT_MANAGER': 'owner',
                'SITE_SUPERVISOR': 'site_engineer',
                'ENGINEER': 'site_engineer',
            },
        )


class AuditAndNotificationModelTests(TestCase):
    def test_audit_and_notification_rows_default_sanely(self):
        user = make_user('audit@example.com', [Role.ADMIN])

        audit = AuditLog.objects.create(user=user, action='login', entity='auth',
                                        entity_id=user.pk)
        note = Notification.objects.create(user=user, type='welcome', message='Hi')

        self.assertEqual(audit.details, {})
        self.assertIsNone(note.link)
        self.assertFalse(note.is_read)
        self.assertEqual(list(user.notifications.all()), [note])

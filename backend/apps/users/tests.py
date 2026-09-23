"""Tests for the CPMS user model and role taxonomy."""

from django.test import TestCase

from .models import User, UserRole


class UserModelTests(TestCase):
    def test_create_user_defaults_to_engineer_role_and_hashes_password(self):
        user = User.objects.create_user(
            username='jdelacruz',
            email='jdelacruz@example.com',
            password='s3cret-pass-123',
        )

        self.assertEqual(user.role, UserRole.ENGINEER)
        self.assertTrue(user.check_password('s3cret-pass-123'))
        self.assertFalse(user.is_staff)
        self.assertFalse(user.is_superuser)

    def test_create_superuser_gets_admin_role(self):
        admin = User.objects.create_superuser(
            username='boss',
            email='boss@example.com',
            password='s3cret-pass-123',
        )

        self.assertEqual(admin.role, UserRole.ADMIN)
        self.assertTrue(admin.is_staff)
        self.assertTrue(admin.is_superuser)

    def test_email_and_username_are_unique(self):
        User.objects.create_user(
            username='a', email='a@example.com', password='s3cret-pass-123',
        )

        with self.assertRaises(Exception):
            User.objects.create_user(
                username='a', email='other@example.com', password='s3cret-pass-123',
            )

    def test_full_name_falls_back_to_username(self):
        named = User(username='named', first_name='Juan', last_name='Dela Cruz')
        unnamed = User(username='anon')

        self.assertEqual(named.full_name, 'Juan Dela Cruz')
        self.assertEqual(unnamed.full_name, 'anon')

    def test_str_includes_role_label(self):
        user = User(username='pm1', role=UserRole.PROJECT_MANAGER)

        self.assertEqual(str(user), 'pm1 (Project Manager)')

    def test_role_flags(self):
        pm = User(username='pm', role=UserRole.PROJECT_MANAGER)
        site = User(username='site', role=UserRole.SITE_SUPERVISOR)
        eng = User(username='eng', role=UserRole.ENGINEER)

        self.assertTrue(pm.is_project_manager)
        self.assertFalse(pm.is_admin)

        self.assertTrue(site.is_site_supervisor)
        self.assertFalse(site.is_engineer)

        self.assertTrue(eng.is_engineer)

    def test_only_project_manager_and_admin_may_approve_requisitions(self):
        self.assertTrue(
            User(username='a', role=UserRole.ADMIN).can_approve_requisitions()
        )
        self.assertTrue(
            User(username='b', role=UserRole.PROJECT_MANAGER).can_approve_requisitions()
        )
        self.assertFalse(
            User(username='c', role=UserRole.SITE_SUPERVISOR).can_approve_requisitions()
        )
        self.assertFalse(
            User(username='d', role=UserRole.ENGINEER).can_approve_requisitions()
        )

    def test_superuser_is_treated_as_admin(self):
        user = User(username='root', role=UserRole.ENGINEER, is_superuser=True)

        self.assertTrue(user.is_admin)
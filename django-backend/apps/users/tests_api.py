"""Phase 1.1 wire-contract tests: auth, roles, users, audit, notifications.

Every check in `planning/backend-integration/contracts/phase-1-auth-and-admin.md`
under "Security checks this phase must prove with tests" has a test here.
"""

# Pyright here runs without django-stubs, so model managers are untyped.
# pyright: reportAttributeAccessIssue=false, reportArgumentType=false

import hashlib

from django.core.cache import cache
from rest_framework.test import APITestCase

from .models import AuditLog, Notification, Role, User, UserRole
from .tests import DEMO_PASSWORD, make_user

LOGIN_URL = '/api/v1/auth/login/'
ME_URL = '/api/v1/auth/me/'
USERS_URL = '/api/v1/users/'


class ApiTestCase(APITestCase):
    """Clears the throttle cache so limits never leak between tests."""

    def setUp(self):
        cache.clear()

    def sign_in(self, user):
        self.client.force_authenticate(user=user)
        return user


class LoginTests(ApiTestCase):
    def test_login_returns_user_roles_and_tokens(self):
        make_user('maria@example.com', [Role.ADMIN, Role.OWNER], full_name='Maria Santos')

        response = self.client.post(
            LOGIN_URL,
            {'email': 'MARIA@Example.com', 'password': DEMO_PASSWORD},
            format='json',
        )

        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(set(response.data), {'user', 'roles', 'access', 'refresh'})
        self.assertEqual(response.data['roles'], ['admin', 'owner'])
        self.assertEqual(
            set(response.data['user']),
            {'id', 'company_id', 'full_name', 'email', 'phone', 'is_active',
             'created_at', 'updated_at'},
        )
        self.assertEqual(response.data['user']['email'], 'maria@example.com')
        self.assertNotIn('password', response.data['user'])
        self.assertEqual(AuditLog.objects.filter(action='login').count(), 1)

    def test_wrong_password_and_unknown_email_share_one_answer(self):
        make_user('maria@example.com', [Role.ADMIN])

        wrong_password = self.client.post(
            LOGIN_URL, {'email': 'maria@example.com', 'password': 'nope-nope-1'},
            format='json',
        )
        unknown_email = self.client.post(
            LOGIN_URL, {'email': 'nobody@example.com', 'password': 'nope-nope-1'},
            format='json',
        )

        self.assertEqual(wrong_password.status_code, 400)
        self.assertEqual(unknown_email.status_code, 400)
        self.assertEqual(wrong_password.data['detail'], 'Incorrect email or password.')
        self.assertEqual(unknown_email.data['detail'], wrong_password.data['detail'])
        self.assertEqual(AuditLog.objects.filter(action='login_failed').count(), 1)

    def test_inactive_account_failure_is_audited(self):
        user = make_user('ana@example.com', [Role.ADMIN], is_active=False)

        self.client.post(
            LOGIN_URL, {'email': 'ana@example.com', 'password': DEMO_PASSWORD},
            format='json',
        )

        row = AuditLog.objects.get(action='login_failed')
        self.assertEqual(row.user_id, user.pk)
        self.assertEqual(row.details, {'reason': 'inactive'})

    def test_account_without_a_role_failure_is_audited(self):
        user = make_user('new@example.com')

        self.client.post(
            LOGIN_URL, {'email': 'new@example.com', 'password': DEMO_PASSWORD},
            format='json',
        )

        row = AuditLog.objects.get(action='login_failed')
        self.assertEqual(row.user_id, user.pk)
        self.assertEqual(row.details, {'reason': 'no_role'})

    def test_unknown_email_warns_with_a_hashed_email_and_writes_no_audit_row(self):
        make_user('maria@example.com', [Role.ADMIN])

        with self.assertLogs('cpms.security', level='WARNING') as logs:
            response = self.client.post(
                LOGIN_URL,
                {'email': 'Nobody@Example.com', 'password': 'nope-nope-1'},
                format='json',
            )

        self.assertEqual(response.status_code, 400)
        self.assertEqual(response.data['detail'], 'Incorrect email or password.')
        message = '\n'.join(logs.output)
        digest = hashlib.sha256(b'nobody@example.com').hexdigest()
        self.assertIn(digest, message)
        # The raw address identifies a non-user; only the hash may leave the server.
        self.assertNotIn('nobody@example.com', message.lower())
        self.assertIn('127.0.0.1', message)
        self.assertEqual(AuditLog.objects.filter(action='login_failed').count(), 0)

    def test_inactive_account_gets_its_own_message(self):
        make_user('ana@example.com', [Role.ADMIN], is_active=False)

        response = self.client.post(
            LOGIN_URL, {'email': 'ana@example.com', 'password': DEMO_PASSWORD},
            format='json',
        )

        self.assertEqual(response.status_code, 403)
        self.assertEqual(
            response.data['detail'],
            'This account is deactivated. Contact your system admin.',
        )

    def test_account_without_a_role_is_refused(self):
        make_user('new@example.com')

        response = self.client.post(
            LOGIN_URL, {'email': 'new@example.com', 'password': DEMO_PASSWORD},
            format='json',
        )

        self.assertEqual(response.status_code, 403)
        self.assertEqual(
            response.data['detail'],
            'This account has no role yet. Contact your system admin.',
        )

    def test_issued_token_opens_an_authenticated_route(self):
        make_user('liza@example.com', [Role.ACCOUNTANT])

        tokens = self.client.post(
            LOGIN_URL, {'email': 'liza@example.com', 'password': DEMO_PASSWORD},
            format='json',
        ).data

        response = self.client.get(
            ME_URL, HTTP_AUTHORIZATION=f'Bearer {tokens["access"]}',
        )

        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data['roles'], ['accountant'])


class AuthRouteTests(ApiTestCase):
    def test_register_route_is_removed(self):
        response = self.client.post('/api/v1/auth/register/', {}, format='json')

        self.assertEqual(response.status_code, 404)

    def test_me_returns_user_and_roles(self):
        user = make_user('ramon@example.com', [Role.OWNER], full_name='Ramon Cruz')
        self.sign_in(user)

        response = self.client.get(ME_URL)

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['user']['full_name'], 'Ramon Cruz')
        self.assertEqual(response.data['roles'], ['owner'])

    def test_patch_me_updates_full_name_and_phone(self):
        user = make_user('ramon@example.com', [Role.OWNER])
        self.sign_in(user)

        response = self.client.patch(
            ME_URL, {'full_name': 'Ramon B. Cruz', 'phone': '0917'}, format='json',
        )

        self.assertEqual(response.status_code, 200, response.data)
        user.refresh_from_db()
        self.assertEqual(user.full_name, 'Ramon B. Cruz')
        self.assertEqual(user.phone, '0917')

    def test_patch_me_refuses_privilege_escalation(self):
        user = make_user('eng@example.com', [Role.SITE_ENGINEER])
        self.sign_in(user)

        for field, value in (
            ('role', 'admin'),
            ('roles', ['admin']),
            ('is_active', False),
            ('is_staff', True),
            ('is_superuser', True),
            ('email', 'other@example.com'),
        ):
            with self.subTest(field=field):
                response = self.client.patch(ME_URL, {field: value}, format='json')

                self.assertEqual(response.status_code, 400, response.data)

        user.refresh_from_db()
        self.assertEqual(user.roles, ['site_engineer'])
        self.assertTrue(user.is_active)
        self.assertFalse(user.is_staff)
        self.assertFalse(user.is_superuser)
        self.assertEqual(user.email, 'eng@example.com')

    def test_change_password_requires_the_current_password(self):
        user = make_user('client@example.com', [Role.CLIENT])
        self.sign_in(user)

        response = self.client.post(
            '/api/v1/auth/change-password/',
            {'current_password': 'wrong-one-1', 'new_password': 'brand-new-1'},
            format='json',
        )

        self.assertEqual(response.status_code, 400)
        self.assertEqual(response.data['detail'], 'Your current password is incorrect.')

    def test_change_password_rejects_weak_and_repeated_passwords(self):
        user = make_user('client@example.com', [Role.CLIENT])
        self.sign_in(user)
        url = '/api/v1/auth/change-password/'

        for body in (
            {'current_password': DEMO_PASSWORD, 'new_password': 'short1'},
            {'current_password': DEMO_PASSWORD, 'new_password': 'letterswithoutdigits'},
            {'current_password': DEMO_PASSWORD, 'new_password': DEMO_PASSWORD},
        ):
            with self.subTest(body=body):
                response = self.client.post(url, body, format='json')

                self.assertEqual(response.status_code, 400, response.data)

    def test_change_password_succeeds_and_is_audited(self):
        user = make_user('client@example.com', [Role.CLIENT])
        self.sign_in(user)

        response = self.client.post(
            '/api/v1/auth/change-password/',
            {'current_password': DEMO_PASSWORD, 'new_password': 'brand-new-1'},
            format='json',
        )

        self.assertEqual(response.status_code, 200, response.data)
        user.refresh_from_db()
        self.assertTrue(user.check_password('brand-new-1'))
        self.assertEqual(
            AuditLog.objects.filter(action='password_changed', user=user).count(), 1,
        )


class PasswordResetRequestTests(ApiTestCase):
    URL = '/api/v1/auth/password-reset-request/'

    def test_unknown_email_still_answers_204_and_notifies_nobody(self):
        admin = make_user('admin@example.com', [Role.ADMIN])

        response = self.client.post(self.URL, {'email': 'ghost@example.com'},
                                    format='json')

        self.assertEqual(response.status_code, 204)
        self.assertFalse(Notification.objects.filter(user=admin).exists())

    def test_active_admins_are_notified_for_a_known_email(self):
        admin = make_user('admin@example.com', [Role.ADMIN])
        inactive_admin = make_user('gone@example.com', [Role.ADMIN], is_active=False)
        make_user('maria@example.com', [Role.OWNER])

        response = self.client.post(self.URL, {'email': 'maria@example.com'},
                                    format='json')

        self.assertEqual(response.status_code, 204)
        self.assertEqual(
            Notification.objects.filter(
                user=admin, type='password_reset_requested',
            ).count(),
            1,
        )
        self.assertFalse(Notification.objects.filter(user=inactive_admin).exists())

    def test_inactive_user_offers_no_notification(self):
        admin = make_user('admin@example.com', [Role.ADMIN])
        make_user('gone@example.com', [Role.OWNER], is_active=False)

        self.client.post(self.URL, {'email': 'gone@example.com'}, format='json')

        self.assertFalse(Notification.objects.filter(user=admin).exists())


class TokenRouteTests(ApiTestCase):
    def login(self):
        make_user('maria@example.com', [Role.ADMIN])
        return self.client.post(
            LOGIN_URL, {'email': 'maria@example.com', 'password': DEMO_PASSWORD},
            format='json',
        ).data

    def test_refresh_rotates_the_token_and_blacklists_the_old_one(self):
        tokens = self.login()

        refreshed = self.client.post('/api/v1/auth/refresh/',
                                     {'refresh': tokens['refresh']}, format='json')

        self.assertEqual(refreshed.status_code, 200, refreshed.data)
        self.assertEqual(set(refreshed.data), {'access', 'refresh'})
        self.assertNotEqual(refreshed.data['refresh'], tokens['refresh'])

        reuse = self.client.post('/api/v1/auth/refresh/',
                                 {'refresh': tokens['refresh']}, format='json')
        self.assertEqual(reuse.status_code, 401)

    def test_logout_blacklists_the_refresh_token(self):
        tokens = self.login()
        user = User.objects.get(email='maria@example.com')
        self.client.force_authenticate(user=user)

        response = self.client.post('/api/v1/auth/logout/',
                                    {'refresh': tokens['refresh']}, format='json')
        reuse = self.client.post('/api/v1/auth/refresh/',
                                 {'refresh': tokens['refresh']}, format='json')

        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(reuse.status_code, 401)


class UserAdminApiTests(ApiTestCase):
    def setUp(self):
        super().setUp()
        self.admin = make_user('admin@example.com', [Role.ADMIN, Role.OWNER])
        self.owner = make_user('pm@example.com', [Role.OWNER])
        self.client_user = make_user('client@example.com', [Role.CLIENT])

    def test_admin_creates_a_user_with_a_temporary_password(self):
        self.sign_in(self.admin)

        response = self.client.post(USERS_URL, {
            'full_name': 'Ana Reyes',
            'email': 'Ana.Reyes@Example.com',
            'phone': '0917',
            'is_active': True,
            'roles': ['site_engineer'],
        }, format='json')

        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(
            set(response.data), {'user', 'roles', 'temporary_password'},
        )
        self.assertEqual(response.data['user']['email'], 'ana.reyes@example.com')
        self.assertEqual(response.data['roles'], ['site_engineer'])

        login = self.client.post(LOGIN_URL, {
            'email': 'ana.reyes@example.com',
            'password': response.data['temporary_password'],
        }, format='json')
        self.assertEqual(login.status_code, 200, login.data)
        self.assertEqual(
            AuditLog.objects.filter(action='user_created').count(), 1,
        )

    def test_duplicate_email_is_rejected_case_insensitively(self):
        self.sign_in(self.admin)

        response = self.client.post(USERS_URL, {
            'full_name': 'Clone',
            'email': 'ADMIN@example.com',
            'roles': ['client'],
        }, format='json')

        self.assertEqual(response.status_code, 400, response.data)
        self.assertIn('email', response.data)

    def test_a_user_needs_at_least_one_valid_role(self):
        self.sign_in(self.admin)

        for roles in ([], ['wizard']):
            with self.subTest(roles=roles):
                response = self.client.post(USERS_URL, {
                    'full_name': 'Nobody',
                    'email': 'nobody@example.com',
                    'roles': roles,
                }, format='json')

                self.assertEqual(response.status_code, 400, response.data)

    def test_non_admin_cannot_write_users(self):
        for actor, roles in (
            (self.owner, ['owner']),
            (self.client_user, ['client']),
        ):
            with self.subTest(roles=roles):
                self.sign_in(actor)
                response = self.client.post(USERS_URL, {
                    'full_name': 'Smuggled',
                    'email': 'smuggled@example.com',
                    'roles': ['admin'],
                }, format='json')

                self.assertEqual(response.status_code, 403, response.data)

    def test_admin_replaces_the_role_set(self):
        target = make_user('eng@example.com', [Role.SITE_ENGINEER])
        self.sign_in(self.admin)

        response = self.client.patch(
            f'{USERS_URL}{target.pk}/', {'roles': ['accountant', 'client']},
            format='json',
        )

        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data['roles'], ['accountant', 'client'])
        target.refresh_from_db()
        self.assertEqual(sorted(r.role for r in UserRole.objects.filter(user=target)),
                         ['accountant', 'client'])
        self.assertEqual(
            AuditLog.objects.filter(action='user_roles_changed', entity_id=target.pk).count(),
            1,
        )

    def test_delete_is_not_allowed(self):
        target = make_user('eng@example.com', [Role.SITE_ENGINEER])
        self.sign_in(self.admin)

        response = self.client.delete(f'{USERS_URL}{target.pk}/')

        self.assertEqual(response.status_code, 405)
        self.assertTrue(User.objects.filter(pk=target.pk).exists())

    def test_admin_cannot_remove_own_admin_role_or_deactivate_themselves(self):
        self.sign_in(self.admin)

        demote = self.client.patch(
            f'{USERS_URL}{self.admin.pk}/', {'roles': ['owner']}, format='json',
        )
        deactivate = self.client.patch(
            f'{USERS_URL}{self.admin.pk}/', {'is_active': False}, format='json',
        )

        self.assertEqual(demote.status_code, 400, demote.data)
        self.assertEqual(deactivate.status_code, 400, deactivate.data)
        self.admin.refresh_from_db()
        self.assertTrue(self.admin.is_active)
        self.assertEqual(self.admin.roles, ['admin', 'owner'])

    def test_admin_reset_password_returns_a_working_temporary_password(self):
        target = make_user('eng@example.com', [Role.SITE_ENGINEER])
        self.sign_in(self.admin)

        response = self.client.post(f'{USERS_URL}{target.pk}/reset-password/',
                                    {}, format='json')

        self.assertEqual(response.status_code, 200, response.data)
        password = response.data['temporary_password']
        self.assertGreaterEqual(len(password), 8)
        target.refresh_from_db()
        self.assertTrue(target.check_password(password))
        self.assertEqual(AuditLog.objects.filter(action='password_reset').count(), 1)

    def test_staff_can_read_the_directory_but_a_client_cannot(self):
        self.sign_in(self.owner)
        staff_view = self.client.get(USERS_URL)
        self.assertEqual(staff_view.status_code, 200)
        self.assertGreaterEqual(staff_view.data['count'], 3)

        other = make_user('other@example.com', [Role.CLIENT])
        self.sign_in(self.client_user)
        own = self.client.get(f'{USERS_URL}{self.client_user.pk}/')
        someone_else = self.client.get(f'{USERS_URL}{other.pk}/')
        listing = self.client.get(USERS_URL)

        self.assertEqual(own.status_code, 200, own.data)
        self.assertEqual(someone_else.status_code, 404)
        self.assertEqual(listing.status_code, 403)

    def test_directory_filters_by_role_and_activity(self):
        make_user('eng@example.com', [Role.SITE_ENGINEER], is_active=False)
        self.sign_in(self.admin)

        by_role = self.client.get(USERS_URL, {'role': 'site_engineer'})
        inactive = self.client.get(USERS_URL, {'is_active': 'false'})

        self.assertEqual(by_role.status_code, 200)
        self.assertEqual(
            [row['email'] for row in by_role.data['results']], ['eng@example.com'],
        )
        self.assertEqual(
            [row['email'] for row in inactive.data['results']], ['eng@example.com'],
        )


class LastAdminGuardTests(ApiTestCase):
    """The firm can never be left without an active admin."""

    def test_last_active_admin_cannot_be_demoted_or_deactivated(self):
        # A superuser acts as admin through is_superuser only, so the single
        # stored admin below is the last one who can actually administer.
        root = make_user('root@example.com', is_superuser=True, is_staff=True)
        last_admin = make_user('only@example.com', [Role.ADMIN])
        self.sign_in(root)

        demote = self.client.patch(
            f'{USERS_URL}{last_admin.pk}/', {'roles': ['owner']}, format='json',
        )
        deactivate = self.client.patch(
            f'{USERS_URL}{last_admin.pk}/', {'is_active': False}, format='json',
        )

        self.assertEqual(demote.status_code, 400, demote.data)
        self.assertEqual(deactivate.status_code, 400, deactivate.data)
        last_admin.refresh_from_db()
        self.assertEqual(last_admin.roles, ['admin'])
        self.assertTrue(last_admin.is_active)

    def test_a_second_admin_may_be_demoted(self):
        actor = make_user('actor@example.com', [Role.ADMIN])
        other = make_user('other@example.com', [Role.ADMIN])
        self.sign_in(actor)

        response = self.client.patch(
            f'{USERS_URL}{other.pk}/', {'roles': ['owner']}, format='json',
        )

        self.assertEqual(response.status_code, 200, response.data)
        other.refresh_from_db()
        self.assertEqual(other.roles, ['owner'])


class ActiveRoleTests(ApiTestCase):
    def test_unknown_active_role_is_refused(self):
        engineer = make_user('eng@example.com', [Role.SITE_ENGINEER])
        self.sign_in(engineer)

        response = self.client.get(USERS_URL, HTTP_X_ACTIVE_ROLE='admin')

        self.assertEqual(response.status_code, 403)
        self.assertEqual(response.data, {'code': 'ROLE_NOT_HELD'})

    def test_held_role_switches_the_permissions_in_force(self):
        admin = make_user('admin@example.com', [Role.ADMIN, Role.OWNER])
        self.sign_in(admin)

        as_admin = self.client.get(USERS_URL, HTTP_X_ACTIVE_ROLE='admin')
        as_owner = self.client.get(USERS_URL, HTTP_X_ACTIVE_ROLE='owner')

        self.assertEqual(as_admin.status_code, 200)
        self.assertEqual(as_owner.status_code, 200)

        write_as_owner = self.client.post(
            USERS_URL,
            {'full_name': 'X', 'email': 'x@example.com', 'roles': ['client']},
            format='json',
            HTTP_X_ACTIVE_ROLE='owner',
        )
        self.assertEqual(write_as_owner.status_code, 403)

    def test_a_client_active_role_attribute_cannot_read_the_directory(self):
        both = make_user('dual@example.com', [Role.ADMIN, Role.CLIENT])
        self.sign_in(both)

        response = self.client.get(USERS_URL, HTTP_X_ACTIVE_ROLE='client')

        self.assertEqual(response.status_code, 403)


class UserRoleApiTests(ApiTestCase):
    def test_staff_can_list_roles_and_filter_by_user(self):
        engineer = make_user('eng@example.com', [Role.SITE_ENGINEER])
        make_user('acc@example.com', [Role.ACCOUNTANT])
        self.sign_in(make_user('pm@example.com', [Role.OWNER]))

        response = self.client.get('/api/v1/user-roles/', {'user': engineer.pk})

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['count'], 1)
        row = response.data['results'][0]
        self.assertEqual(
            set(row), {'id', 'user_id', 'role', 'created_at', 'updated_at'},
        )
        self.assertEqual(row['role'], 'site_engineer')

    def test_client_cannot_list_roles(self):
        client_user = make_user('client@example.com', [Role.CLIENT])
        self.sign_in(client_user)

        response = self.client.get('/api/v1/user-roles/')

        self.assertEqual(response.status_code, 403)


class AuditLogApiTests(ApiTestCase):
    def test_only_admin_can_read_the_audit_log(self):
        admin = make_user('admin@example.com', [Role.ADMIN])
        AuditLog.objects.create(user=admin, action='login', entity='auth',
                                entity_id=admin.pk)
        self.sign_in(admin)
        self.assertEqual(self.client.get('/api/v1/audit-logs/').status_code, 200)

        self.sign_in(make_user('pm@example.com', [Role.OWNER]))
        self.assertEqual(self.client.get('/api/v1/audit-logs/').status_code, 403)

    def test_audit_rows_are_newest_first_filterable_and_not_postable(self):
        admin = make_user('admin@example.com', [Role.ADMIN])
        self.sign_in(admin)
        first = AuditLog.objects.create(user=admin, action='login', entity='auth',
                                        entity_id=admin.pk)
        second = AuditLog.objects.create(user=admin, action='user_updated', entity='user',
                                         entity_id=42)

        listing = self.client.get('/api/v1/audit-logs/')
        filtered = self.client.get('/api/v1/audit-logs/',
                                   {'entity': 'user', 'entity_id': 42})
        posted = self.client.post('/api/v1/audit-logs/', {
            'action': 'forged', 'entity': 'auth', 'entity_id': 1,
        }, format='json')

        self.assertEqual(listing.data['results'][0]['id'], second.pk)
        self.assertEqual(listing.data['results'][1]['id'], first.pk)
        self.assertEqual([row['id'] for row in filtered.data['results']], [second.pk])
        self.assertEqual(posted.status_code, 405)
        self.assertFalse(AuditLog.objects.filter(action='forged').exists())


class NotificationApiTests(ApiTestCase):
    def test_a_user_sees_and_marks_only_their_own_notifications(self):
        mine = make_user('mine@example.com', [Role.SITE_ENGINEER])
        other = make_user('other@example.com', [Role.SITE_ENGINEER])
        own_note = Notification.objects.create(user=mine, type='todo_done',
                                               message='Todo approved')
        other_note = Notification.objects.create(user=other, type='todo_done',
                                                 message='Not yours')
        self.sign_in(mine)

        listing = self.client.get('/api/v1/notifications/')
        stolen = self.client.post(f'/api/v1/notifications/{other_note.pk}/read/',
                                  {}, format='json')
        marked = self.client.post(f'/api/v1/notifications/{own_note.pk}/read/',
                                  {}, format='json')
        all_read = self.client.post('/api/v1/notifications/read-all/', {}, format='json')

        self.assertEqual([row['id'] for row in listing.data['results']], [own_note.pk])
        self.assertEqual(stolen.status_code, 404)
        other_note.refresh_from_db()
        self.assertFalse(other_note.is_read)
        self.assertEqual(marked.status_code, 200, marked.data)
        own_note.refresh_from_db()
        self.assertTrue(own_note.is_read)
        self.assertEqual(all_read.status_code, 200)

    def test_notifications_are_not_postable_and_need_sign_in(self):
        response = self.client.get('/api/v1/notifications/')

        self.assertEqual(response.status_code, 401)


class ThrottleTests(ApiTestCase):
    def test_login_attempts_are_throttled_per_ip(self):
        # Distinct emails, so only the per-IP scope can answer 429
        # (the per-account scope is covered in tests_throttling.py).
        statuses = [
            self.client.post(
                LOGIN_URL, {'email': f'ghost{n}@example.com', 'password': 'wrong-pass-1'},
                format='json',
            ).status_code
            for n in range(11)
        ]

        self.assertEqual(statuses[:10], [400] * 10)
        self.assertEqual(statuses[10], 429)

    def test_password_reset_requests_are_throttled(self):
        url = '/api/v1/auth/password-reset-request/'

        statuses = [
            self.client.post(url, {'email': 'ghost@example.com'}, format='json').status_code
            for _ in range(6)
        ]

        self.assertEqual(statuses[:5], [204] * 5)
        self.assertEqual(statuses[5], 429)

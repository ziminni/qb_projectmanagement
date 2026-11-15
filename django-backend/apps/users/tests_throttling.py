"""Phase 5 hardening: login is throttled per account (normalized email) as well
as per IP, and the account throttle never reveals whether an email exists.
"""

from django.conf import settings
from django.core.cache import cache
from django.test import override_settings
from rest_framework.test import APITestCase

from .models import Role
from .tests import DEMO_PASSWORD, make_user

LOGIN_URL = '/api/v1/auth/login/'

# High per-IP and default rates so only the per-account limit can answer 429.
TEST_REST_FRAMEWORK = dict(
    settings.REST_FRAMEWORK,
    DEFAULT_THROTTLE_RATES=dict(
        settings.REST_FRAMEWORK['DEFAULT_THROTTLE_RATES'],
        login='1000/min',
        login_email='5/min',
        anon='10000/min',
        user='10000/min',
    ),
)


@override_settings(REST_FRAMEWORK=TEST_REST_FRAMEWORK)
class AccountLoginThrottleTests(APITestCase):
    def setUp(self):
        cache.clear()

    def attempt(self, email, password='wrong-pass-1'):  # noqa: S107 - test fixture
        return self.client.post(LOGIN_URL, {'email': email, 'password': password}, format='json')

    def exhaust(self, email):
        return [self.attempt(email).status_code for _ in range(5)]

    def test_sixth_wrong_password_for_one_account_is_throttled(self):
        make_user('maria@example.com', [Role.ADMIN])

        self.assertEqual(self.exhaust('maria@example.com'), [400] * 5)
        self.assertEqual(self.attempt('maria@example.com').status_code, 429)

    def test_throttled_account_does_not_lock_out_another_account(self):
        make_user('maria@example.com', [Role.ADMIN])
        make_user('ramon@example.com', [Role.SITE_ENGINEER])

        self.exhaust('maria@example.com')

        response = self.attempt('ramon@example.com', DEMO_PASSWORD)

        self.assertEqual(response.status_code, 200, response.data)

    def test_email_case_and_spacing_share_one_account_bucket(self):
        make_user('maria@example.com', [Role.ADMIN])

        for email in ('maria@example.com', ' MARIA@Example.com ', 'Maria@EXAMPLE.com',
                      'maria@example.COM', '  maria@example.com'):
            self.assertEqual(self.attempt(email).status_code, 400, email)

        self.assertEqual(self.attempt('maria@example.com').status_code, 429)

    def test_unknown_email_is_throttled_exactly_like_a_real_one(self):
        make_user('maria@example.com', [Role.ADMIN])

        self.assertEqual(self.exhaust('ghost@example.com'), [400] * 5)
        throttled = self.attempt('ghost@example.com')

        self.assertEqual(throttled.status_code, 429)
        self.assertNotIn('ghost@example.com', str(throttled.data))
        self.assertEqual(set(throttled.data), {'detail'})

    def test_throttle_answer_is_the_same_for_a_known_and_an_unknown_email(self):
        make_user('maria@example.com', [Role.ADMIN])

        self.exhaust('maria@example.com')
        known = self.attempt('maria@example.com')
        self.exhaust('ghost@example.com')
        unknown = self.attempt('ghost@example.com')

        self.assertEqual(known.status_code, unknown.status_code)
        self.assertEqual(set(known.data), set(unknown.data))
        self.assertNotIn('maria@example.com', str(known.data))

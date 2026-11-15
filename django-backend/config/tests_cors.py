"""The desktop/web client sends `X-Active-Role`; the preflight must allow it."""

from django.test import TestCase


class CorsPreflightTests(TestCase):
    def test_preflight_allows_the_active_role_header(self):
        response = self.client.options(
            '/api/v1/auth/login/',
            HTTP_ORIGIN='http://127.0.0.1:18054',
            HTTP_ACCESS_CONTROL_REQUEST_METHOD='GET',
            HTTP_ACCESS_CONTROL_REQUEST_HEADERS='authorization,x-active-role',
        )

        allowed = response['Access-Control-Allow-Headers'].lower()
        self.assertIn('x-active-role', allowed)
        self.assertIn('authorization', allowed)

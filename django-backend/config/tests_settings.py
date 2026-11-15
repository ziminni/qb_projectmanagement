"""Phase 5 hardening: `config.settings` must fail closed outside DEBUG.

Each check imports the settings module in a fresh subprocess, because the
failure happens at import time (`ImproperlyConfigured`) and the module is
evaluated once per process.
"""

import os
import subprocess
import sys
from pathlib import Path

from django.test import SimpleTestCase

BACKEND_DIR = Path(__file__).resolve().parent.parent

GOOD_SECRET = 'k' * 64
DEV_SECRET = 'django-insecure-cpms-dev-only-key-change-me-in-production'  # noqa: S105 - the shipped dev default, not a credential

# Every env var these tests own; anything else the runner set is inherited.
MANAGED = (
    'DJANGO_DEBUG',
    'DJANGO_SECRET_KEY',
    'DJANGO_ALLOWED_HOSTS',
    'CORS_ALLOW_ALL_ORIGINS',
    'CORS_ALLOWED_ORIGINS',
    'POSTGRES_PASSWORD',
)

PROBE = (
    'import config.settings as s\n'
    "print(s.DEBUG)\n"
    "print(s.SESSION_COOKIE_SECURE, s.CSRF_COOKIE_SECURE)\n"
    "print(s.SECURE_HSTS_SECONDS)\n"
    "print(s.SECURE_PROXY_SSL_HEADER)\n"
    "print(s.ALLOWED_HOSTS)\n"
    "print(s.DATABASES['default']['PASSWORD'])\n"
)


def import_settings(**env):
    """Import config.settings in a subprocess with exactly `env` overlaid."""
    base = {k: v for k, v in os.environ.items() if k not in MANAGED}
    base.update(env)
    return subprocess.run(
        [sys.executable, '-c', f'{PROBE}'],
        cwd=str(BACKEND_DIR),
        env=base,
        capture_output=True,
        text=True,
        timeout=60,
    )


class FailClosedTests(SimpleTestCase):
    def assertRefused(self, result, variable):
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn('ImproperlyConfigured', result.stderr)
        self.assertIn(variable, result.stderr)

    def production(self, **overrides):
        env = {
            'DJANGO_DEBUG': 'False',
            'DJANGO_SECRET_KEY': GOOD_SECRET,
            'DJANGO_ALLOWED_HOSTS': 'cpms.example.com',
            'CORS_ALLOW_ALL_ORIGINS': 'False',
            'CORS_ALLOWED_ORIGINS': 'https://cpms.example.com',
        }
        env.update(overrides)
        return import_settings(**env)

    def test_debug_off_without_a_secret_key_refuses_to_start(self):
        result = import_settings(
            DJANGO_DEBUG='False',
            DJANGO_ALLOWED_HOSTS='cpms.example.com',
            CORS_ALLOW_ALL_ORIGINS='False',
        )

        self.assertRefused(result, 'DJANGO_SECRET_KEY')

    def test_debug_off_with_the_dev_default_secret_refuses_to_start(self):
        self.assertRefused(self.production(DJANGO_SECRET_KEY=DEV_SECRET), 'DJANGO_SECRET_KEY')

    def test_debug_off_with_a_wildcard_allowed_hosts_refuses_to_start(self):
        self.assertRefused(self.production(DJANGO_ALLOWED_HOSTS='*'), 'DJANGO_ALLOWED_HOSTS')

    def test_debug_off_with_the_wildcard_default_allowed_hosts_refuses_to_start(self):
        result = import_settings(
            DJANGO_DEBUG='False',
            DJANGO_SECRET_KEY=GOOD_SECRET,
            CORS_ALLOW_ALL_ORIGINS='False',
        )

        self.assertRefused(result, 'DJANGO_ALLOWED_HOSTS')

    def test_debug_off_with_cors_allow_all_refuses_to_start(self):
        self.assertRefused(self.production(CORS_ALLOW_ALL_ORIGINS='True'), 'CORS_ALLOW_ALL_ORIGINS')

    def test_every_production_problem_is_named_in_one_error(self):
        result = import_settings(DJANGO_DEBUG='False', CORS_ALLOW_ALL_ORIGINS='True')

        self.assertRefused(result, 'DJANGO_SECRET_KEY')
        for variable in ('DJANGO_ALLOWED_HOSTS', 'CORS_ALLOW_ALL_ORIGINS'):
            self.assertIn(variable, result.stderr)


class ProductionDefaultsTests(SimpleTestCase):
    def test_production_turns_on_secure_transport_settings(self):
        result = import_settings(
            DJANGO_DEBUG='False',
            DJANGO_SECRET_KEY=GOOD_SECRET,
            DJANGO_ALLOWED_HOSTS='cpms.example.com',
            CORS_ALLOW_ALL_ORIGINS='False',
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        lines = result.stdout.strip().splitlines()
        self.assertEqual(lines[0], 'False')
        self.assertEqual(lines[1], 'True True')
        self.assertGreater(int(lines[2]), 0)
        self.assertEqual(lines[3], "('HTTP_X_FORWARDED_PROTO', 'https')")
        self.assertEqual(lines[4], "['cpms.example.com']")

    def test_debug_stays_easy_with_the_dev_defaults(self):
        result = import_settings()

        self.assertEqual(result.returncode, 0, result.stderr)
        lines = result.stdout.strip().splitlines()
        self.assertEqual(lines[0], 'True')
        self.assertEqual(lines[1], 'False False')
        self.assertEqual(lines[2], '0')
        self.assertEqual(lines[3], 'None')
        self.assertEqual(lines[4], "['*']")

    def test_postgres_credentials_come_from_the_environment(self):
        result = import_settings(POSTGRES_PASSWORD='from-env-pass')  # noqa: S106 - test fixture

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip().splitlines()[5], 'from-env-pass')

"""Tests for admin-only system security, JWT sessions, and database backups."""

import gzip
import hashlib
import tempfile
from pathlib import Path

from django.core.files.uploadedfile import SimpleUploadedFile
from django.core.management import call_command
from django.test import override_settings
from rest_framework import status
from rest_framework_simplejwt.token_blacklist.models import (
    BlacklistedToken,
    OutstandingToken,
)
from rest_framework_simplejwt.tokens import RefreshToken

from apps.company.models import Company
from . import lockout
from .models import AuditLog, Role, SystemBackupSchedule, SystemSecurityPolicy, User
from .tests_api import ApiTestCase


class SystemSecurityAndBackupTests(ApiTestCase):
    def setUp(self):
        super().setUp()
        self.company = Company.objects.create(name='Queen Builders')
        self.admin = User.objects.create_user(
            email='sysadmin@example.ph',
            password='password123',
            full_name='Sys Admin',
            company=self.company,
            roles=[Role.ADMIN],
        )
        self.owner = User.objects.create_user(
            email='sysowner@example.ph',
            password='password123',
            full_name='Sys Owner',
            company=self.company,
            roles=[Role.OWNER],
        )

    def test_non_admin_forbidden_on_system_endpoints(self):
        self.sign_in(self.owner)
        for method, path in (
            ('get', '/api/v1/system/security/'),
            ('post', '/api/v1/system/security/sessions/1/revoke/'),
            ('patch', '/api/v1/system/security/policy/'),
            ('get', '/api/v1/system/backups/'),
            ('post', '/api/v1/system/backups/'),
            ('post', '/api/v1/system/backups/restore/'),
            ('patch', '/api/v1/system/backups/schedule/'),
            ('get', '/api/v1/system/backups/foo/download/'),
        ):
            res = getattr(self.client, method)(path, format='json')
            self.assertEqual(res.status_code, status.HTTP_403_FORBIDDEN, path)

    def test_security_overview_and_session_revoke(self):
        refresh = RefreshToken.for_user(self.owner)
        token_row = OutstandingToken.objects.get(jti=refresh['jti'])
        AuditLog.objects.create(
            user=self.owner,
            action='login',
            entity='auth',
            entity_id=self.owner.pk,
        )
        AuditLog.objects.create(
            user=self.owner,
            action='login_failed',
            entity='auth',
            entity_id=self.owner.pk,
        )

        self.sign_in(self.admin)
        res = self.client.get('/api/v1/system/security/')
        self.assertEqual(res.status_code, status.HTTP_200_OK)
        self.assertTrue(any(s['id'] == token_row.pk for s in res.data['sessions']))
        self.assertEqual(len(res.data['events']), 2)
        self.assertEqual(res.data['policy']['min_password_length'], 8)

        revoke = self.client.post(
            f'/api/v1/system/security/sessions/{token_row.pk}/revoke/',
            format='json',
        )
        self.assertEqual(revoke.status_code, status.HTTP_200_OK)
        self.assertTrue(BlacklistedToken.objects.filter(token=token_row).exists())
        self.assertTrue(
            AuditLog.objects.filter(action='logout', entity='session', entity_id=token_row.pk).exists()
        )

        res_after = self.client.get('/api/v1/system/security/')
        self.assertFalse(any(s['id'] == token_row.pk for s in res_after.data['sessions']))

    def test_security_policy_patch_updates_lockout_and_audits(self):
        original = lockout.MAX_FAILURES
        self.addCleanup(setattr, lockout, 'MAX_FAILURES', original)

        self.sign_in(self.admin)
        res = self.client.patch(
            '/api/v1/system/security/policy/',
            {
                'min_password_length': 12,
                'idle_timeout_minutes': 45,
                'max_failed_logins': 3,
                'require_manager_override': False,
            },
            format='json',
        )
        self.assertEqual(res.status_code, status.HTTP_200_OK)
        self.assertEqual(lockout.MAX_FAILURES, 3)

        policy = SystemSecurityPolicy.objects.get(pk=1)
        self.assertEqual(policy.min_password_length, 12)
        self.assertEqual(policy.idle_timeout_minutes, 45)
        self.assertFalse(policy.require_manager_override)
        self.assertTrue(
            AuditLog.objects.filter(action='settings_updated', entity='security_policy').exists()
        )

    def test_backup_create_list_download_restore_and_schedule(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            with override_settings(MEDIA_ROOT=tmpdir):
                self.sign_in(self.admin)

                # Update schedule with retention=2
                sched = self.client.patch(
                    '/api/v1/system/backups/schedule/',
                    {'frequency': 'weekly', 'retention_count': 2},
                    format='json',
                )
                self.assertEqual(sched.status_code, status.HTTP_200_OK)
                self.assertEqual(
                    SystemBackupSchedule.objects.get(pk=1).frequency,
                    'weekly',
                )

                # Create 3 backups -> retention keeps 2
                created_ids = []
                for _ in range(3):
                    create = self.client.post('/api/v1/system/backups/', format='json')
                    self.assertEqual(create.status_code, status.HTTP_201_CREATED)
                    created_ids.append(create.data['id'])

                listing = self.client.get('/api/v1/system/backups/')
                self.assertEqual(listing.status_code, status.HTTP_200_OK)
                self.assertEqual(len(listing.data['backups']), 2)
                latest = listing.data['backups'][0]
                self.assertGreater(latest['size_bytes'], 0)
                self.assertEqual(len(latest['sha256']), 64)

                # Download works and matches SHA-256
                dl = self.client.get(f'/api/v1/system/backups/{latest["id"]}/download/')
                self.assertEqual(dl.status_code, status.HTTP_200_OK)
                content = b''.join(dl.streaming_content)
                self.assertEqual(hashlib.sha256(content).hexdigest(), latest['sha256'])

                # Restore succeeds
                restore = self.client.post(
                    '/api/v1/system/backups/restore/',
                    {'id': latest['id']},
                    format='json',
                )
                self.assertEqual(restore.status_code, status.HTTP_200_OK)
                self.assertTrue(
                    AuditLog.objects.filter(action='backup_restored', entity='backup').exists()
                )

                # Tampered file fails checksum verification
                archive = Path(tmpdir) / 'backups' / f'{latest["id"]}.json.gz'
                archive.write_bytes(b'corrupted')
                bad_restore = self.client.post(
                    '/api/v1/system/backups/restore/',
                    {'id': latest['id']},
                    format='json',
                )
                self.assertEqual(bad_restore.status_code, status.HTTP_400_BAD_REQUEST)

                # Upload & restore valid archive
                empty_dump = gzip.compress(b'[]')
                upload = SimpleUploadedFile(
                    'manual.json.gz',
                    empty_dump,
                    content_type='application/gzip',
                )
                up_res = self.client.post(
                    '/api/v1/system/backups/upload-restore/',
                    {'file': upload},
                    format='multipart',
                )
                self.assertEqual(up_res.status_code, status.HTTP_200_OK)

                # Scheduled backup command runs cleanly
                call_command('run_scheduled_backup', force=True)

    def test_revoke_all_and_system_health_and_audit_user_filter(self):
        RefreshToken.for_user(self.owner)
        RefreshToken.for_user(self.admin)
        AuditLog.objects.create(
            user=self.owner,
            action='login',
            entity='auth',
            entity_id=self.owner.pk,
        )

        self.sign_in(self.admin)
        rev = self.client.post(
            '/api/v1/system/security/sessions/revoke-all/',
            {'user_id': self.owner.pk},
            format='json',
        )
        self.assertEqual(rev.status_code, status.HTTP_200_OK)
        self.assertEqual(rev.data['count'], 1)

        health = self.client.get('/api/v1/system/health/')
        self.assertEqual(health.status_code, status.HTTP_200_OK)
        self.assertEqual(health.data['database'], 'ok')
        self.assertIn('storage', health.data)
        self.assertIn('pos_bridge', health.data)

        logs = self.client.get(f'/api/v1/audit-logs/?user={self.owner.pk}')
        self.assertEqual(logs.status_code, status.HTTP_200_OK)
        results = logs.data['results'] if isinstance(logs.data, dict) else logs.data
        self.assertEqual(len(results), 1)

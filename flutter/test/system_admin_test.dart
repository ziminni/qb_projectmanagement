import 'package:buildpro_frontend/core/network/api_client.dart';
import 'package:buildpro_frontend/data/models/system_admin.dart';
import 'package:buildpro_frontend/data/repositories/http_system_admin_repository.dart';
import 'package:buildpro_frontend/data/services/session_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'network/fake_api.dart';
import 'test_helpers.dart';

void main() {
  setUp(resetServices);

  group('HttpSystemAdminRepository', () {
    test('calls all security and backup endpoints', () async {
      final calls = <(String, String)>[];
      final fake = FakeApi((req) async {
        calls.add((req.method, req.uri.path));
        if (req.uri.path.endsWith('system/security/')) {
          return json({
            'sessions': [
              {
                'id': 1,
                'user_id': 2,
                'user_email': 'ramon@example.ph',
                'user_name': 'Ramon',
                'jti': 'jti-123',
                'created_at': '2026-11-20T00:00:00Z',
                'expires_at': '2026-11-27T00:00:00Z',
              },
            ],
            'events': [
              {
                'id': 10,
                'user_id': 2,
                'user_email': 'ramon@example.ph',
                'user_name': 'Ramon',
                'action': 'login',
                'details': {},
                'created_at': '2026-11-20T00:00:00Z',
              },
            ],
            'policy': {
              'min_password_length': 10,
              'idle_timeout_minutes': 45,
              'max_failed_logins': 4,
              'require_manager_override': true,
            },
          });
        }
        if (req.uri.path.endsWith('system/security/sessions/1/revoke/')) {
          return json({'detail': 'Session revoked.', 'id': 1});
        }
        if (req.uri.path.endsWith('system/security/policy/')) {
          return json({
            'min_password_length': 12,
            'idle_timeout_minutes': 60,
            'max_failed_logins': 3,
            'require_manager_override': false,
          });
        }
        if (req.uri.path.endsWith('system/backups/') && req.method == 'GET') {
          return json({
            'backups': [
              {
                'id': 'snap-1',
                'filename': 'snap-1.json.gz',
                'size_bytes': 1024,
                'sha256': 'abc123',
                'created_at': '2026-11-20T00:00:00Z',
              },
            ],
            'schedule': {'frequency': 'daily', 'retention_count': 7},
          });
        }
        if (req.uri.path.endsWith('system/backups/') && req.method == 'POST') {
          return json({
            'id': 'snap-2',
            'filename': 'snap-2.json.gz',
            'size_bytes': 2048,
            'sha256': 'def456',
            'created_at': '2026-11-20T01:00:00Z',
          }, status: 201);
        }
        if (req.uri.path.endsWith('system/backups/snap-1/download/')) {
          return bytesBody([1, 2, 3]);
        }
        if (req.uri.path.endsWith('system/backups/restore/')) {
          return json({'detail': 'Backup restored.', 'id': 'snap-1'});
        }
        if (req.uri.path.endsWith('system/backups/schedule/')) {
          return json({'frequency': 'weekly', 'retention_count': 14});
        }
        if (req.uri.path.endsWith('system/security/sessions/revoke-all/')) {
          return json({'detail': 'Revoked 2 session(s).', 'count': 2});
        }
        if (req.uri.path.endsWith('system/backups/upload-restore/')) {
          return json({'detail': 'Uploaded backup restored.', 'id': 'up-1'});
        }
        if (req.uri.path.endsWith('system/health/')) {
          return json({
            'database': 'ok',
            'storage': {
              'backups_bytes': 100,
              'reports_bytes': 200,
              'documents_bytes': 300,
              'total_bytes': 600,
            },
            'pos_bridge': {
              'base_url': 'http://127.0.0.1:8000',
              'pending_count': 0,
              'failed_count': 1,
              'synced_count': 5,
              'pos_reachable': true,
              'jobs': [],
            },
          });
        }
        if (req.uri.path.endsWith('system/pos-sync/1/retry/')) {
          return json({'detail': 'Sync job re-queued.', 'id': 1});
        }
        return json({}, status: 404);
      });

      final dio = Dio()..httpClientAdapter = fake;
      final client = ApiClient(
        tokens: InMemoryTokenStore(),
        session: SessionService(),
        dio: dio,
      );
      final repo = HttpSystemAdminRepository(client);
      final sec = await repo.getSecurityOverview();
      expect(sec.sessions, hasLength(1));
      expect(sec.events, hasLength(1));
      expect(sec.policy.minPasswordLength, 10);

      await repo.revokeSession(1);
      final policy = await repo.updateSecurityPolicy(
        const SecurityPolicy(
          minPasswordLength: 12,
          idleTimeoutMinutes: 60,
          maxFailedLogins: 3,
          requireManagerOverride: false,
        ),
      );
      expect(policy.minPasswordLength, 12);

      final backups = await repo.getBackups();
      expect(backups.backups, hasLength(1));
      final created = await repo.createBackup();
      expect(created.id, 'snap-2');
      final bytes = await repo.downloadBackup('snap-1');
      expect(bytes, [1, 2, 3]);
      await repo.restoreBackup('snap-1');
      final sched = await repo.updateBackupSchedule(
        const BackupSchedule(frequency: 'weekly', retentionCount: 14),
      );
      expect(sched.frequency, 'weekly');

      expect(await repo.revokeAllSessions(), 2);
      final health = await repo.getSystemHealth(probePos: true);
      expect(health.database, 'ok');
      expect(health.posBridge.posReachable, isTrue);
      await repo.retryPosSync(1);
      expect(calls, hasLength(11));
    });
  });

  testWidgets('admin can open Security & sessions and Database backups pages', (
    tester,
  ) async {
    await pumpApp(tester);
    await signInAs(tester, 'maria@example.ph');

    await goTo(tester, '/admin/security');
    expect(find.text('Active JWT sessions'), findsOneWidget);
    expect(find.text('Recent authentication events'), findsOneWidget);
    await tester.ensureVisible(find.text('Revoke').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Revoke').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Revoke'));
    await tester.pumpAndSettle();

    await goTo(tester, '/admin/backups');
    expect(find.text('Automated backup schedule'), findsOneWidget);
    expect(find.text('Server snapshots'), findsWidgets);
    await tester.ensureVisible(find.text('Create backup'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create backup'));
    await tester.pumpAndSettle();

    await goTo(tester, '/admin/health');
    expect(find.text('POS outbox queue'), findsOneWidget);
    expect(find.text('Storage breakdown'), findsOneWidget);
    await tester.tap(find.text('Retry sync'));
    await tester.pumpAndSettle();
  });
}

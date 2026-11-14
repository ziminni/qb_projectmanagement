import 'package:buildpro_frontend/data/repositories/http_audit_log_repository.dart';
import 'package:buildpro_frontend/data/repositories/http_notification_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_api.dart';

void main() {
  group('http audit log repository', () {
    test('writes no entry itself: the server records it', () async {
      final api = FakeApi((options) => json([]));
      final repo = HttpAuditLogRepository(
        testClient(api: api, tokens: InMemoryTokenStore()),
      );

      final log = await repo.record(
        userId: 3,
        action: 'todo_verified',
        entity: 'todo',
        entityId: 9,
        details: const {'project_id': 1},
      );

      expect(api.requests, isEmpty);
      expect(log.userId, 3);
      expect(log.action, 'todo_verified');
      expect(log.entityId, 9);
      expect(log.details['project_id'], 1);
    });

    test('reads the newest entries for an entity', () async {
      final api = FakeApi(
        (options) => json({
          'count': 1,
          'results': [
            {
              'id': 5,
              'user_id': 3,
              'action': 'todo_verified',
              'entity': 'todo',
              'entity_id': 9,
              'details': {'project_id': 1},
              'created_at': '2026-11-14T08:00:00Z',
            },
          ],
        }),
      );
      final repo = HttpAuditLogRepository(
        testClient(api: api, tokens: InMemoryTokenStore()),
      );

      final logs = await repo.getFor('todo', 9);

      final request = api.last('audit-logs/');
      expect(request.queryParameters['entity'], 'todo');
      expect(request.queryParameters['entity_id'], 9);
      expect(logs.single.id, 5);
    });

    test('reads every entry for the admin audit page', () async {
      final api = FakeApi(
        (options) => json([
          {
            'id': 1,
            'user_id': 1,
            'action': 'login',
            'entity': 'user',
            'entity_id': 1,
            'details': {},
            'created_at': '2026-11-13T08:00:00Z',
          },
        ]),
      );
      final repo = HttpAuditLogRepository(
        testClient(api: api, tokens: InMemoryTokenStore()),
      );

      final logs = await repo.getAll();

      expect(api.last('audit-logs/').queryParameters, isEmpty);
      expect(logs.single.action, 'login');
    });
  });

  group('http notification repository', () {
    test('sends no notification itself: the server creates them', () async {
      final api = FakeApi((options) => json([]));
      final repo = HttpNotificationRepository(
        testClient(api: api, tokens: InMemoryTokenStore()),
      );

      final notification = await repo.create(
        userId: 3,
        type: 'todo_done',
        message: 'Verify the rebar.',
        link: '/todo-verification',
      );

      expect(api.requests, isEmpty);
      expect(notification.userId, 3);
      expect(notification.type, 'todo_done');
      expect(notification.isRead, isFalse);
    });

    test("reads only the caller's notifications", () async {
      final api = FakeApi(
        (options) => json([
          {
            'id': 2,
            'user_id': 7,
            'type': 'todo_done',
            'message': 'Verify the rebar.',
            'link': null,
            'is_read': false,
            'created_at': '2026-11-14T08:00:00Z',
          },
        ]),
      );
      final repo = HttpNotificationRepository(
        testClient(api: api, tokens: InMemoryTokenStore()),
      );

      final items = await repo.getFor(7);

      expect(api.last('notifications/').method, 'GET');
      expect(items.single.id, 2);
    });

    test('marks one notification read', () async {
      final api = FakeApi((options) => noContent());
      final repo = HttpNotificationRepository(
        testClient(api: api, tokens: InMemoryTokenStore()),
      );

      await repo.markRead(2);

      final request = api.last('notifications/2/read/');
      expect(request.method, 'POST');
    });

    test('marks every notification read', () async {
      final api = FakeApi((options) => noContent());
      final repo = HttpNotificationRepository(
        testClient(api: api, tokens: InMemoryTokenStore()),
      );

      await repo.markAllRead(7);

      expect(api.last('notifications/read-all/').method, 'POST');
    });
  });
}

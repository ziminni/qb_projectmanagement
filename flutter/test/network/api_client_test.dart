import 'dart:async';

import 'package:buildpro_frontend/data/models/app_role.dart';
import 'package:buildpro_frontend/data/services/business_rule_exception.dart';
import 'package:buildpro_frontend/data/services/session_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_api.dart';

void main() {
  group('api client', () {
    test('sends the access token and the active role on every call', () async {
      final api = FakeApi((options) => json([]));
      final client = testClient(
        api: api,
        tokens: InMemoryTokenStore(access: testAccess, refresh: testRefresh),
        session: signedInSession(
          roles: const [AppRole.admin, AppRole.owner],
          active: AppRole.owner,
        ),
      );

      await client.get('users/');

      final request = api.last('users/');
      expect(request.headers['Authorization'], 'Bearer $testAccess');
      expect(request.headers['X-Active-Role'], 'owner');
      expect(request.method, 'GET');
    });

    test('omits the role header before a role is chosen', () async {
      final api = FakeApi((options) => json([]));
      final client = testClient(
        api: api,
        tokens: InMemoryTokenStore(),
        session: SessionService(),
      );

      await client.get('users/');

      expect(api.last('users/').headers.containsKey('X-Active-Role'), isFalse);
      expect(api.last('users/').headers.containsKey('Authorization'), isFalse);
    });

    test('refreshes once for two requests that fail together', () async {
      final gate = Completer<void>();
      final api = FakeApi((options) async {
        if (options.path == 'auth/refresh/') {
          return json({'access': 'access-2', 'refresh': 'refresh-2'});
        }
        if (options.headers['Authorization'] == 'Bearer $testAccess') {
          await gate.future;
          return json({'detail': 'Given token not valid'}, status: 401);
        }
        return json([
          {'path': options.path},
        ]);
      });
      final tokens = InMemoryTokenStore(
        access: testAccess,
        refresh: testRefresh,
      );
      final client = testClient(api: api, tokens: tokens);

      final users = client.get('users/');
      final roles = client.get('user-roles/');
      await pumpEventQueue();
      gate.complete();
      await Future.wait([users, roles]);

      expect(api.countOf('auth/refresh/'), 1);
      expect(tokens.access, 'access-2');
      expect(tokens.refresh, 'refresh-2');
      expect(api.countOf('users/'), 2);
    });

    test('signs out when the refresh answer carries no access token', () async {
      final api = FakeApi(
        (options) => options.path == 'auth/refresh/'
            ? json({'detail': 'refresh returned nothing useful'})
            : json({'detail': 'Given token not valid'}, status: 401),
      );
      final tokens = InMemoryTokenStore(
        access: testAccess,
        refresh: testRefresh,
      );
      final session = signedInSession();
      final client = testClient(api: api, tokens: tokens, session: session);

      await expectLater(
        client.get('users/'),
        throwsA(
          isA<BusinessRuleException>().having(
            (e) => e.message,
            'message',
            'Your session has expired. Sign in again.',
          ),
        ),
      );

      expect(tokens.access, isNull);
      expect(tokens.refresh, isNull);
      expect(session.isSignedIn, isFalse);
    });

    test('follows every page of a paginated list', () async {
      final api = FakeApi((options) {
        final second = options.uri.queryParameters['page'] == '2';
        return json({
          'count': 2,
          'next': second ? null : 'http://cpms.test/api/v1/users/?page=2',
          'previous': null,
          'results': [
            {'id': second ? 2 : 1},
          ],
        });
      });
      final client = testClient(
        api: api,
        tokens: InMemoryTokenStore(access: testAccess, refresh: testRefresh),
      );

      final rows = await client.getRows('users/');

      expect(rows.map((row) => row['id']), [1, 2]);
      expect(api.requests, hasLength(2));
      expect(api.requests.last.uri.queryParameters['page'], '2');
      expect(api.requests.last.headers['Authorization'], 'Bearer $testAccess');
    });

    test('reads a bare list without asking for a second page', () async {
      final api = FakeApi(
        (options) => json([
          {'id': 1},
        ]),
      );
      final client = testClient(
        api: api,
        tokens: InMemoryTokenStore(access: testAccess, refresh: testRefresh),
      );

      final rows = await client.getRows('users/');

      expect(rows, hasLength(1));
      expect(api.requests, hasLength(1));
    });

    test('refuses a list that never ends', () async {
      final api = FakeApi(
        (options) => json({
          'count': 1,
          'next': 'http://cpms.test/api/v1/users/?page=2',
          'results': <Object>[],
        }),
      );
      final client = testClient(
        api: api,
        tokens: InMemoryTokenStore(access: testAccess, refresh: testRefresh),
      );

      await expectLater(
        client.getRows('users/'),
        throwsA(
          isA<BusinessRuleException>().having(
            (e) => e.message,
            'message',
            contains('page'),
          ),
        ),
      );
      expect(api.requests, hasLength(200));
    });

    test('signs out and forgets the tokens when the refresh fails', () async {
      final api = FakeApi(
        (options) => options.path == 'auth/refresh/'
            ? json({'detail': 'Token is invalid or expired'}, status: 401)
            : json({'detail': 'Given token not valid'}, status: 401),
      );
      final tokens = InMemoryTokenStore(
        access: testAccess,
        refresh: testRefresh,
      );
      final session = signedInSession();
      final client = testClient(api: api, tokens: tokens, session: session);

      await expectLater(
        client.get('users/'),
        throwsA(
          isA<BusinessRuleException>().having(
            (e) => e.message,
            'message',
            'Your session has expired. Sign in again.',
          ),
        ),
      );

      expect(tokens.access, isNull);
      expect(tokens.refresh, isNull);
      expect(session.isSignedIn, isFalse);
    });

    test('does not refresh a request that was never signed in', () async {
      final api = FakeApi(
        (options) => json({
          'detail': 'Authentication credentials required.',
        }, status: 401),
      );
      final tokens = InMemoryTokenStore();
      final client = testClient(api: api, tokens: tokens);

      await expectLater(
        client.get('users/'),
        throwsA(isA<BusinessRuleException>()),
      );

      expect(api.countOf('auth/refresh/'), 0);
      expect(tokens.clearCalls, greaterThan(0));
    });

    test('shows the server detail text as-is', () async {
      final api = FakeApi(
        (options) =>
            json({'detail': 'Incorrect email or password.'}, status: 400),
      );
      final client = testClient(
        api: api,
        tokens: InMemoryTokenStore(access: testAccess, refresh: testRefresh),
      );

      await expectLater(
        client.post('auth/login/', body: const {'email': 'x@example.ph'}),
        throwsA(
          isA<BusinessRuleException>().having(
            (e) => e.message,
            'message',
            'Incorrect email or password.',
          ),
        ),
      );
    });

    test('reports a server that cannot be reached', () async {
      final api = FakeApi(
        (options) => throw const SocketFailure('connection refused'),
      );
      final client = testClient(
        api: api,
        tokens: InMemoryTokenStore(access: testAccess, refresh: testRefresh),
      );

      await expectLater(
        client.get('users/'),
        throwsA(
          isA<BusinessRuleException>().having(
            (e) => e.message,
            'message',
            'Cannot reach the server. Check your connection.',
          ),
        ),
      );
    });

    test('returns null for a missing record when asked to', () async {
      final api = FakeApi(
        (options) => json({'detail': 'Not found.'}, status: 404),
      );
      final client = testClient(
        api: api,
        tokens: InMemoryTokenStore(access: testAccess, refresh: testRefresh),
      );

      expect(await client.get('users/99/', notFoundAsNull: true), isNull);
      await expectLater(
        client.get('users/99/'),
        throwsA(isA<BusinessRuleException>()),
      );
    });
  });
}

/// Stands in for a dead socket: dio reports it as an unknown error with no
/// response attached.
class SocketFailure implements Exception {
  const SocketFailure(this.message);

  final String message;
}

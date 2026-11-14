import 'dart:async';

import 'package:buildpro_frontend/core/network/api_config.dart';
import 'package:buildpro_frontend/data/models/app_role.dart';
import 'package:buildpro_frontend/data/services/business_rule_exception.dart';
import 'package:buildpro_frontend/data/services/session_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_api.dart';

/// The origin every authenticated request must stay on.
final Uri apiOrigin = Uri.parse(apiBaseUrl);
final String nextPageUrl = '$apiBaseUrl/users/?page=2';

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
          'next': second ? null : nextPageUrl,
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
        (options) =>
            json({'count': 1, 'next': nextPageUrl, 'results': <Object>[]}),
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

    test('reads a private file from the API origin with the token', () async {
      final api = FakeApi((options) => bytesBody([1, 2, 3]));
      final client = testClient(
        api: api,
        tokens: InMemoryTokenStore(access: testAccess, refresh: testRefresh),
      );

      final bytes = await client.getBytes(
        '${apiOrigin.origin}/api/v1/report-photos/4/file/pour.jpg',
      );

      expect(bytes, [1, 2, 3]);
      expect(
        api.requests.single.headers['Authorization'],
        'Bearer $testAccess',
      );
    });

    test('refuses a file url on another origin before any request', () async {
      final api = FakeApi((options) => bytesBody([1]));
      final client = testClient(
        api: api,
        tokens: InMemoryTokenStore(access: testAccess, refresh: testRefresh),
      );

      await expectLater(
        client.getBytes('https://files.example.ph/report-photos/4/file/a.jpg'),
        throwsA(
          isA<BusinessRuleException>().having(
            (e) => e.message,
            'message',
            contains('different site'),
          ),
        ),
      );

      expect(api.requests, isEmpty);
    });

    test('refuses a protocol-relative or foreign-port url', () async {
      final api = FakeApi((options) => json([]));
      final client = testClient(
        api: api,
        tokens: InMemoryTokenStore(access: testAccess, refresh: testRefresh),
      );

      await expectLater(
        client.get('//files.example.ph/api/v1/users/'),
        throwsA(isA<BusinessRuleException>()),
      );
      await expectLater(
        client.getBytes('${apiOrigin.replace(port: 8443)}/api/v1/x/file.pdf'),
        throwsA(isA<BusinessRuleException>()),
      );
      await expectLater(
        client.delete('http://files.example.ph/api/v1/documents/1/'),
        throwsA(isA<BusinessRuleException>()),
      );

      expect(api.requests, isEmpty);
    });

    test('does not send the token to a redirect on another origin', () async {
      final api = FakeApi((options) {
        if (options.path == 'documents/1/file/a.pdf') {
          return redirectTo('https://files.example.ph/a.pdf');
        }
        return bytesBody([9]);
      });
      final client = testClient(
        api: api,
        tokens: InMemoryTokenStore(access: testAccess, refresh: testRefresh),
      );

      await expectLater(
        client.getBytes('documents/1/file/a.pdf'),
        throwsA(isA<BusinessRuleException>()),
      );

      // Only the API got a request; the foreign hop was never sent.
      expect(api.requests, hasLength(1));
    });

    test('follows a redirect that stays on the API origin', () async {
      final api = FakeApi((options) {
        if (options.path == 'documents/1/file/a.pdf') {
          return redirectTo('/api/v1/documents/1/file/b.pdf');
        }
        return bytesBody([4, 5]);
      });
      final client = testClient(
        api: api,
        tokens: InMemoryTokenStore(access: testAccess, refresh: testRefresh),
      );

      final bytes = await client.getBytes('documents/1/file/a.pdf');

      expect(bytes, [4, 5]);
      expect(api.requests, hasLength(2));
      expect(api.requests.last.headers['Authorization'], 'Bearer $testAccess');
    });

    test('a cross-origin next page is refused, not followed', () async {
      final api = FakeApi(
        (options) => json({
          'count': 2,
          'next': 'https://files.example.ph/api/v1/users/?page=2',
          'previous': null,
          'results': [
            {'id': 1},
          ],
        }),
      );
      final client = testClient(
        api: api,
        tokens: InMemoryTokenStore(access: testAccess, refresh: testRefresh),
      );

      await expectLater(
        client.getRows('users/'),
        throwsA(isA<BusinessRuleException>()),
      );

      expect(api.requests, hasLength(1));
    });
  });
}

/// Stands in for a dead socket: dio reports it as an unknown error with no
/// response attached.
class SocketFailure implements Exception {
  const SocketFailure(this.message);

  final String message;
}

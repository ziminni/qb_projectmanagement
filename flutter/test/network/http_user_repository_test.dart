import 'package:buildpro_frontend/core/network/api_config.dart';
import 'package:buildpro_frontend/data/models/app_role.dart';
import 'package:buildpro_frontend/data/models/user.dart';
import 'package:buildpro_frontend/data/repositories/http_user_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_api.dart';

Map<String, dynamic> userRow(int id, {String role = 'owner'}) => {
  'id': id,
  'company_id': 1,
  'full_name': 'User $id',
  'email': 'user$id@example.ph',
  'phone': null,
  'is_active': true,
};

void main() {
  group('http user repository', () {
    test('reads the latest users from the server', () async {
      final api = FakeApi((options) => json([userRow(1), userRow(2)]));
      final repo = HttpUserRepository(
        testClient(api: api, tokens: InMemoryTokenStore()),
      );

      final users = await repo.getUsers();

      expect(users.map((u) => u.id), [1, 2]);
      expect(users.first.email, 'user1@example.ph');
    });

    test('reads a paginated page of users', () async {
      final api = FakeApi(
        (options) => json({
          'count': 1,
          'results': [userRow(1)],
        }),
      );
      final repo = HttpUserRepository(
        testClient(api: api, tokens: InMemoryTokenStore()),
      );

      expect((await repo.getUsers()).single.id, 1);
    });

    test('reads every page of users and asks for the next one', () async {
      final api = FakeApi((options) {
        final second = options.uri.queryParameters['page'] == '2';
        return json({
          'count': 3,
          'next': second ? null : '$apiBaseUrl/users/?page=2',
          'results': [
            if (!second) userRow(1),
            if (!second) userRow(2),
            if (second) userRow(3),
          ],
        });
      });
      final repo = HttpUserRepository(
        testClient(api: api, tokens: InMemoryTokenStore()),
      );

      final users = await repo.getUsers();

      expect(users.map((u) => u.id), [1, 2, 3]);
      expect(api.requests, hasLength(2));
      expect(api.requests.last.uri.queryParameters['page'], '2');
    });

    test('returns null for a user that is gone', () async {
      final api = FakeApi(
        (options) => json({'detail': 'Not found.'}, status: 404),
      );
      final repo = HttpUserRepository(
        testClient(api: api, tokens: InMemoryTokenStore()),
      );

      expect(await repo.getUser(99), isNull);
    });

    test('creates a user with their roles', () async {
      final api = FakeApi(
        (options) => json({
          'user': userRow(9),
          'roles': [
            {'id': 11, 'user_id': 9, 'role': 'site_engineer'},
          ],
          'temporary_password': 'Temp-12345',
        }, status: 201),
      );
      final repo = HttpUserRepository(
        testClient(api: api, tokens: InMemoryTokenStore()),
      );

      final saved = await repo.saveUser(
        const User(
          id: 0,
          companyId: 1,
          fullName: 'New Hand',
          email: 'new@example.ph',
          phone: '0917',
        ),
        [AppRole.siteEngineer, AppRole.siteEngineer],
      );

      final sent = sentBody(api.last('users/'));
      expect(api.last('users/').method, 'POST');
      expect(sent['full_name'], 'New Hand');
      expect(sent['email'], 'new@example.ph');
      expect(sent['is_active'], isTrue);
      expect(sent['roles'], ['site_engineer']);
      expect(saved.id, 9);
    });

    test('updates an existing user and replaces the roles', () async {
      final api = FakeApi((options) => json(userRow(4)));
      final repo = HttpUserRepository(
        testClient(api: api, tokens: InMemoryTokenStore()),
      );

      final saved = await repo.saveUser(
        const User(
          id: 4,
          companyId: 1,
          fullName: 'User 4',
          email: 'user4@example.ph',
        ),
        [AppRole.accountant],
      );

      final request = api.last('users/4/');
      expect(request.method, 'PATCH');
      expect(sentBody(request)['roles'], ['accountant']);
      expect(saved.id, 4);
    });

    test('deactivates a user with a patch', () async {
      final api = FakeApi((options) => json(userRow(4)));
      final repo = HttpUserRepository(
        testClient(api: api, tokens: InMemoryTokenStore()),
      );

      final saved = await repo.setActive(4, false);

      expect(sentBody(api.last('users/4/'))['is_active'], isFalse);
      expect(saved.id, 4);
    });

    test('lists the active users holding a role', () async {
      final api = FakeApi(
        (options) => json([
          {'id': 1, 'user_id': 1, 'role': 'owner'},
        ]),
      );
      final repo = HttpUserRepository(
        testClient(api: api, tokens: InMemoryTokenStore()),
      );

      final roles = await repo.getRoles(1);

      expect(api.last('user-roles/').queryParameters['user'], 1);
      expect(roles, [AppRole.owner]);
    });

    test('reads every user role row', () async {
      final api = FakeApi(
        (options) => json([
          {'id': 1, 'user_id': 1, 'role': 'admin'},
          {'id': 2, 'user_id': 1, 'role': 'owner'},
        ]),
      );
      final repo = HttpUserRepository(
        testClient(api: api, tokens: InMemoryTokenStore()),
      );

      final rows = await repo.getAllUserRoles();

      expect(rows.map((r) => r.role), [AppRole.admin, AppRole.owner]);
    });

    test('filters the role query on the server', () async {
      final api = FakeApi((options) => json([userRow(1), userRow(2)]));
      final repo = HttpUserRepository(
        testClient(api: api, tokens: InMemoryTokenStore()),
      );

      final users = await repo.getUsersWithRole(AppRole.owner);

      final query = api.last('users/').queryParameters;
      expect(query['role'], 'owner');
      expect(users.length, 2);
    });
  });
}

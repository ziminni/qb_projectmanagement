import 'package:buildpro_frontend/data/models/app_role.dart';
import 'package:buildpro_frontend/data/repositories/http_auth_repository.dart';
import 'package:buildpro_frontend/data/services/business_rule_exception.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_api.dart';

void main() {
  group('http auth repository', () {
    test('signs in, stores the tokens and returns the roles', () async {
      final api = FakeApi(
        (options) => json({
          'user': {
            'id': 7,
            'company_id': 1,
            'full_name': 'Maria Santos',
            'email': 'maria@example.ph',
            'phone': null,
            'is_active': true,
          },
          'roles': [
            {'id': 1, 'user_id': 7, 'role': 'admin'},
            {'id': 2, 'user_id': 7, 'role': 'owner'},
          ],
          'access': 'new-access',
          'refresh': 'new-refresh',
        }),
      );
      final tokens = InMemoryTokenStore();
      final repo = HttpAuthRepository(testClient(api: api, tokens: tokens));

      final result = await repo.signIn('maria@example.ph', 'password123');

      final sent = sentBody(api.last('auth/login/'));
      expect(sent['email'], 'maria@example.ph');
      expect(sent['password'], 'password123');
      expect(result.user.id, 7);
      expect(result.user.fullName, 'Maria Santos');
      expect(result.roles, [AppRole.admin, AppRole.owner]);
      expect(tokens.access, 'new-access');
      expect(tokens.refresh, 'new-refresh');
    });

    test('accepts role codes as well as role rows', () async {
      final api = FakeApi(
        (options) => json({
          'user': testUser.toJson(),
          'roles': ['site_engineer'],
          'access': 'a',
          'refresh': 'r',
        }),
      );
      final repo = HttpAuthRepository(
        testClient(api: api, tokens: InMemoryTokenStore()),
      );

      final result = await repo.signIn('maria@example.ph', 'password123');

      expect(result.roles, [AppRole.siteEngineer]);
    });

    test('shows the server sign-in failure and keeps no tokens', () async {
      final api = FakeApi(
        (options) =>
            json({'detail': 'Incorrect email or password.'}, status: 400),
      );
      final tokens = InMemoryTokenStore();
      final repo = HttpAuthRepository(testClient(api: api, tokens: tokens));

      await expectLater(
        repo.signIn('maria@example.ph', 'wrong'),
        throwsA(
          isA<BusinessRuleException>().having(
            (e) => e.message,
            'message',
            'Incorrect email or password.',
          ),
        ),
      );
      expect(tokens.access, isNull);
    });

    test('forgets an earlier session when sign-in fails', () async {
      final api = FakeApi(
        (options) =>
            json({'detail': 'Incorrect email or password.'}, status: 400),
      );
      final tokens = InMemoryTokenStore(
        access: 'old-access',
        refresh: 'old-refresh',
      );
      final repo = HttpAuthRepository(testClient(api: api, tokens: tokens));

      await expectLater(
        repo.signIn('maria@example.ph', 'wrong'),
        throwsA(isA<BusinessRuleException>()),
      );

      expect(tokens.access, isNull);
      expect(tokens.refresh, isNull);
    });

    test('asks for a password reset without revealing the account', () async {
      final api = FakeApi((options) => noContent());
      final repo = HttpAuthRepository(
        testClient(api: api, tokens: InMemoryTokenStore()),
      );

      await repo.requestPasswordReset('maria@example.ph');

      expect(
        sentBody(api.last('auth/password-reset-request/'))['email'],
        'maria@example.ph',
      );
    });

    test('returns the temporary password an admin reset', () async {
      final api = FakeApi(
        (options) => json({'temporary_password': 'Temp-12345'}),
      );
      final repo = HttpAuthRepository(
        testClient(api: api, tokens: InMemoryTokenStore()),
      );

      final temporary = await repo.resetPassword(7);

      expect(api.last('users/7/reset-password/').method, 'POST');
      expect(temporary, 'Temp-12345');
    });

    test('changes the signed-in user password', () async {
      final api = FakeApi((options) => noContent());
      final repo = HttpAuthRepository(
        testClient(api: api, tokens: InMemoryTokenStore()),
      );

      await repo.changePassword(
        7,
        currentPassword: 'old-pass1',
        newPassword: 'new-pass1',
      );

      final sent = sentBody(api.last('auth/change-password/'));
      expect(sent['current_password'], 'old-pass1');
      expect(sent['new_password'], 'new-pass1');
    });
  });
}

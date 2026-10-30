import 'package:buildpro_frontend/data/repositories/mock_auth_repository.dart';
import 'package:buildpro_frontend/data/repositories/mock_user_repository.dart';
import 'package:buildpro_frontend/data/services/business_rule_exception.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

void main() {
  setUp(resetServices);

  group('MockAuthRepository', () {
    late MockUserRepository users;
    late MockAuthRepository auth;

    setUp(() {
      users = MockUserRepository();
      auth = MockAuthRepository(users: users);
    });

    test('rejects a wrong password', () {
      expect(
        auth.signIn('ramon@example.ph', 'nope'),
        throwsA(isA<BusinessRuleException>()),
      );
    });

    test('email is case-insensitive', () async {
      final result = await auth.signIn('RAMON@example.ph', 'password123');
      expect(result.user.fullName, 'Ramon Dela Cruz');
    });

    test('a deactivated user cannot sign in', () async {
      await users.setActive(3, false);
      expect(
        auth.signIn('ramon@example.ph', 'password123'),
        throwsA(
          isA<BusinessRuleException>().having(
            (e) => e.message,
            'message',
            contains('deactivated'),
          ),
        ),
      );
    });

    test(
      'changing the password checks the current one and the policy',
      () async {
        expect(
          auth.changePassword(3, currentPassword: 'x', newPassword: 'abcd1234'),
          throwsA(isA<BusinessRuleException>()),
        );
        expect(
          auth.changePassword(
            3,
            currentPassword: 'password123',
            newPassword: 'short',
          ),
          throwsA(isA<BusinessRuleException>()),
        );
        await auth.changePassword(
          3,
          currentPassword: 'password123',
          newPassword: 'newpass123',
        );
        final result = await auth.signIn('ramon@example.ph', 'newpass123');
        expect(result.user.id, 3);
      },
    );
  });

  testWidgets('wrong password shows an error on the login screen', (
    tester,
  ) async {
    await pumpApp(tester);
    await signInAs(tester, 'ramon@example.ph', password: 'wrong');
    expect(find.text('Incorrect email or password.'), findsOneWidget);
  });

  testWidgets('multi-role user chooses a role, then can sign out', (
    tester,
  ) async {
    await pumpApp(tester);
    await signInAs(tester, 'elena@example.ph');
    expect(find.text('Continue as'), findsOneWidget);
    await tester.tap(
      find.widgetWithText(OutlinedButton, 'Site engineer / foreman'),
    );
    await tester.pumpAndSettle();
    expect(find.text('My sites'), findsWidgets);

    await tester.tap(find.byTooltip('Account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilledButton, 'Sign in'), findsOneWidget);
  });

  testWidgets('forgot password confirms without revealing accounts', (
    tester,
  ) async {
    await pumpApp(tester);
    await tester.tap(find.text('Forgot password?'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Email'),
      'nobody@example.ph',
    );
    await tester.tap(find.text('Send reset link'));
    await tester.pumpAndSettle();
    expect(find.textContaining('If nobody@example.ph belongs'), findsOneWidget);
  });

  testWidgets('profile edits update the signed-in user', (tester) async {
    await pumpApp(tester);
    await signInAs(tester, 'ramon@example.ph');
    await goTo(tester, '/profile');
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Full name'),
      'Jose P. Reyes',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(find.text('Profile saved.'), findsOneWidget);
  });
}

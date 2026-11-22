import 'package:buildpro_frontend/data/repositories/mock_auth_repository.dart';
import 'package:buildpro_frontend/data/repositories/mock_data.dart';
import 'package:buildpro_frontend/data/repositories/mock_user_repository.dart';
import 'package:buildpro_frontend/data/services/business_rule_exception.dart';
import 'package:buildpro_frontend/data/services/session_service.dart';
import 'package:buildpro_frontend/features/auth/viewmodels/login_viewmodel.dart';
import 'package:buildpro_frontend/features/auth/widgets/login_dialog.dart';
import 'package:buildpro_frontend/features/landing/views/landing_page.dart';
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

  testWidgets('wrong password shows an error in the login modal', (
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
      find.widgetWithText(OutlinedButton, 'Foreman'),
    );
    await tester.pumpAndSettle();
    expect(find.text('My sites'), findsWidgets);

    await tester.tap(find.byTooltip('Log out'));
    await tester.pumpAndSettle();
    expect(find.byType(LandingPage), findsOneWidget);
    expect(find.byType(LoginDialog), findsNothing);
  });

  testWidgets('forgot password confirms without revealing accounts', (
    tester,
  ) async {
    await pumpApp(tester);
    await openLoginDialog(tester);
    await tester.tap(find.text('Forgot password?'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Email'),
      'nobody@example.ph',
    );
    await tester.tap(find.text('Send reset code'));
    await tester.pumpAndSettle();
    expect(find.textContaining('If nobody@example.ph belongs'), findsOneWidget);
  });

  testWidgets('forgot password resets password with 6-digit code', (
    tester,
  ) async {
    await pumpApp(tester);
    await openLoginDialog(tester);
    await tester.tap(find.text('Forgot password?'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Email'),
      'ramon@example.ph',
    );
    await tester.tap(find.text('Send reset code'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, '6-digit reset code'),
      MockAuthRepository.mockResetCode,
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'New password'),
      'NewPass123',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Confirm new password'),
      'NewPass123',
    );
    await tester.tap(find.text('Reset password'));
    await tester.pumpAndSettle();

    expect(
      find.text('Password updated. Sign in with your new password.'),
      findsOneWidget,
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Password'),
      'NewPass123',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();
    expect(find.byType(LoginDialog), findsNothing);
  });

  group('login demo helpers', () {
    LoginViewModel login({required bool usesApi, bool show = true}) =>
        LoginViewModel(
          auth: MockAuthRepository(users: MockUserRepository()),
          users: MockUserRepository(),
          session: SessionService(),
          usesApi: usesApi,
          showDemoLogins: show,
        );

    test('demo logins off lists no accounts in either mode', () async {
      for (final api in [true, false]) {
        final vm = login(usesApi: api, show: false);
        await vm.loadDemoAccounts();
        expect(vm.demoAccounts, isEmpty);
      }
    });

    test('API mode lists the accounts the backend seeds', () async {
      final vm = login(usesApi: true);
      await vm.loadDemoAccounts();
      expect(
        vm.demoAccounts.map((a) => a.user.email),
        containsAll([
          'maria@example.ph',
          'ramon@example.ph',
          'mark@example.ph',
        ]),
      );
    });

    test('mock mode lists the mock accounts', () async {
      final vm = login(usesApi: false);
      await vm.loadDemoAccounts();
      expect(vm.demoAccounts, isNotEmpty);
    });

    testWidgets('demo logins off hide the dropdown and the password', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: LoginDialog(usesApi: true, showDemoLogins: false),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Demo account'), findsNothing);
      expect(find.textContaining(MockData.demoPassword), findsNothing);
    });

    for (final api in [true, false]) {
      testWidgets('choosing a demo account fills the form (api: $api)', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1200, 1400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: LoginDialog(usesApi: api, showDemoLogins: true),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Choose an account to sign in as'));
        await tester.pumpAndSettle();
        await tester.tap(find.textContaining('Ramon Dela Cruz').last);
        await tester.pumpAndSettle();
        String? text(String label) => tester
            .widget<TextFormField>(find.widgetWithText(TextFormField, label))
            .controller
            ?.text;
        expect(text('Email'), 'ramon@example.ph');
        expect(text('Password'), MockData.demoPassword);
      });
    }
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

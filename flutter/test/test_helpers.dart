import 'package:buildpro_frontend/app.dart';
import 'package:buildpro_frontend/core/di/service_locator.dart';
import 'package:buildpro_frontend/data/repositories/mock_data.dart';
import 'package:buildpro_frontend/shared/widgets/app_status_chip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// Fresh mock data for every test.
Future<void> resetServices() async {
  await getIt.reset();
  setupServiceLocator();
}

/// Pumps the app at [size] (desktop by default) on the login screen.
Future<void> pumpApp(
  WidgetTester tester, {
  Size size = const Size(1400, 1000),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const App());
  await tester.pumpAndSettle();
}

/// Signs in through the login form. For multi-role users, picks [role].
Future<void> signInAs(
  WidgetTester tester,
  String email, {
  String password = MockData.demoPassword,
  String? role,
}) async {
  await tester.enterText(find.widgetWithText(TextFormField, 'Email'), email);
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Password'),
    password,
  );
  await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
  await tester.pumpAndSettle();
  if (role != null) {
    await tester.tap(find.widgetWithText(OutlinedButton, role));
    await tester.pumpAndSettle();
  }
}

/// Navigates by route, e.g. where the test font overflows the phone drawer.
Future<void> goTo(WidgetTester tester, String location) async {
  GoRouter.of(tester.element(find.byType(Scaffold).first)).go(location);
  await tester.pumpAndSettle();
}

/// A status label inside a status chip (the step indicator repeats some
/// status words).
Finder statusChip(String label) =>
    find.descendant(of: find.byType(AppStatusChip), matching: find.text(label));

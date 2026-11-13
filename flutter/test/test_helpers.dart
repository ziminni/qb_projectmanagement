import 'package:buildpro_frontend/app.dart';
import 'package:buildpro_frontend/core/di/service_locator.dart';
import 'package:buildpro_frontend/data/repositories/mock_data.dart';
import 'package:buildpro_frontend/features/auth/widgets/login_dialog.dart';
import 'package:buildpro_frontend/features/landing/views/landing_page.dart';
import 'package:buildpro_frontend/shared/widgets/app_location_map.dart';
import 'package:buildpro_frontend/shared/widgets/app_status_chip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// Fresh mock data for every test.
Future<void> resetServices() async {
  await getIt.reset();
  setupServiceLocator();
  // No network in tests: draw maps without tiles.
  AppLocationMap.showTiles = false;
}

/// Pumps the app at [size] (desktop by default) on the landing page.
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

/// Opens the sign-in modal from the landing page, if it is not open yet.
Future<void> openLoginDialog(WidgetTester tester) async {
  if (find.byType(LoginDialog).evaluate().isNotEmpty) return;
  await tester.tap(
    find.descendant(of: find.byType(NavBar), matching: find.text('Login')),
  );
  await tester.pumpAndSettle();
}

/// Signs in through the login modal. For multi-role users, picks [role].
Future<void> signInAs(
  WidgetTester tester,
  String email, {
  String password = MockData.demoPassword,
  String? role,
}) async {
  await openLoginDialog(tester);
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

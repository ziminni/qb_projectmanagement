import 'dart:io';

import 'package:buildpro_frontend/app.dart';
import 'package:buildpro_frontend/core/di/service_locator.dart';
import 'package:buildpro_frontend/data/repositories/mock_data.dart';
import 'package:buildpro_frontend/shared/widgets/app_location_map.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';

/// The site engineer's day on a phone: sites, daily reports, a material
/// request with the site count, and deliveries. Run on a device with
/// `flutter drive --driver=test_driver/integration_test.dart
/// --target=integration_test/site_engineer_test.dart -d DEVICE`.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> shot(WidgetTester tester, String name) async {
    await tester.pumpAndSettle();
    await binding.takeScreenshot(name);
  }

  Future<void> goTo(WidgetTester tester, String location) async {
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go(location);
    await tester.pumpAndSettle();
  }

  testWidgets('site engineer works from a phone', (tester) async {
    setupServiceLocator();
    AppLocationMap.showTiles = false;
    await tester.pumpWidget(const App());
    await tester.pumpAndSettle();
    // Android draws to a surface screenshots cannot read until converted.
    if (Platform.isAndroid) await binding.convertFlutterSurfaceToImage();
    await shot(tester, '01-login');

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Email'),
      'ana@example.ph',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Password'),
      MockData.demoPassword,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();
    await shot(tester, '02-my-sites');

    await tester.tap(find.byTooltip('Open navigation menu'));
    await shot(tester, '03-menu');
    await tester.tap(find.text('Daily reports').last);
    await shot(tester, '04-daily-reports');

    await goTo(tester, '/material-requests/new?projectId=1');
    await tester.tap(
      find.widgetWithText(
        DropdownButtonFormField<int>,
        'Category (budget it draws from)',
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Roofing').last);
    await tester.pumpAndSettle();
    final counts = find.widgetWithText(TextFormField, 'Counted');
    for (var i = 0; i < counts.evaluate().length; i++) {
      await tester.ensureVisible(counts.at(i));
      await tester.enterText(counts.at(i), '5');
    }
    await shot(tester, '05-site-count');
    await tester.ensureVisible(find.widgetWithText(TextFormField, 'Item'));
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Item'),
      'Roofing nails',
    );
    await tester.enterText(find.widgetWithText(TextFormField, 'Qty'), '3');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await shot(tester, '06-request-items');
    await tester.tap(find.text('Send to owner'));
    await tester.pumpAndSettle();
    expect(find.text('Waiting for owner'), findsWidgets);
    await shot(tester, '07-request-sent');

    await goTo(tester, '/deliveries');
    await shot(tester, '08-deliveries');
    await tester.tap(find.text('Confirm').first);
    await shot(tester, '09-confirm-delivery');
  });
}

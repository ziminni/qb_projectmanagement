import 'package:buildpro_frontend/core/di/service_locator.dart';
import 'package:buildpro_frontend/data/repositories/notification_repository.dart';
import 'package:buildpro_frontend/data/repositories/schedule_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

void main() {
  setUp(resetServices);

  test('marking a to-do done notifies the project PM', () async {
    final before = await getIt<NotificationRepository>().getFor(3);
    await getIt<ScheduleRepository>().setDone(9, done: true, userId: 4);
    final after = await getIt<NotificationRepository>().getFor(3);
    expect(after.length, before.length + 1);
    expect(after.first.message, contains('Second-floor column pouring'));
    expect(after.first.link, '/todo-verification');
  });

  testWidgets('owner dashboard and bid approval in the inbox', (tester) async {
    await pumpApp(tester);
    await signInAs(tester, 'ramon@example.ph');
    expect(find.text('Company overview'), findsOneWidget);
    // Projects 1 and 2 are Ongoing.
    expect(
      find.descendant(
        of: find.ancestor(
          of: find.text('Active projects'),
          matching: find.byType(Card),
        ),
        matching: find.text('2'),
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Approvals').first);
    await tester.pumpAndSettle();
    expect(find.text('Bids (1)'), findsWidgets);
    await tester.tap(find.text('Townhouse row, Malvar'));
    await tester.pumpAndSettle();
    expect(find.text('Change status'), findsOneWidget);
  });

  testWidgets('PM inbox lists to-dos awaiting verification', (tester) async {
    await pumpApp(tester);
    await signInAs(tester, 'jose@example.ph');
    expect(find.text('To-do verification'), findsOneWidget);
    await goTo(tester, '/approvals');
    expect(find.text('To-do verification (2)'), findsWidgets);
    expect(find.text('Second-floor column rebar'), findsOneWidget);
  });

  testWidgets('notifications show unread count and mark as read', (
    tester,
  ) async {
    await pumpApp(tester);
    await signInAs(tester, 'jose@example.ph');
    expect(find.byTooltip('1 unread notifications'), findsOneWidget);
    await tester.tap(find.byTooltip('1 unread notifications'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mark all as read'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Notifications'), findsOneWidget);
  });
}

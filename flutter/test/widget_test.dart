import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

void main() {
  setUp(resetServices);

  testWidgets('PM opens the schedule and sees document sample progress', (
    tester,
  ) async {
    await pumpApp(tester);
    await signInAs(tester, 'jose@example.ph');
    expect(find.text('Dashboard'), findsWidgets);

    await tester.tap(find.text('My projects').first);
    await tester.pumpAndSettle();
    expect(find.text('Two-storey residence, Villanueva'), findsOneWidget);
    expect(find.text('37%'), findsOneWidget);

    await tester.tap(find.text('Two-storey residence, Villanueva'));
    await tester.pumpAndSettle();
    expect(find.text('37% complete'), findsOneWidget);
    expect(find.text('S-curve'), findsOneWidget);

    await tester.tap(find.text('Categories and to-dos'));
    await tester.pumpAndSettle();
    expect(find.text('Foundation'), findsOneWidget);
    expect(find.text('Earned value'), findsOneWidget);
    expect(find.text('₱740,000.00'), findsOneWidget);

    await tester.tap(find.text('Gantt'));
    await tester.pumpAndSettle();
    expect(find.text('Category % complete'), findsOneWidget);
  });

  testWidgets('client cannot open the internal project detail', (tester) async {
    await pumpApp(tester);
    await signInAs(tester, 'mark@example.ph');
    await goTo(tester, '/projects/1/schedule');
    expect(find.text('Add category'), findsNothing);
    expect(find.text('Categories and to-dos'), findsNothing);
  });

  testWidgets('site engineer checks off a to-do on a phone', (tester) async {
    await pumpApp(tester, size: const Size(390, 844));
    // Ana Bautista is the site engineer on project 1.
    await signInAs(tester, 'ana@example.ph');

    // The drawer's labels overflow with the wide test font, so navigate
    // by route; the AppBar title confirms the shell resolved the entry.
    expect(find.byTooltip('Open navigation menu'), findsOneWidget);
    await goTo(tester, '/schedule');
    expect(find.text('To-do checklist'), findsOneWidget);
    await tester.tap(find.text('Two-storey residence, Villanueva'));
    await tester.pumpAndSettle();

    final pouring = find.text('Second-floor column pouring');
    await tester.dragUntilVisible(
      pouring,
      find.byType(ListView).first,
      const Offset(0, -200),
    );
    await tester.ensureVisible(pouring);
    await tester.pumpAndSettle();
    final tile = find.ancestor(of: pouring, matching: find.byType(Row)).first;
    final checkbox = find.descendant(of: tile, matching: find.byType(Checkbox));
    expect(tester.widget<Checkbox>(checkbox).value, isFalse);
    await tester.tap(checkbox);
    await tester.pumpAndSettle();
    expect(tester.widget<Checkbox>(checkbox).value, isTrue);
    expect(
      find.descendant(of: tile, matching: find.text('Awaiting verification')),
      findsOneWidget,
    );
    // Not verified yet, so overall progress is unchanged.
    await tester.dragUntilVisible(
      find.text('37%'),
      find.byType(ListView).first,
      const Offset(0, 400),
    );
    expect(find.text('37%'), findsOneWidget);

    // The scrollable tab bar puts Gantt off screen on a phone.
    await goTo(tester, '/projects/1/gantt');
    expect(find.text('Category % complete'), findsOneWidget);
  });
}

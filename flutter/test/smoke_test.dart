import 'package:buildpro_frontend/core/layout/project_tabs.dart';
import 'package:buildpro_frontend/core/layout/role_navigation.dart';
import 'package:buildpro_frontend/data/models/app_role.dart';
import 'package:buildpro_frontend/routes/routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

/// Opens every navigation destination for every role on a phone and on a
/// desktop, failing on layout overflows or build errors.
void main() {
  setUp(resetServices);

  const accounts = {
    AppRole.admin: 'maria@example.ph',
    AppRole.owner: 'ramon@example.ph',
    AppRole.siteEngineer: 'ana@example.ph',
    AppRole.accountant: 'liza@example.ph',
    AppRole.client: 'mark@example.ph',
  };

  for (final size in const [Size(412, 915), Size(1400, 1000)]) {
    for (final entry in accounts.entries) {
      testWidgets('${entry.key.name} screens at ${size.width.toInt()}px', (
        tester,
      ) async {
        await pumpApp(tester, size: size);
        await signInAs(tester, entry.value);
        for (final d in RoleNavigation.forRole(entry.key)) {
          await goTo(tester, d.path);
          expect(tester.takeException(), isNull, reason: d.path);
        }
        if (entry.key != AppRole.client && entry.key != AppRole.admin) {
          for (final tab in [
            'overview',
            'schedule',
            'gantt',
            'daily-reports',
            'materials',
            'labor',
            'financials',
            'documents',
          ]) {
            await goTo(tester, '/projects/1/$tab');
            expect(tester.takeException(), isNull, reason: tab);
          }
        }
      });
    }
  }

  // Company finances are confidential: roles outside finance must never see
  // a peso amount on any screen they can open.
  const noFinance = {
    AppRole.admin: 'maria@example.ph',
    AppRole.siteEngineer: 'ana@example.ph',
  };
  for (final entry in noFinance.entries) {
    testWidgets('${entry.key.name} sees no peso amounts', (tester) async {
      await pumpApp(tester, size: const Size(1400, 3000));
      await signInAs(tester, entry.value);
      final paths = [
        for (final d in RoleNavigation.forRole(entry.key)) d.path,
        if (entry.key == AppRole.siteEngineer) ...[
          for (final tab in ProjectTab.visibleTo(entry.key))
            '/projects/1/${tab.segment}',
          AppRoutes.materialRequest(4),
          AppRoutes.purchaseOrder(5),
          AppRoutes.variationOrder(1),
          AppRoutes.variationOrders,
          AppRoutes.materialRequestNew,
        ],
      ];
      for (final path in paths) {
        await goTo(tester, path);
        expect(find.textContaining('₱'), findsNothing, reason: path);
      }
    });
  }
}

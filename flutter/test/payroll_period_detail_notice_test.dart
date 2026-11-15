import 'package:buildpro_frontend/core/di/service_locator.dart';
import 'package:buildpro_frontend/data/models/payroll_line.dart';
import 'package:buildpro_frontend/data/repositories/labor_repository.dart';
import 'package:buildpro_frontend/data/repositories/mock_audit_log_repository.dart';
import 'package:buildpro_frontend/data/repositories/mock_labor_repository.dart';
import 'package:buildpro_frontend/features/labor/views/payroll_period_detail_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

/// The mock computes real contributions; the CPMS server sends one statutory
/// total plus a policy flag instead, so the screens must say when that policy
/// is unconfigured (QA ISSUE-002).
class PolicyLaborRepository extends MockLaborRepository {
  PolicyLaborRepository({required this.policy, DateTime Function()? clock})
    : super(
        projects: getIt(),
        users: getIt(),
        auditLog: MockAuditLogRepository(),
        clock: clock ?? DateTime.now,
      );

  final String policy;

  @override
  Future<List<PayrollLine>> getLines(int periodId) async {
    final lines = await super.getLines(periodId);
    return [
      for (final l in lines)
        PayrollLine(
          id: l.id,
          payrollPeriodId: l.payrollPeriodId,
          workerId: l.workerId,
          daysWorked: l.daysWorked,
          overtimePay: l.overtimePay,
          grossPay: l.grossPay,
          sss: l.sss,
          philhealth: l.philhealth,
          pagibig: l.pagibig,
          cashAdvance: l.cashAdvance,
          netPay: l.netPay,
          statutoryDeductions: l.statutoryDeductions,
          deductionsPolicy: policy,
        ),
    ];
  }
}

void main() {
  setUp(resetServices);

  /// Opens payroll period 2 (QB-2026-014, 2026-10-16–31) as the accountant.
  Future<void> openPeriod(
    WidgetTester tester, {
    required String policy,
    required Size size,
  }) async {
    await getIt.unregister<LaborRepository>();
    getIt.registerLazySingleton<LaborRepository>(
      () => PolicyLaborRepository(policy: policy),
    );
    await pumpApp(tester, size: size);
    await signInAs(tester, 'liza@example.ph');
    await goTo(tester, '/payroll/2');
    expect(find.text('Totals'), findsOneWidget);
  }

  /// The page's own list, not the nav drawer's (also a Scrollable).
  Finder pageScrollable() => find
      .descendant(
        of: find.byType(PayrollPeriodDetailPage),
        matching: find.byType(Scrollable),
      )
      .first;

  for (final size in const [Size(1440, 900), Size(1100, 900)]) {
    final label = '${size.width.round()}x${size.height.round()}';

    testWidgets(
      '$label: basic payroll says so and hides the contribution columns',
      (tester) async {
        await openPeriod(
          tester,
          policy: PayrollLine.deductionsUnconfigured,
          size: size,
        );
        // An unnoticed warning is nearly useless: it must be on screen under
        // Totals, not below the pay table.
        expect(find.textContaining('Basic payroll'), findsOneWidget);
        expect(find.text('SSS'), findsNothing);
        expect(find.text('PhilHealth'), findsNothing);
        expect(find.text('Pag-IBIG'), findsNothing);
        await tester.scrollUntilVisible(
          find.textContaining('Basic payroll'),
          300,
          scrollable: pageScrollable(),
          maxScrolls: 40,
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('Basic payroll'), findsOneWidget);
      },
    );

    testWidgets('$label: configured deductions keep the rates footer', (
      tester,
    ) async {
      await openPeriod(
        tester,
        policy: PayrollLine.deductionsConfigured,
        size: size,
      );
      await tester.scrollUntilVisible(
        find.textContaining('simplified employee-share rates'),
        300,
        scrollable: pageScrollable(),
        maxScrolls: 40,
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('simplified employee-share rates'),
        findsOneWidget,
      );
      expect(find.text('SSS'), findsOneWidget);
      expect(find.textContaining('Basic payroll'), findsNothing);
    });
  }

  testWidgets('the header row offers Export PDF', (tester) async {
    await openPeriod(
      tester,
      policy: PayrollLine.deductionsUnconfigured,
      size: const Size(1100, 900),
    );
    expect(find.text('Export PDF'), findsOneWidget);
  });
}

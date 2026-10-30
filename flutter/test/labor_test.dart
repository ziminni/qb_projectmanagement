import 'package:buildpro_frontend/core/di/service_locator.dart';
import 'package:buildpro_frontend/data/models/attendance.dart';
import 'package:buildpro_frontend/data/models/payroll_period.dart';
import 'package:buildpro_frontend/data/models/worker.dart';
import 'package:buildpro_frontend/data/repositories/labor_repository.dart';
import 'package:buildpro_frontend/data/repositories/mock_audit_log_repository.dart';
import 'package:buildpro_frontend/data/repositories/mock_labor_repository.dart';
import 'package:buildpro_frontend/data/services/business_rule_exception.dart';
import 'package:buildpro_frontend/data/services/payroll_calculator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

void main() {
  setUp(resetServices);

  late MockLaborRepository repo;
  setUp(() {
    repo = MockLaborRepository(
      projects: getIt(),
      users: getIt(),
      auditLog: MockAuditLogRepository(),
      clock: () => DateTime(2026, 10, 26, 9),
    );
  });

  Matcher throwsRule(String fragment) => throwsA(
    isA<BusinessRuleException>().having(
      (e) => e.message,
      'message',
      contains(fragment),
    ),
  );

  test('pay = rate × days + 25% overtime, less contributions', () {
    const worker = Worker(id: 1, fullName: 'X', trade: 'Mason', dailyRate: 750);
    Attendance a(int day, AttendanceStatus s, [double ot = 0]) => Attendance(
      id: day,
      projectId: 1,
      workerId: 1,
      workDate: DateTime(2026, 10, day),
      status: s,
      overtimeHours: ot,
      recordedBy: 4,
    );
    final line = computePayrollLine(
      payrollPeriodId: 1,
      worker: worker,
      attendance: [
        for (var d = 1; d <= 5; d++) a(d, AttendanceStatus.present),
        a(6, AttendanceStatus.halfDay, 4),
        a(7, AttendanceStatus.absent),
      ],
      cashAdvance: 500,
    );
    expect(line.daysWorked, 5.5);
    expect(line.overtimePay, 468.75);
    expect(line.grossPay, 4593.75);
    expect(line.sss, 229.69);
    expect(line.philhealth, 114.84);
    expect(line.pagibig, 91.88);
    expect(
      line.netPay,
      closeTo(4593.75 - 229.69 - 114.84 - 91.88 - 500, 0.001),
    );
  });

  group('attendance', () {
    AttendanceEntry present(int w) =>
        (workerId: w, status: AttendanceStatus.present, overtimeHours: 0.0);

    test('locked once its payroll period is processed', () {
      expect(
        repo.saveAttendance(1, DateTime(2026, 10, 5), [present(1)], userId: 4),
        throwsRule('locked'),
      );
    });

    test('no future dates, and only the assigned site engineer', () {
      expect(
        repo.saveAttendance(1, DateTime(2026, 10, 27), [present(1)], userId: 4),
        throwsRule('future'),
      );
      expect(
        repo.saveAttendance(1, DateTime(2026, 10, 26), [present(1)], userId: 8),
        throwsRule('site engineer'),
      );
    });

    test('a worker cannot be present on two sites the same day', () {
      // Worker 8 is on project 2 on Oct 20.
      expect(
        repo.saveAttendance(1, DateTime(2026, 10, 20), [present(8)], userId: 4),
        throwsRule('another project'),
      );
    });
  });

  group('payroll', () {
    test('periods are at most 16 days and cannot overlap', () {
      expect(
        repo.createPeriod(
          1,
          DateTime(2026, 11, 1),
          DateTime(2026, 11, 30),
          userId: 6,
        ),
        throwsRule('16'),
      );
      expect(
        repo.createPeriod(
          1,
          DateTime(2026, 10, 30),
          DateTime(2026, 11, 5),
          userId: 6,
        ),
        throwsRule('overlaps'),
      );
    });

    test('verify after cut-off by the owner, then process', () async {
      // Period 2 ends Oct 31; the clock is Oct 26.
      expect(repo.verifyPeriod(2, userId: 3), throwsRule('cut-off'));
      expect(repo.processPeriod(3, userId: 6), throwsRule('verify'));
      await repo.verifyPeriod(3, userId: 3);

      final lines = await repo.getLines(3);
      final ramil = lines.firstWhere((l) => l.workerId == 8);
      expect(
        repo.setCashAdvance(3, 8, ramil.grossPay + 1, userId: 6),
        throwsRule('exceed'),
      );
      await repo.setCashAdvance(3, 8, 1000, userId: 6);

      final before = await repo.laborCost(2);
      final processed = await repo.processPeriod(3, userId: 6);
      expect(processed.status, PayrollStatus.processed);
      final stored = await repo.getLines(3);
      expect(stored.firstWhere((l) => l.workerId == 8).cashAdvance, 1000);
      expect(
        await repo.laborCost(2),
        before + stored.fold<double>(0, (s, l) => s + l.grossPay),
      );
    });
  });

  testWidgets('site engineer records attendance', (tester) async {
    await pumpApp(tester);
    await signInAs(tester, 'ana@example.ph');
    await goTo(tester, '/attendance?projectId=1');
    await tester.tap(find.text('Mark all present'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Save attendance'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Save attendance'));
    await tester.pumpAndSettle();
    expect(find.text('Attendance saved.'), findsOneWidget);
  });

  testWidgets('PM verifies attendance from the inbox; accountant processes', (
    tester,
  ) async {
    await pumpApp(tester);
    await signInAs(tester, 'ramon@example.ph');
    await goTo(tester, '/approvals');
    expect(find.text('Attendance verification (1)'), findsWidgets);
    await tester.tap(find.text('Attendance · QB-2026-018'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Verify attendance'));
    await tester.pumpAndSettle();
    expect(find.text('Attendance verified.'), findsOneWidget);

    await tester.tap(find.byTooltip('Account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    await signInAs(tester, 'liza@example.ph');
    await goTo(tester, '/payroll/3');
    await tester.tap(find.text('Process payroll'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Process'));
    await tester.pumpAndSettle();
    expect(find.text('Payroll processed.'), findsOneWidget);
    expect(statusChip('Processed'), findsOneWidget);
  });
}

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

  test('pay = rate × days, less cash advances (no OT or statutory deductions)', () {
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
    expect(line.overtimePay, 0);
    expect(line.grossPay, 4125.0);
    expect(line.sss, 0);
    expect(line.philhealth, 0);
    expect(line.pagibig, 0);
    expect(line.netPay, closeTo(4125.0 - 500, 0.001));
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
    // How many periods have passed cut-off depends on today's date.
    expect(find.textContaining('Attendance verification ('), findsWidgets);
    await tester.ensureVisible(find.text('Attendance · QB-2026-018'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Attendance · QB-2026-018'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Verify attendance'));
    await tester.pumpAndSettle();
    expect(find.text('Attendance verified.'), findsOneWidget);

    await tester.tap(find.byTooltip('Log out'));
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

  testWidgets('attendance shows hours input on Present and hides Half day', (
    tester,
  ) async {
    await pumpApp(tester);
    await signInAs(tester, 'ana@example.ph');
    await goTo(tester, '/attendance?projectId=1');

    expect(find.text('Half day'), findsNothing);
    expect(find.text('Present'), findsWidgets);
    expect(find.text('Absent'), findsWidgets);

    await tester.tap(find.text('Present').first);
    await tester.pumpAndSettle();
    expect(find.text('Hours'), findsWidgets);
  });

  testWidgets('workers and payroll pages show KPI dashboards and filters', (
    tester,
  ) async {
    await pumpApp(tester);
    await signInAs(tester, 'liza@example.ph');

    await goTo(tester, '/workers');
    expect(find.text('Total workers'), findsOneWidget);
    expect(find.text('Active crew'), findsOneWidget);
    expect(find.text('Avg. daily rate'), findsOneWidget);

    await goTo(tester, '/payroll');
    expect(find.text('Payroll periods'), findsOneWidget);
    expect(find.text('Open cut-offs'), findsOneWidget);
    expect(find.text('Ready to process'), findsOneWidget);
    expect(find.text('Processed net pay'), findsOneWidget);
  });

  testWidgets('foreman requests a laborer on a project and PM approves it', (
    tester,
  ) async {
    await pumpApp(tester);
    await signInAs(tester, 'ana@example.ph');
    await goTo(tester, '/projects/1/laborers');

    await tester.tap(find.text('Add laborer'));
    await tester.pumpAndSettle();
    // Switch to "New laborer" tab when existing workers are listed.
    if (find.text('New laborer').evaluate().isNotEmpty) {
      await tester.tap(find.text('New laborer'));
      await tester.pumpAndSettle();
    }
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Full name'),
      'Juanito Cruz',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Address'),
      'Brgy. Carmen, CDO',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Phone number'),
      '09171234567',
    );
    await tester.tap(find.text('Send request'));
    await tester.pumpAndSettle();

    expect(find.textContaining('sent to the project manager'), findsOneWidget);
    expect(find.text('Juanito Cruz'), findsOneWidget);
    expect(find.text('Pending PM approval'), findsOneWidget);

    await tester.tap(find.byTooltip('Log out'));
    await tester.pumpAndSettle();
    await signInAs(tester, 'ramon@example.ph');
    await goTo(tester, '/approvals');
    expect(find.textContaining('Laborer requests (1)'), findsWidgets);

    // Clicking the laborer request on /approvals opens the review modal in
    // place instead of redirecting away to the project page.
    await tester.ensureVisible(find.text('Juanito Cruz · QB-2026-014'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Juanito Cruz · QB-2026-014'));
    await tester.pumpAndSettle();
    expect(find.text('Laborer & site assignment details'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Approve'));
    await tester.pumpAndSettle();

    expect(find.textContaining('approved and added'), findsOneWidget);
    // Still on the Approvals page, with the laborer queue now cleared!
    expect(find.text('Approvals'), findsWidgets);
    expect(find.text('Laborer requests (0)'), findsOneWidget);

    await goTo(tester, '/projects/1/laborers');
    expect(find.text('Juanito Cruz'), findsOneWidget);
    expect(find.text('No pending laborer requests.'), findsOneWidget);
  });

  test('worker cash advance balance auto-deducts on payroll and carries over remainder', () async {
    // Worker 8 is in period 3 (project 2). Give them a balance larger than
    // one period's pay so the full period gross is deducted and the remainder
    // stays on their balance for the next payday.
    final initialLines = await repo.getLines(3);
    final gross = initialLines.firstWhere((l) => l.workerId == 8).grossPay;
    await repo.addWorkerCashAdvance(8, gross + 750);

    // Preview automatically applies min(balance, gross).
    final preview = await repo.getLines(3);
    final line = preview.firstWhere((l) => l.workerId == 8);
    expect(line.cashAdvance, gross);
    expect(line.netPay, 0);

    // Verify & process period 3 -> balance decreases by deducted amount.
    await repo.verifyPeriod(3, userId: 3);
    await repo.processPeriod(3, userId: 6);
    final afterWorker = (await repo.getWorkers()).firstWhere((w) => w.id == 8);
    expect(afterWorker.cashAdvanceBalance, closeTo(750, 0.001));
  });

  testWidgets('adding a worker saves the inputted daily rate as payroll basis', (
    tester,
  ) async {
    await pumpApp(tester);
    await signInAs(tester, 'liza@example.ph');
    await goTo(tester, '/workers');

    await tester.tap(find.text('Add worker'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Full name'),
      'Marco Santos',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Address'),
      'Lipa City',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Phone number'),
      '09171112222',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Daily rate'),
      '680',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    final workers = await getIt<LaborRepository>().getWorkers();
    final added = workers.firstWhere((w) => w.fullName == 'Marco Santos');
    expect(added.dailyRate, 680);
  });

  testWidgets(
    'bulk laborer requests group into one approval row with multi-select modal',
    (tester) async {
      await pumpApp(tester, size: const Size(1400, 900));
      final labor = getIt<LaborRepository>();
      // Foreman (userId 3) requests 3 laborers on project 1 in bulk.
      await labor.requestProjectWorker(
        projectId: 1,
        fullName: 'Berto Alonzo',
        address: 'Sariaya',
        phone: '09170000001',
        userId: 3,
      );
      await labor.requestProjectWorker(
        projectId: 1,
        fullName: 'Cardo Dalisay',
        address: 'Sariaya',
        phone: '09170000002',
        userId: 3,
      );
      await labor.requestProjectWorker(
        projectId: 1,
        fullName: 'Dante Gulapa',
        address: 'Sariaya',
        phone: '09170000003',
        userId: 3,
      );

      await signInAs(tester, 'ramon@example.ph');
      await goTo(tester, '/approvals');

      // Grouped into ONE single row instead of 3 separate rows!
      expect(find.text('Laborer requests (1)'), findsWidgets);
      expect(find.text('3 laborers requested · QB-2026-014'), findsOneWidget);
      expect(find.text('Approve all (3)'), findsOneWidget);

      await tester.ensureVisible(
        find.text('3 laborers requested · QB-2026-014'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('3 laborers requested · QB-2026-014'));
      await tester.pumpAndSettle();

      expect(find.text('3 laborers requested'), findsOneWidget);
      expect(find.text('Select all (3/3)'), findsOneWidget);

      // Untick Dante Gulapa, approve the 2 selected, then reject the remaining 1.
      await tester.tap(find.text('Dante Gulapa'));
      await tester.pumpAndSettle();
      expect(find.text('Approve selected (2)'), findsOneWidget);

      await tester.tap(find.text('Approve selected (2)'));
      await tester.pumpAndSettle();

      // Modal stays open with the 1 remaining pending worker pre-selected.
      expect(find.text('Reject selected (1)'), findsOneWidget);
      await tester.tap(find.text('Reject selected (1)'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextFormField),
        ),
        'Crew already full',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Reject'));
      await tester.pumpAndSettle();

      // Modal closes automatically once all 3 are decided, keeping PM on Approvals.
      expect(find.text('Laborer requests (0)'), findsOneWidget);
    },
  );
}

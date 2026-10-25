import 'package:buildpro_frontend/core/di/service_locator.dart';
import 'package:buildpro_frontend/data/models/daily_report.dart';
import 'package:buildpro_frontend/data/repositories/daily_report_repository.dart';
import 'package:buildpro_frontend/data/repositories/mock_audit_log_repository.dart';
import 'package:buildpro_frontend/data/repositories/mock_daily_report_repository.dart';
import 'package:buildpro_frontend/data/repositories/project_repository.dart';
import 'package:buildpro_frontend/data/repositories/schedule_repository.dart';
import 'package:buildpro_frontend/data/services/business_rule_exception.dart';
import 'package:buildpro_frontend/data/services/progress_calculator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

void main() {
  setUp(resetServices);

  late MockDailyReportRepository repo;
  setUp(() {
    repo = MockDailyReportRepository(
      projects: getIt<ProjectRepository>(),
      schedule: getIt<ScheduleRepository>(),
      auditLog: MockAuditLogRepository(),
      clock: () => DateTime(2026, 10, 25, 10),
    );
  });

  Matcher throwsRule(String fragment) => throwsA(
    isA<BusinessRuleException>().having(
      (e) => e.message,
      'message',
      contains(fragment),
    ),
  );

  DailyReportDraft draft({
    int projectId = 1,
    DateTime? date,
    List<int> todoIds = const [],
  }) => DailyReportDraft(
    projectId: projectId,
    reportDate: date ?? DateTime(2026, 10, 25),
    weather: Weather.sunny,
    manpower: const [(trade: 'Mason', headcount: 4)],
    materials: const [(materialId: 1, quantity: 10)],
    todoIds: todoIds,
  );

  test('no future dates and one report per project per date', () {
    expect(
      repo.saveDraft(draft(date: DateTime(2026, 10, 26)), userId: 4),
      throwsRule('future'),
    );
    expect(
      repo.saveDraft(draft(date: DateTime(2026, 10, 20)), userId: 4),
      throwsRule('already a report'),
    );
  });

  test('reports need an Ongoing project and the assigned site engineer', () {
    // Project 3 is Awarded; Elena is its site engineer.
    expect(
      repo.saveDraft(draft(projectId: 3), userId: 8),
      throwsRule('Ongoing'),
    );
    // Elena is not the site engineer on project 1.
    expect(repo.saveDraft(draft(), userId: 8), throwsRule('assigned'));
  });

  test(
    'submit marks to-dos done; approval verifies them and moves progress',
    () async {
      final schedule = getIt<ScheduleRepository>();
      final project = (await getIt<ProjectRepository>().getProject(1))!;
      Future<double> progress() async => computeProjectProgress(
        project: project,
        categories: await schedule.getCategories(1),
        todos: await schedule.getTodos(1),
      ).progress;

      expect(await progress(), closeTo(0.37, 1e-9));
      final saved = await repo.saveDraft(draft(todoIds: [9]), userId: 4);
      await repo.submit(saved.id, userId: 4);
      final todo9 = (await schedule.getTodos(1)).firstWhere((t) => t.id == 9);
      expect(todo9.isDone, isTrue);
      expect(todo9.dailyReportId, saved.id);
      // Done but unverified: progress unchanged.
      expect(await progress(), closeTo(0.37, 1e-9));

      expect(repo.approve(saved.id, userId: 4), throwsRule('PM'));
      await repo.approve(saved.id, userId: 3);
      // Pillars 4 of 5 → 80% × 20% weight: +4 points.
      expect(await progress(), closeTo(0.41, 1e-9));

      // Approved reports are locked.
      expect(
        repo.saveDraft(
          DailyReportDraft(
            id: saved.id,
            projectId: 1,
            reportDate: DateTime(2026, 10, 25),
            weather: Weather.cloudy,
          ),
          userId: 4,
        ),
        throwsRule('can no longer be edited'),
      );
    },
  );

  test(
    'returning needs remarks; only submitted reports are reviewed',
    () async {
      expect(
        repo.returnReport(6, userId: 3, remarks: ' '),
        throwsRule('remarks'),
      );
      final returned = await repo.returnReport(
        6,
        userId: 3,
        remarks: 'Add photos',
      );
      expect(returned.status, DailyReportStatus.returned);
      expect(repo.approve(6, userId: 3), throwsRule('Only submitted'));
    },
  );

  test('inventory deductions count approved reports only', () async {
    final usage = await repo.getApprovedMaterialUsage(1);
    // Report 6 (submitted) used plywood; it must not count yet.
    expect(usage.any((u) => u.materialId == 7), isFalse);
    expect(
      usage
          .where((u) => u.materialId == 1)
          .fold<double>(0, (s, u) => s + u.quantity),
      50,
    );
  });

  testWidgets('site engineer files and submits a report', (tester) async {
    await pumpApp(tester);
    await signInAs(tester, 'ana@example.ph');
    await goTo(tester, '/daily-reports/new?projectId=1');

    // New reports start with one empty manpower row.
    await tester.tap(
      find.widgetWithText(DropdownButtonFormField<String>, 'Trade'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mason').last);
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(CheckboxListTile, 'Second-floor column pouring'),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Submit to PM'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Submit to PM'));
    await tester.pumpAndSettle();
    expect(find.text('Report submitted to the PM.'), findsOneWidget);
    expect(statusChip('Submitted'), findsOneWidget);
    expect(find.text('Mason'), findsOneWidget);
  });

  testWidgets('PM approves a submitted report and returns another', (
    tester,
  ) async {
    await pumpApp(tester);
    await signInAs(tester, 'jose@example.ph');
    await goTo(tester, '/approvals');
    expect(find.text('Daily reports (1)'), findsWidgets);
    await tester.tap(find.text('Daily report · QB-2026-014'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Return with remarks'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Return'));
    await tester.pumpAndSettle();
    expect(
      find.text('Add remarks so the site engineer knows what to fix.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Approve'));
    await tester.pumpAndSettle();
    expect(statusChip('Approved'), findsOneWidget);
  });

  testWidgets('project tab filters reports by status', (tester) async {
    await pumpApp(tester);
    await signInAs(tester, 'ramon@example.ph');
    await goTo(tester, '/projects/1/daily-reports');
    expect(find.text('Oct 24, 2026'), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Returned'));
    await tester.pumpAndSettle();
    expect(find.text('Oct 19, 2026'), findsOneWidget);
    expect(find.text('Oct 24, 2026'), findsNothing);
  });
}

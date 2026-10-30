import 'package:buildpro_frontend/data/models/app_role.dart';
import 'package:buildpro_frontend/data/models/project.dart';
import 'package:buildpro_frontend/data/repositories/mock_audit_log_repository.dart';
import 'package:buildpro_frontend/data/repositories/mock_data.dart';
import 'package:buildpro_frontend/data/repositories/mock_project_repository.dart';
import 'package:buildpro_frontend/data/repositories/mock_user_repository.dart';
import 'package:buildpro_frontend/data/services/business_rule_exception.dart';
import 'package:buildpro_frontend/data/services/progress_calculator.dart';
import 'package:buildpro_frontend/data/services/project_rules.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

void main() {
  setUp(resetServices);

  late MockProjectRepository repo;
  late MockAuditLogRepository audit;
  setUp(() {
    audit = MockAuditLogRepository();
    repo = MockProjectRepository(users: MockUserRepository(), auditLog: audit);
  });

  final throwsRule = throwsA(isA<BusinessRuleException>());

  Project draft({double amount = 1000000, DateTime? end}) => Project(
    id: 0,
    code: 'qb-2026-099',
    name: 'Test',
    location: 'Lipa',
    clientId: 1,
    contractAmount: amount,
    downPaymentPct: 15,
    retentionPct: 10,
    startDate: DateTime(2027, 1, 1),
    targetEndDate: end ?? DateTime(2027, 6, 1),
    status: ProjectStatus.ongoing,
  );

  test('contract amount must be > 0 and end after start', () {
    expect(repo.saveProject(draft(amount: 0)), throwsRule);
    expect(repo.saveProject(draft(end: DateTime(2027, 1, 1))), throwsRule);
  });

  test('new projects start as Draft with an upper-case unique code', () async {
    final p = await repo.saveProject(draft());
    expect(p.status, ProjectStatus.draft);
    expect(p.code, 'QB-2026-099');
    expect(repo.saveProject(draft()), throwsRule);
  });

  test('status moves forward only; On hold returns to Ongoing', () {
    expect(
      ProjectRules.nextStatuses(ProjectStatus.ongoing),
      containsAll([ProjectStatus.completed, ProjectStatus.onHold]),
    );
    expect(
      ProjectRules.nextStatuses(ProjectStatus.ongoing),
      isNot(contains(ProjectStatus.awarded)),
    );
    expect(ProjectRules.nextStatuses(ProjectStatus.onHold), [
      ProjectStatus.ongoing,
    ]);
    expect(ProjectRules.nextStatuses(ProjectStatus.closed), isEmpty);
  });

  test('only the owner changes status; changes are audited', () async {
    final p = await repo.saveProject(draft());
    expect(
      repo.changeStatus(
        p.id,
        ProjectStatus.bidding,
        userId: 4,
        role: AppRole.siteEngineer,
      ),
      throwsRule,
    );
    await repo.changeStatus(
      p.id,
      ProjectStatus.bidding,
      userId: 3,
      role: AppRole.owner,
    );
    final logs = await audit.getFor('project', p.id);
    expect(logs.single.details['to'], 'bidding');
  });

  test('S-curve actual matches the progress bar today', () {
    final project = MockData.projects.first;
    final cats = MockData.categories.where((c) => c.projectId == 1).toList();
    final todos = MockData.todos.where((t) => t.categoryId <= 4).toList();
    final today = DateTime(2026, 10, 25);
    final curve = computeSCurve(
      project: project,
      categories: cats,
      todos: todos,
      today: today,
    );
    final todayPoint = curve.firstWhere((p) => p.date == today);
    expect(todayPoint.actual, closeTo(0.37, 1e-9));
    expect(curve.last.actual, isNull);
    expect(curve.last.planned, closeTo(1, 1e-9));
  });

  testWidgets('owner creates a project', (tester) async {
    await pumpApp(tester);
    await signInAs(tester, 'ramon@example.ph');
    await goTo(tester, '/projects');
    await tester.tap(find.text('New project'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Code'),
      'QB-2026-040',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Project name'),
      'Bakery fit-out',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Location'),
      'Lipa',
    );
    await tester.tap(
      find.widgetWithText(DropdownButtonFormField<int>, 'Client'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Our Lady of Peace Clinic').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Contract amount'),
      '850000',
    );
    // Default retention comes from settings.
    expect(find.widgetWithText(TextFormField, '10'), findsOneWidget);

    await tester.tap(find.widgetWithText(InkWell, 'Start date'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(InkWell, 'Target end date'));
    await tester.pumpAndSettle();
    // Same date as start: rejected.
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Create project'));
    await tester.tap(find.text('Create project'));
    await tester.pumpAndSettle();
    expect(
      find.text('Target end date must be after the start date.'),
      findsOneWidget,
    );
  });

  testWidgets('PM sees overview with team and can put a project on hold', (
    tester,
  ) async {
    await pumpApp(tester);
    await signInAs(tester, 'ramon@example.ph');
    await goTo(tester, '/projects/1/overview');
    expect(find.text('Ana Bautista'), findsOneWidget);
    expect(find.text('₱2,000,000.00'), findsOneWidget);

    await tester.tap(find.text('Change status'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('On hold'));
    await tester.pumpAndSettle();
    expect(find.text('Status changed to On hold.'), findsOneWidget);
  });

  testWidgets('PM cannot open a project they are not assigned to', (
    tester,
  ) async {
    await pumpApp(tester);
    await signInAs(tester, 'ramon@example.ph');
    await goTo(tester, '/projects/3/overview');
    expect(find.text('You are not assigned to this project.'), findsOneWidget);
  });

  testWidgets('site engineer sees no money on the project', (tester) async {
    await pumpApp(tester);
    await signInAs(tester, 'ana@example.ph');
    await goTo(tester, '/projects/1/overview');
    expect(find.text('Financials'), findsNothing);
    expect(find.text('Contract amount'), findsNothing);
    expect(find.text('Earned value'), findsNothing);
    expect(find.textContaining('₱'), findsNothing);
    await goTo(tester, '/projects/1/schedule');
    expect(find.textContaining('₱'), findsNothing);
    await goTo(tester, '/projects/1/labor');
    expect(find.textContaining('₱'), findsNothing);
    await goTo(tester, '/projects/1/financials');
    expect(find.text('Budget vs. actual'), findsNothing);
  });

  testWidgets('accountant sees finance but not site work', (tester) async {
    await pumpApp(tester);
    await signInAs(tester, 'liza@example.ph');
    await goTo(tester, '/projects/1/overview');
    expect(find.text('Financials'), findsOneWidget);
    expect(find.text('Contract amount'), findsOneWidget);
    expect(find.text('Daily reports'), findsNothing);
    expect(find.text('Materials'), findsNothing);
    expect(find.text('Gantt'), findsNothing);
  });
}

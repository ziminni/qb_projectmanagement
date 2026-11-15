import 'package:buildpro_frontend/core/di/service_locator.dart';
import 'package:buildpro_frontend/data/models/app_role.dart';
import 'package:buildpro_frontend/data/models/project.dart';
import 'package:buildpro_frontend/data/models/project_assignment.dart';
import 'package:buildpro_frontend/data/repositories/mock_audit_log_repository.dart';
import 'package:buildpro_frontend/data/repositories/mock_data.dart';
import 'package:buildpro_frontend/data/repositories/mock_project_repository.dart';
import 'package:buildpro_frontend/data/repositories/project_repository.dart';
import 'package:buildpro_frontend/data/repositories/mock_user_repository.dart';
import 'package:buildpro_frontend/data/services/business_rule_exception.dart';
import 'package:buildpro_frontend/data/repositories/schedule_repository.dart';
import 'package:buildpro_frontend/data/services/progress_calculator.dart';
import 'package:buildpro_frontend/data/services/project_rules.dart';
import 'package:buildpro_frontend/data/services/session_service.dart';
import 'package:buildpro_frontend/shared/widgets/app_location_map.dart';
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

  test(
    'new projects wait for acceptance, with an upper-case unique code',
    () async {
      final p = await repo.saveProject(draft());
      expect(p.status, ProjectStatus.requested);
      expect(p.code, 'QB-2026-099');
      expect(repo.saveProject(draft()), throwsRule);
    },
  );

  test('status moves forward only; On hold returns to Ongoing', () {
    expect(ProjectRules.nextStatuses(ProjectStatus.requested), isEmpty);
    expect(ProjectRules.nextStatuses(ProjectStatus.changesRequested), isEmpty);
    expect(ProjectRules.nextStatuses(ProjectStatus.accepted), [
      ProjectStatus.ongoing,
    ]);
    expect(
      ProjectRules.nextStatuses(ProjectStatus.ongoing),
      containsAll([ProjectStatus.completed, ProjectStatus.onHold]),
    );
    expect(ProjectRules.nextStatuses(ProjectStatus.onHold), [
      ProjectStatus.ongoing,
    ]);
    expect(ProjectRules.nextStatuses(ProjectStatus.closed), isEmpty);
  });

  test('only the owner changes status; changes are audited', () async {
    // Project 3 is Accepted.
    expect(
      repo.changeStatus(
        3,
        ProjectStatus.ongoing,
        userId: 8,
        role: AppRole.siteEngineer,
      ),
      throwsRule,
    );
    await repo.changeStatus(
      3,
      ProjectStatus.ongoing,
      userId: 8,
      role: AppRole.owner,
    );
    final logs = await audit.getFor('project', 3);
    expect(logs.single.details['to'], 'ongoing');
  });

  group('project requests', () {
    Future<Project> sent() async {
      final p = await repo.saveProject(draft());
      await repo.assign(p.id, 3, AppRole.owner);
      await repo.assign(p.id, 7, AppRole.client);
      await repo.assign(p.id, 4, AppRole.siteEngineer);
      return p;
    }

    ProjectAssignment mine(List<ProjectRequest> rs, int projectId) =>
        rs.firstWhere((r) => r.project.id == projectId).assignment;

    Future<List<ProjectRequest>> forAna() =>
        repo.getRequestsFor(4, AppRole.siteEngineer);

    test(
      'the foreman gets the request only after the client accepts',
      () async {
        final p = await sent();
        expect((await forAna()).any((r) => r.project.id == p.id), isFalse);

        final mark = mine(await repo.getRequestsFor(7, AppRole.client), p.id);
        expect(
          repo.respondToRequest(
            mark.id,
            userId: 4,
            answer: RequestResponse.accepted,
          ),
          throwsRule,
        );
        await repo.respondToRequest(
          mark.id,
          userId: 7,
          answer: RequestResponse.accepted,
        );
        expect(
          (await repo.getProject(p.id))!.status,
          ProjectStatus.siteEngineerPending,
        );
        // Not on the project until they accept.
        expect(await repo.isAssigned(p.id, 4, AppRole.siteEngineer), isFalse);

        final ana = mine(await forAna(), p.id);
        await repo.respondToRequest(
          ana.id,
          userId: 4,
          answer: RequestResponse.accepted,
        );
        expect((await repo.getProject(p.id))!.status, ProjectStatus.accepted);
        expect(await repo.isAssigned(p.id, 4, AppRole.siteEngineer), isTrue);
      },
    );

    test(
      'client asks for changes; the owner revises and sends it again',
      () async {
        final p = await sent();
        final mark = mine(await repo.getRequestsFor(7, AppRole.client), p.id);
        expect(
          repo.respondToRequest(
            mark.id,
            userId: 7,
            answer: RequestResponse.changesRequested,
            note: ' ',
          ),
          throwsRule,
        );
        await repo.respondToRequest(
          mark.id,
          userId: 7,
          answer: RequestResponse.changesRequested,
          note: 'Move the start to February',
        );
        expect(
          (await repo.getProject(p.id))!.status,
          ProjectStatus.changesRequested,
        );
        final note = (await repo.getAssignments(
          p.id,
        )).firstWhere((a) => a.userId == 7).note;
        expect(note, 'Move the start to February');

        expect(repo.resendRequest(p.id, userId: 4), throwsRule);
        await repo.resendRequest(p.id, userId: 3);
        expect((await repo.getProject(p.id))!.status, ProjectStatus.requested);
        expect(
          (await repo.getRequestsFor(
            7,
            AppRole.client,
          )).any((r) => r.project.id == p.id),
          isTrue,
        );
      },
    );

    test('a client decline needs a reason and deletes the project', () async {
      final p = await sent();
      final mark = mine(await repo.getRequestsFor(7, AppRole.client), p.id);
      expect(
        repo.respondToRequest(
          mark.id,
          userId: 7,
          answer: RequestResponse.declined,
        ),
        throwsRule,
      );
      await repo.respondToRequest(
        mark.id,
        userId: 7,
        answer: RequestResponse.declined,
        note: 'Going with another contractor',
      );
      expect(await repo.getProject(p.id), isNull);
      expect(await repo.getAssignments(p.id), isEmpty);
    });

    test('only the client can ask for changes', () async {
      final p = await sent();
      final mark = mine(await repo.getRequestsFor(7, AppRole.client), p.id);
      await repo.respondToRequest(
        mark.id,
        userId: 7,
        answer: RequestResponse.accepted,
      );
      final ana = mine(await forAna(), p.id);
      expect(
        repo.respondToRequest(
          ana.id,
          userId: 4,
          answer: RequestResponse.changesRequested,
          note: 'x',
        ),
        throwsRule,
      );
    });

    test('a site engineer decline waits for a replacement', () async {
      final p = await sent();
      final mark = mine(await repo.getRequestsFor(7, AppRole.client), p.id);
      await repo.respondToRequest(
        mark.id,
        userId: 7,
        answer: RequestResponse.accepted,
      );
      final ana = mine(await forAna(), p.id);
      await repo.respondToRequest(
        ana.id,
        userId: 4,
        answer: RequestResponse.declined,
        note: 'Already full-time on QB-2026-014',
      );
      expect(
        (await repo.getProject(p.id))!.status,
        ProjectStatus.siteEngineerPending,
      );

      // The client already accepted, so the new request goes out at once.
      await repo.assign(p.id, 8, AppRole.siteEngineer);
      final elena = mine(
        await repo.getRequestsFor(8, AppRole.siteEngineer),
        p.id,
      );
      await repo.respondToRequest(
        elena.id,
        userId: 8,
        answer: RequestResponse.accepted,
      );
      expect((await repo.getProject(p.id))!.status, ProjectStatus.accepted);
    });
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

  testWidgets('owner creates a project with the four-step wizard', (
    tester,
  ) async {
    await pumpApp(tester, size: const Size(1400, 1200));
    await signInAs(tester, 'ramon@example.ph');
    await goTo(tester, '/projects');
    await tester.tap(find.text('New project').first);
    await tester.pumpAndSettle();
    expect(find.text('Step 1 of 4 · Project details'), findsOneWidget);

    // Step 1 checks the client login, foreman and dates before moving on.
    await tester.tap(
      find.widgetWithText(DropdownButtonFormField<int>, 'Client'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Our Lady of Peace Clinic').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next: Location'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'This client has no app login yet. Ask the admin to create one.',
      ),
      findsOneWidget,
    );
    expect(find.text('Choose the site engineer.'), findsOneWidget);
    expect(find.text('Choose the start and target end dates.'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Code'),
      'QB-2026-040',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Project name'),
      'Bakery fit-out',
    );
    await tester.tap(
      find.widgetWithText(DropdownButtonFormField<int>, 'Client'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mark Villanueva').last);
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(
        DropdownButtonFormField<int>,
        'Site engineer / foreman',
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ana Bautista').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(InkWell, 'Start date'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(InkWell, 'Target end date'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('28'));
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next: Location'));
    await tester.pumpAndSettle();

    // Step 2: address and a pin dropped on the map.
    expect(find.text('Step 2 of 4 · Location'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Location'),
      'Poblacion, Lipa City',
    );
    await tester.tapAt(tester.getCenter(find.byType(AppLocationMap)));
    await tester.pumpAndSettle();
    expect(find.text('Clear pin'), findsOneWidget);
    await tester.tap(find.text('Next: Budget'));
    await tester.pumpAndSettle();

    // Step 3: categories cannot add up to more than the contract.
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Contract amount'),
      '850000',
    );
    await tester.tap(find.widgetWithText(ActionChip, 'Foundation'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ActionChip, 'Roofing'));
    await tester.pumpAndSettle();
    final budgets = find.widgetWithText(TextFormField, 'Budget');
    await tester.enterText(budgets.at(0), '600000');
    await tester.enterText(budgets.at(1), '400000');
    await tester.pumpAndSettle();
    expect(find.text('Over by'), findsOneWidget);
    await tester.tap(find.text('Next: Review'));
    await tester.pumpAndSettle();
    expect(find.text('Step 3 of 4 · Budget'), findsOneWidget);
    await tester.enterText(budgets.at(1), '250000');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next: Review'));
    await tester.pumpAndSettle();

    // Step 4: review, then create.
    expect(find.text('Bakery fit-out'), findsOneWidget);
    expect(find.text('₱850,000.00'), findsWidgets);
    await tester.tap(find.text('Create and send request'));
    await tester.pumpAndSettle();
    expect(
      find.text('Project created and sent to the client.'),
      findsOneWidget,
    );
    expect(find.text('Bakery fit-out'), findsWidgets);

    final created = (await getIt<ProjectRepository>().getProjects()).firstWhere(
      (p) => p.code == 'QB-2026-040',
    );
    expect(created.status, ProjectStatus.requested);
    expect(created.hasPin, isTrue);
    final categories = await getIt<ScheduleRepository>().getCategories(
      created.id,
    );
    expect(categories.map((c) => c.name), ['Foundation', 'Roofing']);
    expect(categories.map((c) => c.budget), [600000, 250000]);
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

  testWidgets('client accepts, then the foreman gets the request', (
    tester,
  ) async {
    await pumpApp(tester);
    await signInAs(tester, 'mark@example.ph');
    expect(find.text('New project request'), findsOneWidget);
    expect(find.text('₱6,800,000.00'), findsOneWidget);
    expect(find.text('Request changes'), findsOneWidget);
    await tester.tap(find.text('Accept'));
    await tester.pumpAndSettle();
    expect(find.text('Request accepted.'), findsOneWidget);

    getIt<SessionService>().signOut();
    await tester.pumpAndSettle();
    await signInAs(tester, 'ana@example.ph');
    await goTo(tester, '/projects');
    expect(find.text('New project request'), findsOneWidget);
    // The foreman never sees the price or a Request changes option.
    expect(find.text('Contract amount'), findsNothing);
    expect(find.text('Request changes'), findsNothing);
    await tester.tap(find.text('Accept'));
    await tester.pumpAndSettle();
    expect(find.text('Request accepted.'), findsOneWidget);
    expect(find.text('New project request'), findsNothing);
  });

  testWidgets('foreman sees nothing until the client accepts', (tester) async {
    await pumpApp(tester);
    await signInAs(tester, 'ana@example.ph');
    await goTo(tester, '/projects');
    expect(find.text('New project request'), findsNothing);
  });

  testWidgets('client asks for changes and the owner sees the note', (
    tester,
  ) async {
    await pumpApp(tester);
    await signInAs(tester, 'mark@example.ph');
    await tester.tap(find.text('Request changes'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'Add a carport');
    await tester.tap(find.widgetWithText(FilledButton, 'Send to owner'));
    await tester.pumpAndSettle();
    expect(
      find.text('Your requested changes were sent to the owner.'),
      findsOneWidget,
    );

    getIt<SessionService>().signOut();
    await tester.pumpAndSettle();
    await signInAs(tester, 'ramon@example.ph');
    await goTo(tester, '/projects/4/overview');
    expect(find.text('Changes requested'), findsWidgets);
    expect(find.textContaining('Add a carport'), findsWidgets);
    await tester.tap(find.text('Send again'));
    await tester.pumpAndSettle();
    expect(find.text('Request sent to the client again.'), findsOneWidget);
  });

  testWidgets('client declines after confirming the deletion', (tester) async {
    await pumpApp(tester);
    await signInAs(tester, 'mark@example.ph');
    await tester.tap(find.text('Decline'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'Too expensive');
    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Delete this project request?'), findsOneWidget);
    await tester.tap(find.text('Decline and delete'));
    await tester.pumpAndSettle();
    expect(find.text('Project declined and deleted.'), findsOneWidget);
    expect(find.text('New project request'), findsNothing);

    getIt<SessionService>().signOut();
    await tester.pumpAndSettle();
    await signInAs(tester, 'ramon@example.ph');
    await goTo(tester, '/projects');
    expect(find.text('Townhouse row, Malvar'), findsNothing);
  });
}

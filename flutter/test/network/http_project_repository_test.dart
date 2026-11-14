import 'package:buildpro_frontend/data/models/app_role.dart';
import 'package:buildpro_frontend/data/models/project.dart';
import 'package:buildpro_frontend/data/models/project_assignment.dart';
import 'package:buildpro_frontend/data/repositories/http_project_repository.dart';
import 'package:buildpro_frontend/data/services/business_rule_exception.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_api.dart';

/// A project row as the server sends it. [finance] false is what an admin or
/// a site engineer receives: the three peso keys are omitted.
Map<String, dynamic> projectRow({
  int id = 1,
  String code = 'QB-2026-001',
  String status = 'requested',
  bool finance = true,
}) => {
  'id': id,
  'code': code,
  'name': 'Our Lady of Peace Clinic',
  'location': 'Lipa City',
  'latitude': null,
  'longitude': null,
  'client_id': 3,
  if (finance) 'contract_amount': '2000000.00',
  if (finance) 'down_payment_pct': '15.00',
  if (finance) 'retention_pct': '10.00',
  'start_date': '2026-08-01',
  'target_end_date': '2026-12-31',
  'actual_end_date': null,
  'status': status,
  'created_at': '2026-07-01T02:00:00Z',
  'updated_at': '2026-07-01T02:00:00Z',
};

Map<String, dynamic> assignmentRow({
  int id = 11,
  int projectId = 1,
  int userId = 5,
  String role = 'owner',
  String response = 'accepted',
  String? note,
}) => {
  'id': id,
  'project_id': projectId,
  'user_id': userId,
  'role_on_project': role,
  'response': response,
  'note': note,
  'responded_at': null,
  'created_at': '2026-07-01T02:00:00Z',
  'updated_at': '2026-07-01T02:00:00Z',
};

void main() {
  group('http project repository', () {
    test('reads the scoped project list from the server', () async {
      final api = FakeApi(
        (options) => json([projectRow(id: 1), projectRow(id: 2)]),
      );
      final repo = HttpProjectRepository(
        testClient(api: api, tokens: InMemoryTokenStore()),
      );

      final projects = await repo.getProjects();

      expect(api.last('projects/').method, 'GET');
      expect(projects.map((p) => p.id), [1, 2]);
      expect(projects.first.contractAmount, 2000000);
      expect(projects.first.status, ProjectStatus.requested);
    });

    test('getProjectsFor ignores the ids and lets the server scope', () async {
      final api = FakeApi((options) => json([projectRow(id: 1)]));
      final repo = HttpProjectRepository(
        testClient(api: api, tokens: InMemoryTokenStore()),
      );

      final projects = await repo.getProjectsFor(7, AppRole.siteEngineer);

      expect(api.last('projects/').method, 'GET');
      expect(api.last('projects/').queryParameters, isEmpty);
      expect(projects.single.id, 1);
    });

    test('parses a project whose finance keys were redacted', () async {
      final api = FakeApi((options) => json(projectRow(finance: false)));
      final repo = HttpProjectRepository(
        testClient(api: api, tokens: InMemoryTokenStore()),
      );

      final project = await repo.getProject(1);

      expect(project!.contractAmount, 0);
      expect(project.downPaymentPct, 0);
      expect(project.retentionPct, 0);
    });

    test('returns null for a project outside the caller scope', () async {
      final api = FakeApi(
        (options) => json({'detail': 'Not found.'}, status: 404),
      );
      final repo = HttpProjectRepository(
        testClient(api: api, tokens: InMemoryTokenStore()),
      );

      expect(await repo.getProject(99), isNull);
    });

    test('creates a project with the details and no status', () async {
      final api = FakeApi((options) => json(projectRow(id: 40), status: 201));
      final repo = HttpProjectRepository(
        testClient(api: api, tokens: InMemoryTokenStore()),
      );

      final saved = await repo.saveProject(
        Project(
          id: 0,
          code: ' QB-2026-040 ',
          name: 'Bakery fit-out',
          location: 'Poblacion',
          latitude: 13.9,
          longitude: 121.1,
          clientId: 3,
          contractAmount: 850000,
          downPaymentPct: 15,
          retentionPct: 10,
          startDate: DateTime(2026, 8, 3),
          targetEndDate: DateTime(2026, 12, 28),
          status: ProjectStatus.requested,
        ),
      );

      final request = api.last('projects/');
      expect(request.method, 'POST');
      final sent = sentBody(request);
      expect(sent['code'], 'QB-2026-040');
      expect(sent['client_id'], 3);
      expect(sent['contract_amount'], 850000);
      expect(sent['down_payment_pct'], 15);
      expect(sent['retention_pct'], 10);
      expect(sent['start_date'], '2026-08-03');
      expect(sent['target_end_date'], '2026-12-28');
      expect(sent['latitude'], 13.9);
      // The server sets these; sending them would be ignored or refused.
      expect(sent.containsKey('status'), isFalse);
      expect(sent.containsKey('id'), isFalse);
      expect(saved.id, 40);
    });

    test('updates a project with a patch', () async {
      final api = FakeApi((options) => json(projectRow(id: 4)));
      final repo = HttpProjectRepository(
        testClient(api: api, tokens: InMemoryTokenStore()),
      );

      final saved = await repo.saveProject(Project.fromJson(projectRow(id: 4)));

      final request = api.last('projects/4/');
      expect(request.method, 'PATCH');
      expect(sentBody(request)['name'], 'Our Lady of Peace Clinic');
      expect(saved.id, 4);
    });

    test('shows the server refusal text when a save is refused', () async {
      final api = FakeApi(
        (options) => json({
          'detail': 'Another project already uses this code.',
        }, status: 400),
      );
      final repo = HttpProjectRepository(
        testClient(api: api, tokens: InMemoryTokenStore()),
      );

      expect(
        repo.saveProject(Project.fromJson(projectRow())),
        throwsA(
          isA<BusinessRuleException>().having(
            (e) => e.message,
            'message',
            'Another project already uses this code.',
          ),
        ),
      );
    });

    test('changes the status through its own route', () async {
      final api = FakeApi((options) => json(projectRow(status: 'ongoing')));
      final repo = HttpProjectRepository(
        testClient(api: api, tokens: InMemoryTokenStore()),
      );

      final project = await repo.changeStatus(
        1,
        ProjectStatus.ongoing,
        userId: 5,
        role: AppRole.owner,
      );

      final request = api.last('projects/1/status/');
      expect(request.method, 'POST');
      expect(sentBody(request), {'status': 'ongoing'});
      expect(project.status, ProjectStatus.ongoing);
    });

    test('reads the team of a project', () async {
      final api = FakeApi(
        (options) => json([
          assignmentRow(id: 11),
          assignmentRow(id: 12, userId: 7, role: 'client', response: 'pending'),
        ]),
      );
      final repo = HttpProjectRepository(
        testClient(api: api, tokens: InMemoryTokenStore()),
      );

      final team = await repo.getAssignments(1);

      expect(api.last('projects/1/assignments/').method, 'GET');
      expect(team.map((a) => a.id), [11, 12]);
      expect(team.last.response, RequestResponse.pending);
      expect(team.last.roleOnProject, AppRole.client);
    });

    test('reads the assignments of a user', () async {
      final api = FakeApi((options) => json([assignmentRow()]));
      final repo = HttpProjectRepository(
        testClient(api: api, tokens: InMemoryTokenStore()),
      );

      final rows = await repo.getAssignmentsForUser(5);

      expect(api.last('project-assignments/').queryParameters['user'], 5);
      expect(rows.single.userId, 5);
    });

    test('isAssigned asks only for accepted rows', () async {
      final api = FakeApi((options) => json([assignmentRow(projectId: 2)]));
      final repo = HttpProjectRepository(
        testClient(api: api, tokens: InMemoryTokenStore()),
      );

      expect(await repo.isAssigned(2, 5, AppRole.owner), isTrue);
      expect(await repo.isAssigned(1, 5, AppRole.owner), isFalse);

      final query = api.last('project-assignments/').queryParameters;
      expect(query['user'], 5);
      expect(query['role_on_project'], 'owner');
      expect(query['response'], 'accepted');
    });

    test('replaces a user assignments with a put', () async {
      final api = FakeApi((options) => json([assignmentRow()]));
      final repo = HttpProjectRepository(
        testClient(api: api, tokens: InMemoryTokenStore()),
      );

      await repo.setUserAssignments(5, [
        (projectId: 1, role: AppRole.owner),
        (projectId: 2, role: AppRole.siteEngineer),
      ]);

      final request = api.last('users/5/assignments/');
      expect(request.method, 'PUT');
      expect(sentBody(request), {
        'assignments': [
          {'project_id': 1, 'role': 'owner'},
          {'project_id': 2, 'role': 'site_engineer'},
        ],
      });
    });

    test('adds a member to a project', () async {
      final api = FakeApi(
        (options) => json(
          assignmentRow(id: 12, userId: 7, role: 'client', response: 'pending'),
          status: 201,
        ),
      );
      final repo = HttpProjectRepository(
        testClient(api: api, tokens: InMemoryTokenStore()),
      );

      final created = await repo.assign(1, 7, AppRole.client);

      final request = api.last('projects/1/assignments/');
      expect(request.method, 'POST');
      expect(sentBody(request), {'user_id': 7, 'role_on_project': 'client'});
      expect(created.response, RequestResponse.pending);
    });

    test('removes a member', () async {
      final api = FakeApi((options) => noContent());
      final repo = HttpProjectRepository(
        testClient(api: api, tokens: InMemoryTokenStore()),
      );

      await repo.unassign(11);

      final request = api.last('project-assignments/11/');
      expect(request.method, 'DELETE');
    });

    test('reads the requests waiting for the caller', () async {
      final api = FakeApi(
        (options) => json([
          {
            'project': projectRow(id: 2, finance: false),
            'assignment': assignmentRow(
              id: 12,
              projectId: 2,
              userId: 7,
              role: 'client',
              response: 'pending',
            ),
          },
        ]),
      );
      final repo = HttpProjectRepository(
        testClient(api: api, tokens: InMemoryTokenStore()),
      );

      final requests = await repo.getRequestsFor(7, AppRole.client);

      expect(api.last('project-requests/').method, 'GET');
      expect(requests.single.project.id, 2);
      expect(requests.single.assignment.id, 12);
      expect(requests.single.project.contractAmount, 0);
    });

    test('answers a request with a note', () async {
      final api = FakeApi(
        (options) => json(
          assignmentRow(
            id: 12,
            userId: 7,
            role: 'client',
            response: 'changes_requested',
            note: 'Move the gate.',
          ),
        ),
      );
      final repo = HttpProjectRepository(
        testClient(api: api, tokens: InMemoryTokenStore()),
      );

      final answered = await repo.respondToRequest(
        12,
        userId: 7,
        answer: RequestResponse.changesRequested,
        note: 'Move the gate.',
      );

      final request = api.last('project-assignments/12/respond/');
      expect(request.method, 'POST');
      expect(sentBody(request), {
        'response': 'changes_requested',
        'note': 'Move the gate.',
      });
      expect(answered.response, RequestResponse.changesRequested);
    });

    test('sends a revised project again', () async {
      final api = FakeApi((options) => json(projectRow(status: 'requested')));
      final repo = HttpProjectRepository(
        testClient(api: api, tokens: InMemoryTokenStore()),
      );

      final project = await repo.resendRequest(1, userId: 5);

      expect(api.last('projects/1/resend/').method, 'POST');
      expect(project.status, ProjectStatus.requested);
    });

    test(
      'has no variation route: the server applies it on VO approval',
      () async {
        final api = FakeApi((options) => json(projectRow()));
        final repo = HttpProjectRepository(
          testClient(api: api, tokens: InMemoryTokenStore()),
        );

        expect(
          repo.applyVariation(1, amountDelta: 50000, daysImpact: 7),
          throwsUnsupportedError,
        );
        expect(api.requests, isEmpty);
      },
    );
  });
}

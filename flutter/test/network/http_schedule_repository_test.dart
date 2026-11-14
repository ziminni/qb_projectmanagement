import 'package:buildpro_frontend/data/models/category.dart';
import 'package:buildpro_frontend/data/models/todo.dart';
import 'package:buildpro_frontend/data/repositories/http_schedule_repository.dart';
import 'package:buildpro_frontend/data/services/business_rule_exception.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_api.dart';

/// A category row as the server sends it. Non-finance roles get `weight`
/// instead of `budget`.
Map<String, dynamic> categoryRow({
  int id = 1,
  int projectId = 1,
  String name = 'Foundation',
  String? budget = '500000.00',
  String? weight = '0.25',
  int sortOrder = 1,
}) => {
  'id': id,
  'project_id': projectId,
  'name': name,
  'budget': budget,
  'weight': weight,
  'sort_order': sortOrder,
  'created_at': '2026-07-01T02:00:00Z',
  'updated_at': '2026-07-01T02:00:00Z',
};

Map<String, dynamic> todoRow({
  int id = 1,
  int categoryId = 1,
  String title = 'Excavation',
  bool done = false,
  bool verified = false,
}) => {
  'id': id,
  'category_id': categoryId,
  'title': title,
  'start_date': '2026-08-03',
  'end_date': '2026-08-10',
  'is_done': done,
  'done_by': done ? 4 : null,
  'done_at': done ? '2026-08-11T02:00:00Z' : null,
  'is_verified': verified,
  'verified_by': verified ? 5 : null,
  'verified_at': verified ? '2026-08-12T02:00:00Z' : null,
  'daily_report_id': null,
  'created_at': '2026-07-01T02:00:00Z',
  'updated_at': '2026-07-01T02:00:00Z',
};

void main() {
  group('http schedule repository', () {
    test('reads the categories of a project', () async {
      final api = FakeApi(
        (options) =>
            json([categoryRow(id: 1), categoryRow(id: 2, name: 'Roof')]),
      );
      final repo = HttpScheduleRepository(
        testClient(api: api, tokens: InMemoryTokenStore()),
      );

      final categories = await repo.getCategories(1);

      expect(api.last('projects/1/categories/').method, 'GET');
      expect(categories.map((c) => c.name), ['Foundation', 'Roof']);
      expect(categories.first.budget, 500000);
      expect(categories.first.weight, 0.25);
    });

    test('reads a budget-redacted category through its weight', () async {
      final api = FakeApi(
        (options) => json([categoryRow(budget: null, weight: '0.4')]),
      );
      final repo = HttpScheduleRepository(
        testClient(api: api, tokens: InMemoryTokenStore()),
      );

      final category = (await repo.getCategories(1)).single;

      expect(category.budget, isNull);
      expect(category.hasBudget, isFalse);
      expect(category.weight, 0.4);
    });

    test('reads the to-dos of a project', () async {
      final api = FakeApi(
        (options) => json([
          todoRow(id: 1),
          todoRow(id: 2, title: 'Rebar', done: true, verified: true),
        ]),
      );
      final repo = HttpScheduleRepository(
        testClient(api: api, tokens: InMemoryTokenStore()),
      );

      final todos = await repo.getTodos(1);

      expect(api.last('projects/1/todos/').method, 'GET');
      expect(todos.map((t) => t.id), [1, 2]);
      expect(todos.first.isDone, isFalse);
      expect(todos.last.isVerified, isTrue);
      expect(todos.last.startDate, DateTime(2026, 8, 3));
    });

    test('creates a category under its project', () async {
      final api = FakeApi((options) => json(categoryRow(id: 9), status: 201));
      final repo = HttpScheduleRepository(
        testClient(api: api, tokens: InMemoryTokenStore()),
      );

      final saved = await repo.saveCategory(
        const Category(
          id: 0,
          projectId: 1,
          name: ' Roofing ',
          budget: 250000,
          sortOrder: 2,
        ),
      );

      final request = api.last('projects/1/categories/');
      expect(request.method, 'POST');
      expect(sentBody(request), {
        'name': 'Roofing',
        'budget': 250000,
        'sort_order': 2,
      });
      expect(saved.id, 9);
    });

    test('updates a category with a patch', () async {
      final api = FakeApi((options) => json(categoryRow(id: 1)));
      final repo = HttpScheduleRepository(
        testClient(api: api, tokens: InMemoryTokenStore()),
      );

      await repo.saveCategory(
        const Category(
          id: 1,
          projectId: 1,
          name: 'Foundation',
          budget: null,
          sortOrder: 1,
        ),
      );

      final request = api.last('categories/1/');
      expect(request.method, 'PATCH');
      // No budget: the category is weighted equally.
      expect(sentBody(request), {
        'name': 'Foundation',
        'budget': null,
        'sort_order': 1,
      });
    });

    test('deletes a category', () async {
      final api = FakeApi((options) => noContent());
      final repo = HttpScheduleRepository(
        testClient(api: api, tokens: InMemoryTokenStore()),
      );

      await repo.deleteCategory(3);

      expect(api.last('categories/3/').method, 'DELETE');
    });

    test('shows the server text when a category is refused', () async {
      final api = FakeApi(
        (options) => json({
          'detail': 'This category has verified to-dos and cannot be deleted.',
        }, status: 400),
      );
      final repo = HttpScheduleRepository(
        testClient(api: api, tokens: InMemoryTokenStore()),
      );

      expect(
        repo.deleteCategory(3),
        throwsA(
          isA<BusinessRuleException>().having(
            (e) => e.message,
            'message',
            'This category has verified to-dos and cannot be deleted.',
          ),
        ),
      );
    });

    test('creates a to-do', () async {
      final api = FakeApi((options) => json(todoRow(id: 21), status: 201));
      final repo = HttpScheduleRepository(
        testClient(api: api, tokens: InMemoryTokenStore()),
      );

      final saved = await repo.saveTodo(
        Todo(
          id: 0,
          categoryId: 1,
          title: ' Excavation ',
          startDate: DateTime(2026, 8, 3),
          endDate: DateTime(2026, 8, 10),
        ),
      );

      final request = api.last('todos/');
      expect(request.method, 'POST');
      expect(sentBody(request), {
        'category_id': 1,
        'title': 'Excavation',
        'start_date': '2026-08-03',
        'end_date': '2026-08-10',
      });
      expect(saved.id, 21);
    });

    test('updates a to-do and never its done or verified flags', () async {
      final api = FakeApi((options) => json(todoRow(id: 1)));
      final repo = HttpScheduleRepository(
        testClient(api: api, tokens: InMemoryTokenStore()),
      );

      await repo.saveTodo(
        Todo(
          id: 1,
          categoryId: 2,
          title: 'Excavation',
          startDate: DateTime(2026, 8, 3),
          endDate: DateTime(2026, 8, 10),
          isDone: true,
          isVerified: true,
        ),
      );

      final request = api.last('todos/1/');
      expect(request.method, 'PATCH');
      final sent = sentBody(request);
      expect(sent['category_id'], 2);
      expect(sent.containsKey('is_done'), isFalse);
      expect(sent.containsKey('is_verified'), isFalse);
    });

    test('deletes a to-do', () async {
      final api = FakeApi((options) => noContent());
      final repo = HttpScheduleRepository(
        testClient(api: api, tokens: InMemoryTokenStore()),
      );

      await repo.deleteTodo(4);

      expect(api.last('todos/4/').method, 'DELETE');
    });

    test('marks a to-do done through its own route', () async {
      final api = FakeApi((options) => json(todoRow(done: true)));
      final repo = HttpScheduleRepository(
        testClient(api: api, tokens: InMemoryTokenStore()),
      );

      final todo = await repo.setDone(1, done: true, userId: 4);

      final request = api.last('todos/1/done/');
      expect(request.method, 'POST');
      expect(sentBody(request), {'done': true});
      expect(todo.isDone, isTrue);
    });

    test('verifies and un-verifies a to-do', () async {
      final api = FakeApi((options) {
        final unverify = options.path == 'todos/1/unverify/';
        return json(todoRow(verified: !unverify));
      });
      final repo = HttpScheduleRepository(
        testClient(api: api, tokens: InMemoryTokenStore()),
      );

      expect((await repo.verify(1, userId: 5)).isVerified, isTrue);
      expect(api.last('todos/1/verify/').method, 'POST');

      expect(
        (await repo.unverify(1, userId: 5, reason: 'Photo is old.')).isVerified,
        isFalse,
      );
      expect(sentBody(api.last('todos/1/unverify/')), {
        'reason': 'Photo is old.',
      });
    });

    test('has no report link route: a report save links its to-dos', () async {
      final api = FakeApi((options) => json(todoRow()));
      final repo = HttpScheduleRepository(
        testClient(api: api, tokens: InMemoryTokenStore()),
      );

      expect(repo.setReportLink(1, 9), throwsUnsupportedError);
      expect(api.requests, isEmpty);
    });
  });
}

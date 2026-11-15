import 'package:buildpro_frontend/data/models/category.dart';
import 'package:buildpro_frontend/data/models/todo.dart';
import 'package:buildpro_frontend/data/repositories/mock_audit_log_repository.dart';
import 'package:buildpro_frontend/data/repositories/mock_project_repository.dart';
import 'package:buildpro_frontend/data/repositories/mock_schedule_repository.dart';
import 'package:buildpro_frontend/data/repositories/mock_user_repository.dart';
import 'package:buildpro_frontend/data/services/schedule_rules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late MockScheduleRepository repo;
  late MockAuditLogRepository audit;

  setUp(() {
    audit = MockAuditLogRepository();
    repo = MockScheduleRepository(
      projects: MockProjectRepository(
        users: MockUserRepository(),
        auditLog: audit,
      ),
      auditLog: audit,
    );
  });

  Matcher throwsRule(String fragment) => throwsA(
    isA<ScheduleRuleException>().having(
      (e) => e.message,
      'message',
      contains(fragment),
    ),
  );

  test('category budgets cannot exceed the contract amount', () {
    // Project 1 budgets already total the ₱2,000,000 contract.
    expect(
      repo.saveCategory(
        const Category(
          id: 0,
          projectId: 1,
          name: 'Painting',
          budget: 1,
          sortOrder: 5,
        ),
      ),
      throwsRule('exceed the contract amount'),
    );
  });

  test('a category with verified to-dos cannot be deleted', () {
    expect(repo.deleteCategory(1), throwsRule('cannot be deleted'));
  });

  test('a category without verified to-dos can be deleted', () async {
    await repo.deleteCategory(3);
    final cats = await repo.getCategories(1);
    expect(cats.map((c) => c.id), isNot(contains(3)));
    final todos = await repo.getTodos(1);
    expect(todos.where((t) => t.categoryId == 3), isEmpty);
  });

  test('to-do dates must fall within the project schedule', () {
    expect(
      repo.saveTodo(
        Todo(
          id: 0,
          categoryId: 3,
          title: 'Too early',
          startDate: DateTime(2026, 7, 1),
          endDate: DateTime(2026, 8, 5),
        ),
      ),
      throwsRule('within the project schedule'),
    );
    expect(
      repo.saveTodo(
        Todo(
          id: 0,
          categoryId: 3,
          title: 'Backwards',
          startDate: DateTime(2026, 11, 5),
          endDate: DateTime(2026, 11, 1),
        ),
      ),
      throwsRule('on or after the start date'),
    );
  });

  test(
    'only done to-dos can be verified, and verification is logged',
    () async {
      expect(repo.verify(9, userId: 3), throwsRule('marked done'));
      final verified = await repo.verify(8, userId: 3);
      expect(verified.isVerified, isTrue);
      expect(verified.verifiedBy, 3);
      final logs = await audit.getFor('todo', 8);
      expect(logs.single.action, 'todo_verified');
    },
  );

  test('un-verifying needs a reason and is logged with it', () async {
    expect(repo.unverify(1, userId: 3, reason: '  '), throwsRule('reason'));
    final todo = await repo.unverify(
      1,
      userId: 3,
      reason: 'Honeycombing found',
    );
    expect(todo.isVerified, isFalse);
    expect(todo.isDone, isTrue);
    final log = (await audit.getFor('todo', 1)).single;
    expect(log.action, 'todo_unverified');
    expect(log.details['reason'], 'Honeycombing found');
  });

  test('a verified to-do cannot be unchecked or deleted', () {
    expect(repo.setDone(1, done: false, userId: 4), throwsRule('un-verify'));
    expect(repo.deleteTodo(1), throwsRule('cannot be deleted'));
  });
}

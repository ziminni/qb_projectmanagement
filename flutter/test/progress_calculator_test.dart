import 'package:buildpro_frontend/data/models/category.dart';
import 'package:buildpro_frontend/data/models/project.dart';
import 'package:buildpro_frontend/data/models/todo.dart';
import 'package:buildpro_frontend/data/repositories/mock_data.dart';
import 'package:buildpro_frontend/data/services/progress_calculator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final project = MockData.projects.first;
  final categories = MockData.categories
      .where((c) => c.projectId == 1)
      .toList();
  final todos = MockData.todos
      .where((t) => categories.any((c) => c.id == t.categoryId))
      .toList();

  ProjectProgress compute({
    List<Category>? cats,
    List<Todo>? items,
    DateTime? asOf,
  }) => computeProjectProgress(
    project: project,
    categories: cats ?? categories,
    todos: items ?? todos,
    asOf: asOf ?? DateTime(2026, 10, 25),
  );

  group('document sample (₱2,000,000 contract)', () {
    test('budget-weighted progress is 37%', () {
      final p = compute();
      expect(p.usesBudgetWeights, isTrue);
      expect(p.progress, closeTo(0.37, 1e-9));
      expect(p.earnedValue, closeTo(740000, 1e-6));
    });

    test('category weights, progress and status', () {
      final p = compute();
      final byName = {for (final c in p.categories) c.category.name: c};
      expect(byName['Foundation']!.weight, closeTo(0.25, 1e-9));
      expect(byName['Pillars']!.weight, closeTo(0.20, 1e-9));
      expect(byName['Roofing']!.weight, closeTo(0.30, 1e-9));
      expect(byName['Foundation']!.progress, 1);
      expect(byName['Pillars']!.progress, closeTo(0.6, 1e-9));
      expect(byName['Foundation']!.status, CategoryStatus.completed);
      expect(byName['Pillars']!.status, CategoryStatus.inProgress);
      expect(byName['Roofing']!.status, CategoryStatus.notStarted);
    });

    test('done but unverified to-dos do not count', () {
      final pillars = compute().categories[1];
      expect(pillars.verifiedTodos, 3);
      expect(pillars.awaitingVerification, 1);
    });

    test('category span is earliest to-do start to latest to-do end', () {
      final foundation = compute().categories.first;
      expect(foundation.startDate, DateTime(2026, 8, 3));
      expect(foundation.endDate, DateTime(2026, 9, 2));
    });
  });

  test('falls back to equal weights when a category has no budget', () {
    final cats = [
      categories[0],
      categories[1].copyWith(budget: () => null),
      categories[2],
      categories[3],
    ];
    final p = compute(cats: cats);
    expect(p.usesBudgetWeights, isFalse);
    expect(p.progress, closeTo(0.40, 1e-9));
  });

  test('asOf excludes to-dos verified after that date', () {
    // Foundation's last to-do was verified Sep 3; Pillars' first on Sep 13.
    final p = compute(asOf: DateTime(2026, 9, 5));
    expect(p.categories[0].progress, 1);
    expect(p.categories[1].verifiedTodos, 0);
    expect(p.progress, closeTo(0.25, 1e-9));
  });

  test('empty project is 0% and not started', () {
    final p = compute(cats: const [], items: const []);
    expect(p.progress, 0);
    expect(p.categories, isEmpty);
  });

  test('category without to-dos is 0% and not started', () {
    final p = compute(
      cats: [
        Category(id: 99, projectId: 1, name: 'Empty', budget: 1, sortOrder: 1),
      ],
      items: const [],
    );
    expect(p.categories.single.progress, 0);
    expect(p.categories.single.status, CategoryStatus.notStarted);
  });

  test('planned progress interpolates across to-do dates', () {
    final single = Project.fromJson(project.toJson());
    final p = computeProjectProgress(
      project: single,
      categories: [Category(id: 1, projectId: 1, name: 'A', sortOrder: 1)],
      todos: [
        Todo(
          id: 1,
          categoryId: 1,
          title: 't',
          startDate: DateTime(2026, 9, 1),
          endDate: DateTime(2026, 9, 10),
        ),
      ],
      asOf: DateTime(2026, 9, 5),
    );
    expect(p.plannedProgress, closeTo(0.5, 1e-9));
  });
}

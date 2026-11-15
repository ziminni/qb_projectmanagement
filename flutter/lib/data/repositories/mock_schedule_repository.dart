import '../../routes/routes.dart';
import '../models/app_role.dart';
import '../models/category.dart';
import '../models/todo.dart';
import '../services/notification_service.dart';
import '../services/schedule_rules.dart';
import 'audit_log_repository.dart';
import 'mock_data.dart';
import 'project_repository.dart';
import 'schedule_repository.dart';

/// In-memory schedule data. Enforces the same rules the backend will.
class MockScheduleRepository implements ScheduleRepository {
  MockScheduleRepository({
    required ProjectRepository projects,
    required AuditLogRepository auditLog,
    NotificationService? notifications,
  }) : _projects = projects,
       _auditLog = auditLog,
       _notifications = notifications;

  final ProjectRepository _projects;
  final AuditLogRepository _auditLog;
  final NotificationService? _notifications;
  final _categories = [...MockData.categories];
  final _todos = [...MockData.todos];

  int get _nextCategoryId =>
      _categories.fold(0, (m, c) => c.id > m ? c.id : m) + 1;

  int get _nextTodoId => _todos.fold(0, (m, t) => t.id > m ? t.id : m) + 1;

  @override
  Future<List<Category>> getCategories(int projectId) async =>
      _categories.where((c) => c.projectId == projectId).toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

  @override
  Future<List<Todo>> getTodos(int projectId) async {
    final ids = {
      for (final c in _categories)
        if (c.projectId == projectId) c.id,
    };
    return _todos.where((t) => ids.contains(t.categoryId)).toList();
  }

  @override
  Future<Category> saveCategory(Category category) async {
    final project = await _projects.getProject(category.projectId);
    if (project == null) {
      throw const ScheduleRuleException('Project not found.');
    }
    ScheduleRules.enforce(ScheduleRules.validateCategoryName(category.name));
    ScheduleRules.enforce(ScheduleRules.validateBudget(category.budget));
    final others = _categories
        .where((c) => c.projectId == category.projectId && c.id != category.id)
        .fold<double>(0, (s, c) => s + (c.budget ?? 0));
    ScheduleRules.enforce(
      ScheduleRules.validateBudgetTotal(
        budget: category.budget,
        otherBudgetsTotal: others,
        contractAmount: project.contractAmount,
      ),
    );

    final now = DateTime.now();
    if (category.id == 0) {
      final created = Category(
        id: _nextCategoryId,
        projectId: category.projectId,
        name: category.name.trim(),
        budget: category.budget,
        sortOrder: category.sortOrder,
        createdAt: now,
        updatedAt: now,
      );
      _categories.add(created);
      return created;
    }
    final index = _indexOfCategory(category.id);
    final updated = category.copyWith(
      name: category.name.trim(),
      updatedAt: now,
    );
    _categories[index] = updated;
    return updated;
  }

  @override
  Future<void> deleteCategory(int categoryId) async {
    final index = _indexOfCategory(categoryId);
    final categoryTodos = _todos.where((t) => t.categoryId == categoryId);
    ScheduleRules.enforce(
      ScheduleRules.canDeleteCategory(categoryTodos.toList()),
    );
    _todos.removeWhere((t) => t.categoryId == categoryId);
    _categories.removeAt(index);
  }

  @override
  Future<Todo> saveTodo(Todo todo) async {
    final category = _categories[_indexOfCategory(todo.categoryId)];
    final project = await _projects.getProject(category.projectId);
    if (project == null) {
      throw const ScheduleRuleException('Project not found.');
    }
    ScheduleRules.enforce(ScheduleRules.validateTodoTitle(todo.title));
    ScheduleRules.enforce(
      ScheduleRules.validateTodoDates(
        start: todo.startDate,
        end: todo.endDate,
        project: project,
      ),
    );

    final now = DateTime.now();
    if (todo.id == 0) {
      final created = Todo(
        id: _nextTodoId,
        categoryId: todo.categoryId,
        title: todo.title.trim(),
        startDate: todo.startDate,
        endDate: todo.endDate,
        createdAt: now,
        updatedAt: now,
      );
      _todos.add(created);
      return created;
    }
    // Completion and verification change only through setDone / verify.
    final index = _indexOfTodo(todo.id);
    final updated = _todos[index].copyWith(
      categoryId: todo.categoryId,
      title: todo.title.trim(),
      startDate: todo.startDate,
      endDate: todo.endDate,
      updatedAt: now,
    );
    _todos[index] = updated;
    return updated;
  }

  @override
  Future<void> deleteTodo(int todoId) async {
    final index = _indexOfTodo(todoId);
    ScheduleRules.enforce(ScheduleRules.canDeleteTodo(_todos[index]));
    _todos.removeAt(index);
  }

  @override
  Future<Todo> setDone(
    int todoId, {
    required bool done,
    required int userId,
    int? dailyReportId,
  }) async {
    final index = _indexOfTodo(todoId);
    final todo = _todos[index];
    ScheduleRules.enforce(ScheduleRules.canSetDone(todo, done));
    if (todo.isDone == done) return todo;

    final now = DateTime.now();
    final updated = todo.copyWith(
      isDone: done,
      doneBy: () => done ? userId : null,
      doneAt: () => done ? now : null,
      dailyReportId: dailyReportId == null ? null : () => dailyReportId,
      updatedAt: now,
    );
    _todos[index] = updated;
    await _auditLog.record(
      userId: userId,
      action: done ? 'todo_marked_done' : 'todo_marked_not_done',
      entity: 'todo',
      entityId: todoId,
    );
    if (done) {
      final category = _categories[_indexOfCategory(todo.categoryId)];
      final project = await _projects.getProject(category.projectId);
      await _notifications?.notifyProjectRole(
        category.projectId,
        AppRole.owner,
        type: 'todo_done',
        message:
            '"${todo.title}" was marked done on ${project?.code ?? 'a project'}. '
            'Verify it.',
        link: AppRoutes.todoVerification,
      );
    }
    return updated;
  }

  @override
  Future<Todo> setReportLink(int todoId, int? dailyReportId) async {
    final index = _indexOfTodo(todoId);
    final updated = _todos[index].copyWith(
      dailyReportId: () => dailyReportId,
      updatedAt: DateTime.now(),
    );
    _todos[index] = updated;
    return updated;
  }

  @override
  Future<Todo> verify(int todoId, {required int userId}) async {
    final index = _indexOfTodo(todoId);
    ScheduleRules.enforce(ScheduleRules.canVerify(_todos[index]));

    final now = DateTime.now();
    final updated = _todos[index].copyWith(
      isVerified: true,
      verifiedBy: () => userId,
      verifiedAt: () => now,
      updatedAt: now,
    );
    _todos[index] = updated;
    await _auditLog.record(
      userId: userId,
      action: 'todo_verified',
      entity: 'todo',
      entityId: todoId,
    );
    return updated;
  }

  @override
  Future<Todo> unverify(
    int todoId, {
    required int userId,
    required String reason,
  }) async {
    final index = _indexOfTodo(todoId);
    ScheduleRules.enforce(ScheduleRules.canUnverify(_todos[index], reason));

    final updated = _todos[index].copyWith(
      isVerified: false,
      verifiedBy: () => null,
      verifiedAt: () => null,
      updatedAt: DateTime.now(),
    );
    _todos[index] = updated;
    await _auditLog.record(
      userId: userId,
      action: 'todo_unverified',
      entity: 'todo',
      entityId: todoId,
      details: {'reason': reason.trim()},
    );
    return updated;
  }

  int _indexOfCategory(int id) {
    final index = _categories.indexWhere((c) => c.id == id);
    if (index < 0) throw const ScheduleRuleException('Category not found.');
    return index;
  }

  int _indexOfTodo(int id) {
    final index = _todos.indexWhere((t) => t.id == id);
    if (index < 0) throw const ScheduleRuleException('To-do not found.');
    return index;
  }
}

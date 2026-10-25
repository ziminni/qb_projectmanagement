import '../models/category.dart';
import '../models/todo.dart';

/// Categories and to-dos. Implementations enforce `ScheduleRules` and throw
/// `ScheduleRuleException` when a rule is broken.
abstract interface class ScheduleRepository {
  Future<List<Category>> getCategories(int projectId);

  Future<List<Todo>> getTodos(int projectId);

  /// Creates the category when [category] has id 0, otherwise updates it.
  Future<Category> saveCategory(Category category);

  Future<void> deleteCategory(int categoryId);

  /// Creates the to-do when [todo] has id 0, otherwise updates its title,
  /// dates and category.
  Future<Todo> saveTodo(Todo todo);

  Future<void> deleteTodo(int todoId);

  /// Site engineer checks a to-do off (or back on) in the field, optionally
  /// through a daily report.
  Future<Todo> setDone(
    int todoId, {
    required bool done,
    required int userId,
    int? dailyReportId,
  });

  /// Links a to-do to the daily report it is being accomplished on, or
  /// unlinks it with null.
  Future<Todo> setReportLink(int todoId, int? dailyReportId);

  /// PM verification; only verified to-dos count toward progress.
  Future<Todo> verify(int todoId, {required int userId});

  /// PM-only; requires a reason and is written to the audit log.
  Future<Todo> unverify(
    int todoId, {
    required int userId,
    required String reason,
  });
}

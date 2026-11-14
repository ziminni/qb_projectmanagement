import '../../core/network/api_client.dart';
import '../models/category.dart';
import '../models/json_utils.dart';
import '../models/todo.dart';
import 'schedule_repository.dart';

/// Categories and to-dos, against the CPMS backend.
///
/// The schedule rules live on the server (they need the contract amount and
/// the project dates, both of which a redacted role may not see), so a
/// refusal arrives as the server's own `detail` text and surfaces as a
/// `ScheduleRuleException`/`BusinessRuleException` unchanged. `budget` comes
/// back only for finance roles; everyone else gets the server's `weight`.
class HttpScheduleRepository implements ScheduleRepository {
  HttpScheduleRepository(this._client);

  final ApiClient _client;

  @override
  Future<List<Category>> getCategories(int projectId) async => [
    for (final row in await _client.getRows('projects/$projectId/categories/'))
      Category.fromJson(row),
  ];

  @override
  Future<List<Todo>> getTodos(int projectId) async => [
    for (final row in await _client.getRows('projects/$projectId/todos/'))
      Todo.fromJson(row),
  ];

  @override
  Future<Category> saveCategory(Category category) async {
    final body = {
      'name': category.name.trim(),
      'budget': category.budget,
      'sort_order': category.sortOrder,
    };
    final data = await (category.id == 0
        ? _client.post('projects/${category.projectId}/categories/', body: body)
        : _client.patch('categories/${category.id}/', body: body));
    return Category.fromJson(jsonObject(data));
  }

  @override
  Future<void> deleteCategory(int categoryId) =>
      _client.delete('categories/$categoryId/');

  /// Creating needs the category, which the server checks belongs to an
  /// owner-assigned project; updating sends only the editable fields, so the
  /// done/verified flags can never move through a save.
  @override
  Future<Todo> saveTodo(Todo todo) async {
    final body = {
      'category_id': todo.categoryId,
      'title': todo.title.trim(),
      'start_date': JsonUtils.fromDate(todo.startDate),
      'end_date': JsonUtils.fromDate(todo.endDate),
    };
    final data = await (todo.id == 0
        ? _client.post('todos/', body: body)
        : _client.patch('todos/${todo.id}/', body: body));
    return Todo.fromJson(jsonObject(data));
  }

  @override
  Future<void> deleteTodo(int todoId) => _client.delete('todos/$todoId/');

  /// [dailyReportId] is not sent: a to-do is linked to a report by saving the
  /// report (the server has no link route), so only `done` moves here.
  @override
  Future<Todo> setDone(
    int todoId, {
    required bool done,
    required int userId,
    int? dailyReportId,
  }) async => Todo.fromJson(
    jsonObject(await _client.post('todos/$todoId/done/', body: {'done': done})),
  );

  /// No route: linking happens inside the daily-report save, and the mock
  /// report repository is its only caller.
  @override
  Future<Todo> setReportLink(int todoId, int? dailyReportId) async =>
      throw UnsupportedError(
        'A to-do is linked to a daily report by saving the report.',
      );

  @override
  Future<Todo> verify(int todoId, {required int userId}) async =>
      Todo.fromJson(jsonObject(await _client.post('todos/$todoId/verify/')));

  @override
  Future<Todo> unverify(
    int todoId, {
    required int userId,
    required String reason,
  }) async => Todo.fromJson(
    jsonObject(
      await _client.post(
        'todos/$todoId/unverify/',
        body: {'reason': reason.trim()},
      ),
    ),
  );
}

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../core/network/api_client.dart';
import '../models/category.dart';
import '../models/json_utils.dart';
import '../models/planned_material.dart';
import '../models/project.dart';
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
      if (category.plannedWeeks != null) 'planned_weeks': category.plannedWeeks,
      if (category.plannedDays != null) 'planned_days': category.plannedDays,
      if (category.startDate != null)
        'start_date': JsonUtils.fromDate(category.startDate!),
      if (category.endDate != null)
        'end_date': JsonUtils.fromDate(category.endDate!),
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

  @override
  Future<List<PlannedMaterial>> getPlannedMaterials(int projectId) async => [
    for (final row in await _client.getRows(
      'planned-materials/',
      query: {'project': '$projectId'},
    ))
      PlannedMaterial.fromJson(row, costHidden: !_client.seesFinance),
  ];

  @override
  Future<PlannedMaterial> savePlannedMaterial(PlannedMaterial item) async {
    final body = {
      'project_id': item.projectId,
      'category_id': item.categoryId,
      'name': item.name.trim(),
      'unit': item.unit.trim(),
      'planned_qty': item.plannedQty,
      if (_client.seesFinance) 'unit_cost': item.unitCost,
    };
    final data = await (item.id == 0
        ? _client.post('planned-materials/', body: body)
        : _client.patch('planned-materials/${item.id}/', body: body));
    return PlannedMaterial.fromJson(
      jsonObject(data),
      costHidden: !_client.seesFinance,
    );
  }

  @override
  Future<void> deletePlannedMaterial(int id) =>
      _client.delete('planned-materials/$id/');

  @override
  Future<ItemsExcelPreview> previewBarChartForNewProject({
    required String fileName,
    required Uint8List bytes,
    required DateTime startDate,
    String? sheetName,
  }) async {
    final form = FormData.fromMap({
      'file': MultipartFile.fromBytes(bytes, filename: fileName),
      'start_date': JsonUtils.fromDate(startDate),
      if (sheetName != null && sheetName.isNotEmpty) 'sheet': sheetName,
    });
    final data = jsonObject(
      await _client.post('projects/preview-items/', body: form),
    );
    return ItemsExcelPreview.fromJson(data);
  }

  @override
  Future<ItemsExcelPreview> previewItemsExcel(
    int projectId, {
    required String fileName,
    required Uint8List bytes,
    String? sheetName,
  }) async {
    final form = FormData.fromMap({
      'file': MultipartFile.fromBytes(bytes, filename: fileName),
      'dry_run': 'true',
      if (sheetName != null && sheetName.isNotEmpty) 'sheet': sheetName,
    });
    final data = jsonObject(
      await _client.post('projects/$projectId/import-items/', body: form),
    );
    return ItemsExcelPreview.fromJson(data);
  }

  @override
  Future<int> importItemsExcel(
    int projectId, {
    required String fileName,
    required Uint8List bytes,
    String? sheetName,
    bool replaceExisting = false,
  }) async {
    final form = FormData.fromMap({
      'file': MultipartFile.fromBytes(bytes, filename: fileName),
      if (sheetName != null && sheetName.isNotEmpty) 'sheet': sheetName,
      if (replaceExisting) 'replace': 'true',
    });
    final data = jsonObject(
      await _client.post('projects/$projectId/import-items/', body: form),
    );
    return data['items_imported'] as int? ?? 0;
  }

  @override
  Future<Project> startTimeline(int projectId, DateTime startDate) async {
    final data = jsonObject(
      await _client.post(
        'projects/$projectId/start-timeline/',
        body: {'start_date': JsonUtils.fromDate(startDate)},
      ),
    );
    return Project.fromJson(data);
  }

  @override
  Future<DupaImportPreview> previewDupaExcel(
    int projectId, {
    required String fileName,
    required Uint8List bytes,
    int? categoryId,
    String? sheetName,
  }) async {
    final form = FormData.fromMap({
      'file': MultipartFile.fromBytes(bytes, filename: fileName),
      'dry_run': 'true',
      if (categoryId != null) 'category_id': '$categoryId',
      if (sheetName != null && sheetName.isNotEmpty) 'sheet': sheetName,
    });
    final data = jsonObject(
      await _client.post(
        'projects/$projectId/import-dupa/',
        body: form,
      ),
    );
    return DupaImportPreview.fromJson(data);
  }

  @override
  Future<DupaImportResult> importDupaExcel(
    int projectId, {
    required String fileName,
    required Uint8List bytes,
    int? categoryId,
    String? sheetName,
    List<String>? selectedSheets,
    Map<String, int>? sheetCategoryMap,
  }) async {
    final form = FormData.fromMap({
      'file': MultipartFile.fromBytes(bytes, filename: fileName),
      if (categoryId != null) 'category_id': '$categoryId',
      if (sheetName != null && sheetName.isNotEmpty) 'sheet': sheetName,
      if (selectedSheets != null) 'sheets': jsonEncode(selectedSheets),
      if (sheetCategoryMap != null && sheetCategoryMap.isNotEmpty)
        'sheet_category_map': jsonEncode(sheetCategoryMap),
    });
    final data = jsonObject(
      await _client.post(
        'projects/$projectId/import-dupa/',
        body: form,
      ),
    );
    return DupaImportResult.fromJson(data);
  }

  @override
  Future<Uint8List> downloadBarChartTemplate({String variant = 'combined'}) =>
      _client.getBytes('projects/bar-chart-template/?variant=$variant');
}

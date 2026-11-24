import 'dart:typed_data';

import '../models/category.dart';
import '../models/planned_material.dart';
import '../models/project.dart';
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

  // ---- Planned materials (BOM / DUPA Section C)

  Future<List<PlannedMaterial>> getPlannedMaterials(int projectId);

  Future<PlannedMaterial> savePlannedMaterial(PlannedMaterial item);

  Future<void> deletePlannedMaterial(int id);

  /// Parses a DPWH SF-INFR-41 Bar Chart or 3-column Excel before a project
  /// exists (used inside the Create Project wizard).
  Future<ItemsExcelPreview> previewBarChartForNewProject({
    required String fileName,
    required Uint8List bytes,
    required DateTime startDate,
    String? sheetName,
  });

  /// Parses a DPWH SF-INFR-41 Bar Chart or 3-column Excel (`Item of work | Weeks | Days`).
  Future<ItemsExcelPreview> previewItemsExcel(
    int projectId, {
    required String fileName,
    required Uint8List bytes,
    String? sheetName,
  });

  /// Imports a DPWH SF-INFR-41 Bar Chart or 3-column Excel (`Item of work | Weeks | Days`).
  Future<int> importItemsExcel(
    int projectId, {
    required String fileName,
    required Uint8List bytes,
    String? sheetName,
    bool replaceExisting = false,
  });

  /// Sets the project's actual timeline start date (Notice to Proceed) and
  /// remaps planned relative W1/W2 bars onto real calendar dates.
  Future<Project> startTimeline(int projectId, DateTime startDate);

  /// Parses a DPWH DUPA `.xlsx` workbook and returns a preview without writing.
  /// When [categoryId] is set, targets that specific Item of Work.
  Future<DupaImportPreview> previewDupaExcel(
    int projectId, {
    required String fileName,
    required Uint8List bytes,
    int? categoryId,
    String? sheetName,
  });

  /// Imports a DPWH DUPA `.xlsx` workbook into the project's Items of Work
  /// and Planned Materials (or into a single Item of Work when [categoryId] is set).
  Future<DupaImportResult> importDupaExcel(
    int projectId, {
    required String fileName,
    required Uint8List bytes,
    int? categoryId,
    String? sheetName,
    List<String>? selectedSheets,
    Map<String, int>? sheetCategoryMap,
  });

  /// Downloads the exact DPWH SF-INFR-41 Bar Chart Excel template.
  /// [variant] is `'original'`, `'revised'`, or `'combined'`.
  Future<Uint8List> downloadBarChartTemplate({String variant = 'original'});
}
